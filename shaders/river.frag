#include <flutter/runtime_effect.glsl>

// ============================================================
// 可从 Dart 端传入的 uniform 参数
// ============================================================
uniform float uTime;       // 时间（秒），驱动水流动画
uniform float uCanvasW;    // 画布宽度（像素）
uniform float uCanvasH;    // 画布高度（像素）
uniform float uSpeed;      // 【可调】水流速度，建议 0.1~0.6，当前 Dart 端约 0.2~0.4
uniform float uTurbulence; // 【可调】湍流强度，影响河道弯曲和纹理扰动，建议 0.3~1.0
uniform float uWidth;      // 【可调】河道基础半宽，建议 0.10~0.25，当前 Dart 端约 0.16~0.20
uniform float uRed;        // 主题色 R（0~1）
uniform float uGreen;      // 主题色 G（0~1）
uniform float uBlue;       // 主题色 B（0~1）
uniform float uOffset;     // 河道纵向偏移（里程/10），驱动河床滚动
uniform float uUseRealPath; // 是否使用真实路径 (0 或 1)
uniform float uPath[32];    // 真实路径偏移数据
uniform float uPulse;       // 脉冲进度 (0.0 - 1.0)
uniform float uPulseX;      // 脉冲中心 X (UV 坐标)
uniform float uPulseY;      // 脉冲中心 Y

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

// 插值函数，用于从 uPath 中平滑获取偏移
float get_path_offset(float y) {
    float idx = (y * 0.5 + 0.5) * 31.0;
    int i = int(floor(idx));
    int j = min(i + 1, 31);
    float f = fract(idx);
    return mix(uPath[i], uPath[j], f);
}

// ============================================================
// 丝绸流水纹理
// 内部硬编码参数说明（后期如需暴露为 uniform 可提取）：
//   uv1 的 3.0 / 3.5 —— 第一层纹理的横/纵密度，越大纹理越细密
//   uv2 的 5.0 / 6.0 —— 第二层纹理的横/纵密度
//   spd * 2.0 / 1.3   —— 两层纹理的流动速度比，制造错位感
//   turb * 0.4         —— domain warp 扰动幅度，越大纹理越扭曲
//   0.6 / 0.4          —— 两层纹理的混合比例
// ============================================================
float flowing_silk(vec2 uv, float t, float spd, float turb) {
    vec2 uv1 = vec2(uv.x * 3.0, uv.y * 3.5 - t * spd * 2.0);
    vec2 uv2 = vec2(uv.x * 5.0 + 0.7, uv.y * 6.0 - t * spd * 1.3);

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

    // ============================================================
    // 1. 河床蜿蜒路径
    //    0.25  —— 【可调】蜿蜒幅度，越大河道越弯，建议 0.15~0.35
    //    1.5   —— 【可调】蜿蜒频率，越大弯道越密，建议 1.0~2.5
    //    0.05  —— 【可调】次级弯曲幅度（受 uTurbulence 调制）
    //    3.5   —— 【可调】次级弯曲频率
    // ============================================================
    float scrollY = p.y + uOffset * 2.0;
    float path;
    if (uUseRealPath > 0.5) {
        path = get_path_offset(p.y) * 0.5;
    } else {
        path = sin(scrollY * 1.5) * 0.25;
    }
    path += cos(scrollY * 3.5) * 0.05 * uTurbulence;

    // ============================================================
    // 2. 河道宽窄变化
    //    0.3   —— 【可调】宽窄变化幅度，0=完全等宽，0.3=±30%变化，建议 0.1~0.3
    //    2.3   —— 【可调】宽窄变化频率，越大变化越密
    //    0.1   —— 【可调】次级宽窄幅度（受 uTurbulence 调制）
    // ============================================================
    float widthVar = 1.0 + sin(scrollY * 2.3 + 0.5) * 0.3
                         + sin(scrollY * 5.1) * 0.1 * uTurbulence;
    float halfW = uWidth * widthVar;

    // 3. 河床坐标系下的流水纹理
    vec2 riverUV = vec2(p.x - path, scrollY);
    float flow = flowing_silk(riverUV, uTime, uSpeed, uTurbulence);

    // 4. 距离场
    float dist = abs(riverUV.x);

    // ============================================================
    // 核心高亮（中心光带）
    //    3.5   —— 【可调】高光宽窄变化频率，越大一屏内变化越多，建议 2.0~5.0
    //    25.0 / 30.0 —— 【可调】coreDecay 范围 [25, 55]，值越大光带越窄
    //    0.35 / 0.2  —— 【可调】亮度范围 [0.35, 0.55]，值越大越亮
    // ============================================================
    float coreN = noise(vec2(scrollY * 3.5, 0.7));
    float coreDecay = 25.0 + coreN * 30.0;
    float core = exp(-dist * coreDecay) * (0.35 + coreN * 0.2);

    // ============================================================
    // 丝绸纹理带（主要的河流纹理区域）
    //    1.2   —— 【可调】纹理扩散系数，乘以 halfW 就是纹理最大可见半径
    //            越大纹理扩散越远，建议 1.0~2.0
    // ============================================================
    float strands = smoothstep(halfW * 1.2, 0.0, dist) * flow;

    // ============================================================
    // 环境辉光（河道外的淡淡光晕）
    //    10.0  —— 【可调】辉光衰减速度，值越大辉光越窄越集中，建议 5.0~15.0
    //    0.25  —— 【可调】辉光强度，建议 0.1~0.4
    // ============================================================
    float glow = exp(-dist * 10.0) * 0.25;

    // 5. 色彩合成
    vec3 baseColor = vec3(uRed, uGreen, uBlue);
    // ============================================================
    //    0.55  —— 【可调】核心高亮的白色混入比例，越大越白，建议 0.4~0.75
    // ============================================================
    vec3 coreColor = mix(baseColor, vec3(0.88, 0.95, 0.98), 0.55);
    vec3 edgeColor = baseColor * 0.5;

    vec3 riverColor = mix(edgeColor, baseColor, strands);
    riverColor = mix(riverColor, coreColor, core);

    // ============================================================
    // 6. 背景
    //    0.02  —— 【可调】纸质噪点强度，建议 0.01~0.03
    //    0.97,0.97,0.96 —— 【可调】背景色 RGB
    // ============================================================
    float grain = (hash(uv + uTime * 0.01) - 0.5) * 0.02;
    vec3 bgColor = vec3(0.97, 0.97, 0.96) + grain;

    // ============================================================
    //    1.3   —— 【可调】strands 对最终可见度的放大系数
    //            越大纹理区域越明显、扩散越远，建议 1.0~2.0
    // ============================================================
    float mask = clamp(strands * 1.3 + glow + core, 0.0, 1.0);
    vec3 finalColor = mix(bgColor, riverColor + baseColor * glow, mask);

    // ============================================================
    // 7. 祭江脉冲效果 (金色波纹)
    // ============================================================
    if (uPulse > 0.0) {
        vec2 pulseCenter = vec2(uPulseX, uPulseY);
        float d = distance(uv, pulseCenter);
        // 波纹环带计算
        float ring = smoothstep(uPulse, uPulse - 0.1, d) * smoothstep(uPulse - 0.2, uPulse - 0.1, d);
        vec3 gold = vec3(1.0, 0.84, 0.0); // 黄金色
        finalColor += gold * ring * 0.6 * (1.0 - uPulse);
        
        // 全局亮度微增 (呼吸感)
        finalColor += gold * 0.1 * (1.0 - uPulse);
    }

    fragColor = vec4(finalColor, 1.0);
}
