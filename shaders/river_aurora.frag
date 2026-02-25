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
uniform float uUseRealPath;
uniform float uPath[32];
uniform float uPulse;
uniform float uPulseX;
uniform float uPulseY;
uniform float uBgR;
uniform float uBgG;
uniform float uBgB;

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

float fbm(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 4; i++) {
        v += a * noise(p);
        p *= 2.0;
        a *= 0.5;
    }
    return v;
}

float get_path_offset(float y) {
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
    
    // 极光般的蜿蜒路径
    float path;
    if (uUseRealPath > 0.5) {
        path = get_path_offset(p.y) * 0.5;
    } else {
        path = sin(scrollY * 1.2 + uTime * 0.2) * 0.3 * uTurbulence;
        path += cos(scrollY * 2.5 - uTime * 0.1) * 0.1;
    }

    float dx = p.x - path;
    float dist = abs(dx);

    // 极光变幻色彩
    float colorShift = fbm(vec2(scrollY * 0.5, uTime * 0.1));
    vec3 color1 = vec3(0.0, 1.0, 0.8); // 翠青
    vec3 color2 = vec3(0.5, 0.0, 1.0); // 幻紫
    vec3 color3 = vec3(0.0, 0.5, 1.0); // 湛蓝
    
    vec3 auroraColor = mix(color1, color2, sin(uTime * 0.3 + scrollY) * 0.5 + 0.5);
    auroraColor = mix(auroraColor, color3, colorShift);

    // 模拟极光的垂直褶皱感 (Domain Warping)
    float warp = fbm(vec2(dx * 4.0, scrollY * 2.0 - uTime * uSpeed * 2.0));
    float auroraStrands = smoothstep(uWidth * 1.5, 0.0, dist + warp * 0.1);
    
    // 极光特有的垂直放射状纹理
    float verticalLines = pow(fbm(vec2(dx * 10.0 + uTime * 0.1, scrollY * 0.2)), 2.0);
    auroraStrands *= (0.6 + verticalLines * 0.4);

    // 强烈的核心辉光
    float core = exp(-dist * 15.0) * 0.8;
    float outerGlow = exp(-dist * 5.0) * 0.4;

    // 背景随主题/深色模式，极光风格保留淡淡星云
    float nebula = fbm(uv * 1.5 + uTime * 0.02) * 0.08;
    vec3 bgColor = vec3(uBgR, uBgG, uBgB) + auroraColor * nebula;

    // 最终合成
    vec3 riverColor = auroraColor * (auroraStrands + core + outerGlow);
    // 叠加一点主题色倾向
    riverColor += vec3(uRed, uGreen, uBlue) * outerGlow * 0.2;

    float alpha = clamp(auroraStrands + core + outerGlow, 0.0, 1.0);
    vec3 finalColor = mix(bgColor, riverColor, alpha);

    // 祭江脉冲效果
    if (uPulse > 0.0) {
        vec2 pulseCenter = vec2(uPulseX, uPulseY);
        float d = distance(uv, pulseCenter);
        float ring = smoothstep(uPulse, uPulse - 0.1, d) * smoothstep(uPulse - 0.2, uPulse - 0.1, d);
        vec3 gold = vec3(1.0, 0.9, 0.3);
        finalColor += gold * ring * 0.7 * (1.0 - uPulse);
    }

    fragColor = vec4(finalColor, 1.0);
}
