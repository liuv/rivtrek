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
    return mix(
        mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
        mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x),
        f.y
    );
}

// 3 octave FBM
float fbm(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    vec2 shift = vec2(100.0);
    for (int i = 0; i < 3; i++) {
        v += a * noise(p);
        p = p * 2.1 + shift;
        a *= 0.5;
    }
    return v;
}

void main() {
    vec2 res = vec2(uCanvasW, uCanvasH);
    vec2 uv = FlutterFragCoord().xy / res;
    vec2 p = (uv * 2.0 - 1.0);
    p.x *= res.x / res.y;

    float t = uTime;
    float spd = uSpeed;
    float turb = uTurbulence;

    // 1. 河床蜿蜒路径
    float scrollY = p.y + uOffset * 2.0;
    float path = sin(scrollY * 1.5) * 0.25
               + cos(scrollY * 3.5) * 0.05 * turb;

    float dx = p.x - path;
    float dist = abs(dx);

    // 2. 高斯衰减包络
    float envelope = exp(-dist * dist / (uWidth * uWidth * 2.0));

    // 3. Domain Warping
    vec2 baseUV = vec2(dx * 3.0, scrollY * 2.5);

    float warpX1 = fbm(vec2(baseUV.y * 0.8 - t * spd * 0.6, dx * 2.0)) * turb * 0.6;
    float warpX2 = fbm(vec2(dx * 3.0, baseUV.y * 1.5 - t * spd * 1.2)) * turb * 0.3;

    vec2 warpedUV = baseUV;
    warpedUV.x += warpX1 + warpX2;
    warpedUV.y -= t * spd * 2.0;

    // 4. 丝绸纹理 + 纤维条纹
    float silk1 = fbm(warpedUV);
    float silk2 = fbm(warpedUV * 1.8 + 5.3);

    float fibers = abs(sin((silk1 + silk2) * 3.14159 * 2.5));
    fibers = pow(fibers, 0.7);

    float silkTex = silk1 * 0.4 + silk2 * 0.3 + fibers * 0.3;

    // 5. 核心高亮
    float coreNoise = fbm(vec2(scrollY * 0.8 - t * spd * 0.5, 0.7));
    float coreHalfW = 0.02 + coreNoise * 0.06;
    float core = smoothstep(coreHalfW, 0.0, dist) * (0.4 + coreNoise * 0.3);

    // 6. 色彩
    vec3 baseColor = vec3(uRed, uGreen, uBlue);
    vec3 coreColor = mix(baseColor, vec3(0.9, 0.96, 1.0), 0.6);
    vec3 deepColor = baseColor * 0.45;

    vec3 waterColor = mix(deepColor, baseColor, silkTex);
    waterColor = mix(waterColor, coreColor, core);

    float glow = exp(-dist * 7.0) * 0.3;

    // 7. 背景
    float grain = (hash(uv + t * 0.01) - 0.5) * 0.02;
    vec3 bgColor = vec3(0.97, 0.97, 0.96) + grain;

    float visibility = envelope * (silkTex * 0.7 + 0.3) + glow + core * envelope;
    visibility = clamp(visibility, 0.0, 1.0);

    vec3 finalColor = mix(bgColor, waterColor + baseColor * glow, visibility);

    fragColor = vec4(finalColor, 1.0);
}
