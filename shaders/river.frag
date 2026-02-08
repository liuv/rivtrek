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

// 基于 UV 变换的丝绸流水算法
float flowing_silk(vec2 uv, float t, float spd, float turb) {
    // 1. 双层 UV 滚动：层 1 快速向下，层 2 慢速向斜下，产生错位流动感
    vec2 uv1 = uv * 3.5 + vec2(0.0, -t * spd * 2.0);
    vec2 uv2 = uv * 6.0 + vec2(t * 0.1, -t * spd * 1.2);
    
    // 2. 引入领域扭曲 (Domain Warping)：让流动看起来更有流体质感而非简单的平移
    float d = noise(uv1 + t * 0.2) * turb * 0.5;
    
    float n1 = noise(uv1);
    float n2 = noise(uv2 + d);
    
    return (n1 * 0.6 + n2 * 0.4);
}

void main() {
    vec2 res = vec2(uCanvasW, uCanvasH);
    vec2 uv = FlutterFragCoord().xy / res.xy;
    vec2 p = (uv * 2.0 - 1.0);
    p.x *= res.x / res.y;

    // 1. 固定河床路径 (形状完全由里程 uOffset 决定，不随时间晃动)
    float scrollY = p.y + uOffset * 2.0; 
    float path = sin(scrollY * 1.5) * 0.25;
    path += cos(scrollY * 3.5) * 0.05 * uTurbulence;
    
    // 2. 内部流水特效 (UV 坐标变换)
    // 我们在基于河床的坐标系上进行内容偏移
    vec2 riverBedUV = vec2(p.x - path, scrollY);
    float flow = flowing_silk(riverBedUV, uTime, uSpeed, uTurbulence);
    
    // 3. 计算距离场和光效
    float dist = abs(riverBedUV.x);
    // 核心高亮线 (同样固定在河床中心)
    float core = exp(-dist * 50.0) * 1.2;
    // 丝绸细纹
    float strands = smoothstep(uWidth * 1.5, 0.0, dist) * flow;
    // 环境辉光
    float glow = exp(-dist * 8.0) * 0.35;

    // 4. 色彩与合成 (保持之前的惊艳视觉)
    vec3 baseColor = vec3(uRed, uGreen, uBlue);
    vec3 color_core = mix(baseColor, vec3(0.9, 1.0, 1.0), 0.75);
    vec3 color_edge = baseColor * 0.5;

    vec3 riverColor = mix(color_edge, baseColor, strands);
    riverColor = mix(riverColor, color_core, core);
    
    // 暖白背景 + 噪点
    float grain = (hash(uv + uTime * 0.01) - 0.5) * 0.02;
    vec3 bgColor = vec3(0.97, 0.97, 0.96) + grain;

    float mask = clamp(strands * 1.5 + glow + core, 0.0, 1.0);
    vec3 finalColor = mix(bgColor, riverColor + baseColor * glow, mask);

    fragColor = vec4(finalColor, 1.0);
}
