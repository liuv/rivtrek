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
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
               mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// 恢复最初惊艳的领域扭曲 (Domain Warping) 算法
float fbm_warped(vec2 p, float time, float speed) {
    float v = 0.0;
    float a = 0.5;
    // 关键：时间只作用于扭曲场，产生“流动”的灵动感
    vec2 shift = vec2(100.0);
    for (int i = 0; i < 5; ++i) {
        // time * speed 驱动内部波纹，而不是外部坐标
        float n = noise(p + time * speed);
        v += a * n;
        p = p * 2.0 + shift + vec2(n * 0.4, 0.0);
        a *= 0.5;
    }
    return v;
}

void main() {
    vec2 res = vec2(uCanvasW, uCanvasH);
    vec2 uv = FlutterFragCoord().xy / res.xy;
    vec2 p = (uv * 2.0 - 1.0);
    p.x *= res.x / res.y;

    // 1. 恢复优雅的 S 路径
    float scrollY = p.y + uOffset * 2.0; 
    float path = sin(scrollY * 1.5) * 0.3;
    path += cos(scrollY * 3.5) * 0.05 * uTurbulence;
    
    // 2. 核心：领域扭曲产生的丝绸感内容
    vec2 flowUV = vec2(p.x - path, scrollY);
    float flow = fbm_warped(flowUV * 4.0, uTime, uSpeed);
    
    // 3. 计算边缘和高亮 (恢复美感)
    float dist = abs(p.x - path);
    float core = exp(-dist * 40.0) * 1.1; // 增加中心亮白感
    float strands = smoothstep(uWidth * 1.5, 0.0, dist) * flow;
    float glow = exp(-dist * 8.0) * 0.35;

    // 4. 色彩 (电光青 -> 深海蓝)
    vec3 baseColor = vec3(uRed, uGreen, uBlue);
    vec3 color_core = mix(baseColor, vec3(0.85, 1.0, 1.0), 0.7);
    vec3 color_edge = baseColor * 0.5;

    vec3 riverColor = mix(color_edge, baseColor, strands);
    riverColor = mix(riverColor, color_core, core);
    
    vec3 finalGlow = baseColor * glow * (1.2 + flow);
    
    // 恢复暖白纸张背景 (增加极细微噪点)
    float grain = (hash(uv + uTime * 0.01) - 0.5) * 0.025;
    vec3 bgColor = vec3(0.97, 0.97, 0.96) + grain;

    float mask = clamp(strands * 1.5 + glow + core, 0.0, 1.0);
    vec3 finalColor = mix(bgColor, riverColor + finalGlow, mask);

    fragColor = vec4(finalColor, 1.0);
}
