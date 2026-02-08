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
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
               mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// 沿河道纵向流动的丝绸纹理
float flowing_silk(vec2 uv, float t, float spd, float turb) {
    // 两层 UV 都以纵向（y）为主方向滚动，保证纹理顺着河道
    vec2 uv1 = vec2(uv.x * 3.0, uv.y * 3.5 - t * spd * 2.0);
    vec2 uv2 = vec2(uv.x * 5.0 + 0.7, uv.y * 6.0 - t * spd * 1.3);

    // 轻量 domain warp：仅横向微扰，不改变纵向主流向
    float warp = noise(uv1 + t * 0.15) * turb * 0.4;
    uv2.x += warp;

    float n1 = noise(uv1);
    float n2 = noise(uv2);

    return n1 * 0.6 + n2 * 0.4;
}

void main() {
    vec2 res = vec2(uCanvasW, uCanvasH);
    vec2 uv = FlutterFragCoord().xy / res;
    vec2 p = (uv * 2.0 - 1.0);
    p.x *= res.x / res.y;

    // 1. 河床蜿蜒路径（由里程 uOffset 驱动）
    float scrollY = p.y + uOffset * 2.0;
    float path = sin(scrollY * 1.5) * 0.25;
    path += cos(scrollY * 3.5) * 0.05 * uTurbulence;

    // 2. 河道宽窄变化：沿河道方向呼吸式宽窄
    float widthVar = 1.0 + sin(scrollY * 2.3 + 0.5) * 0.3
                         + sin(scrollY * 5.1) * 0.1 * uTurbulence;
    float halfW = uWidth * widthVar;

    // 3. 河床坐标系下的流水纹理
    vec2 riverUV = vec2(p.x - path, scrollY);
    float flow = flowing_silk(riverUV, uTime, uSpeed, uTurbulence);

    // 4. 距离场
    float dist = abs(riverUV.x);

    // 核心高亮：柔和发光，不刺眼
    float core = exp(-dist * 25.0) * 0.45;
    // 丝绸纹理带
    float strands = smoothstep(halfW * 1.5, 0.0, dist) * flow;
    // 环境辉光
    float glow = exp(-dist * 7.0) * 0.3;

    // 5. 色彩合成
    vec3 baseColor = vec3(uRed, uGreen, uBlue);
    vec3 coreColor = mix(baseColor, vec3(0.88, 0.95, 0.98), 0.55);
    vec3 edgeColor = baseColor * 0.5;

    vec3 riverColor = mix(edgeColor, baseColor, strands);
    riverColor = mix(riverColor, coreColor, core);

    // 6. 暖白背景 + 纸质噪点
    float grain = (hash(uv + uTime * 0.01) - 0.5) * 0.02;
    vec3 bgColor = vec3(0.97, 0.97, 0.96) + grain;

    float mask = clamp(strands * 1.5 + glow + core, 0.0, 1.0);
    vec3 finalColor = mix(bgColor, riverColor + baseColor * glow, mask);

    fragColor = vec4(finalColor, 1.0);
}
