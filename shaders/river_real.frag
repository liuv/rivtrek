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
// 传入32个点，代表当前段的路径偏移
uniform float uPath[32]; 

out vec4 fragColor;

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
               mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float flowing_silk(vec2 uv, float t, float spd, float turb) {
    vec2 uv1 = vec2(uv.x * 3.0, uv.y * 3.5 - t * spd * 2.0);
    vec2 uv2 = vec2(uv.x * 5.0 + 0.7, uv.y * 6.0 - t * spd * 1.3);
    float warp = noise(uv1 + t * 0.15) * turb * 0.4;
    uv2.x += warp;
    float n1 = noise(uv1);
    float n2 = noise(uv2);
    return n1 * 0.6 + n2 * 0.4;
}

// 插值函数，用于从 uPath 中平滑获取偏移
float get_path_offset(float y) {
    // y 映射到 0-31 索引
    float idx = (y * 0.5 + 0.5) * 31.0;
    int i = int(floor(idx));
    int j = min(i + 1, 31);
    float f = fract(idx);
    return mix(uPath[i], uPath[j], f);
}

void main() {
    vec2 res = vec2(uCanvasW, uCanvasH);
    vec2 uv = FlutterFragCoord().xy / res;
    vec2 p = (uv * 2.0 - 1.0);
    p.x *= res.x / res.y;

    float scrollY = p.y + uOffset * 2.0;
    
    // 使用真实路径数据
    float path = get_path_offset(p.y) * 0.5; // 0.5 是缩放系数，防止偏移出屏
    path += cos(scrollY * 3.5) * 0.05 * uTurbulence; // 保留一点高频扰动

    float widthVar = 1.0 + sin(scrollY * 2.3 + 0.5) * 0.3
                         + sin(scrollY * 5.1) * 0.1 * uTurbulence;
    float halfW = uWidth * widthVar;

    vec2 riverUV = vec2(p.x - path, scrollY);
    float flow = flowing_silk(riverUV, uTime, uSpeed, uTurbulence);
    float dist = abs(riverUV.x);

    float coreN = noise(vec2(scrollY * 3.5, 0.7));
    float coreDecay = 25.0 + coreN * 30.0;
    float core = exp(-dist * coreDecay) * (0.35 + coreN * 0.2);

    float strands = smoothstep(halfW * 1.2, 0.0, dist) * flow;
    float glow = exp(-dist * 10.0) * 0.25;

    vec3 baseColor = vec3(uRed, uGreen, uBlue);
    vec3 coreColor = mix(baseColor, vec3(0.88, 0.95, 0.98), 0.55);
    vec3 edgeColor = baseColor * 0.5;

    vec3 riverColor = mix(edgeColor, baseColor, strands);
    riverColor = mix(riverColor, coreColor, core);

    float grain = (hash(uv + uTime * 0.01) - 0.5) * 0.02;
    vec3 bgColor = vec3(0.97, 0.97, 0.96) + grain;

    float mask = clamp(strands * 1.3 + glow + core, 0.0, 1.0);
    vec3 finalColor = mix(bgColor, riverColor + baseColor * glow, mask);

    fragColor = vec4(finalColor, 1.0);
}
