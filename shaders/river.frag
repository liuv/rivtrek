#include <flutter/runtime_effect.glsl>

uniform float uTime;
uniform float uCanvasW;
uniform float uCanvasH;
uniform float uSpeed;
uniform float uTurbulence; 
uniform float uWidth;      
uniform float uRed;
uniform float uGreen;
uniform float uBlue;
uniform float uOffset;

out vec4 fragColor;

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// 恢复最初惊艳的丝绸感 FBM
float fbm(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 5; ++i) {
        v += a * noise(p);
        p *= 2.0;
        a *= 0.5;
    }
    return v;
}

void main() {
    vec2 res = vec2(uCanvasW, uCanvasH);
    vec2 uv = FlutterFragCoord().xy / res.xy;
    vec2 p = (uv * 2.0 - 1.0);
    p.x *= res.x / res.y;

    // 1. 恢复 S 曲线的动态扭动 (用来检验 uTime 是否生效)
    // 我们在里程 scrollY 上叠加 uTime
    float scrollY = p.y + uOffset * 2.0; 
    float path = sin(scrollY * 1.5 + uTime * 0.6) * 0.25; 
    path += cos(scrollY * 3.0 - uTime * 0.4) * 0.05 * uTurbulence;
    
    // 2. 恢复丝绸质感内容
    vec2 flowUV = vec2(p.x - path, scrollY);
    float flow = fbm(flowUV * 4.0 + uTime * 0.1); 

    // 3. 计算边缘和高亮 (恢复之前的美感)
    float dist = abs(p.x - path);
    float core = exp(-dist * 45.0) * 1.2;
    float strands = smoothstep(uWidth * 1.5, 0.0, dist) * flow;
    float glow = exp(-dist * 8.0) * 0.35;

    // 4. 色彩还原
    vec3 baseColor = vec3(uRed, uGreen, uBlue);
    vec3 color_core = mix(baseColor, vec3(0.9, 1.0, 1.0), 0.7);
    vec3 color_edge = baseColor * 0.5;

    vec3 riverColor = mix(color_edge, baseColor, strands);
    riverColor = mix(riverColor, color_core, core);
    
    // 5. 恢复暖白背景质感
    float grain = (hash(uv + uTime * 0.01) - 0.5) * 0.02;
    vec3 bgColor = vec3(0.97, 0.97, 0.96) + grain;

    float mask = clamp(strands * 1.5 + glow + core, 0.0, 1.0);
    vec3 finalColor = mix(bgColor, riverColor + baseColor * glow, mask);

    fragColor = vec4(finalColor, 1.0);
}
