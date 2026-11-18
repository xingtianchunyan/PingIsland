// 全息箔面 shader——移植自 Kimi 精选案例「宝可梦全息卡片」的光学实现
// （k3-pokemon-card.ok.kimi.link，两层交叉衍射光栅 + 八种镭射工艺 + 星光层）。
// SwiftUI .layerEffect 调用：对卡面内容做"油墨调制"合成——暗部保持清晰、亮部泛箔。
// 全部为视角纯函数：静止零重绘，拖拽/倾斜时随帧变化。

#include <metal_stdlib>
using namespace metal;

namespace Foil {

// ---- 基础工具 ----

float hash21(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453123);
}
float2 hash22(float2 p) {
    float3 p3 = fract(float3(p.xyx) * float3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

// 绕灰轴色相旋转（Rodrigues）
float3 hueShift(float3 c, float a) {
    float3 k = float3(0.57735);
    float ca = cos(a);
    return c * ca + cross(k, c) * sin(a) + k * dot(k, c) * (1.0 - ca);
}

float patOn(float mask, int k) {
    return mask >= 0 ? fmod(floor(mask / pow(2.0, float(k))), 2.0) : 0.0;
}

// voronoi：x=F1 y=F2-F1 z/w=单元随机数（3x3 邻域）
float4 voronoi(float2 p) {
    float2 g = floor(p);
    float f1 = 8.0, f2 = 8.0;
    float2 id = float2(0.0);
    for (int j = -1; j <= 1; j++)
        for (int i = -1; i <= 1; i++) {
            float2 c = g + float2(float(i), float(j));
            float2 pt = c + hash22(c);
            float d = length(p - pt);
            if (d < f1) { f2 = f1; f1 = d; id = c; }
            else if (d < f2) { f2 = d; }
        }
    return float4(f1, f2 - f1, hash21(id + 2.3), hash21(id + 6.1));
}

// 水波：三个衰减中心的 groove 角度扰动
float rippleAngle(float2 p) {
    float2 c1 = float2(-0.9, 1.2);
    float2 c2 = float2(1.1, -0.6);
    float2 c3 = float2(0.1, 2.2);
    float a = 0.0;
    float d1 = length(p - c1); a += 0.38 * sin(d1 * 8.0) * exp(-d1 * 0.9);
    float d2 = length(p - c2); a += 0.32 * sin(d2 * 8.0) * exp(-d2 * 0.9);
    float d3 = length(p - c3); a += 0.28 * sin(d3 * 8.0) * exp(-d3 * 0.9);
    return a;
}

// ---- CIE 1931 配色（分段高斯拟合，Wyman 2013）----

float pg(float x, float mu, float s1, float s2) {
    float s = x < mu ? s1 : s2;
    float t = (x - mu) / s;
    return exp(-0.5 * t * t);
}
float3 cie1931(float w) {
    float X = 1.056 * pg(w, 599.8, 37.9, 31.0)
            + 0.362 * pg(w, 442.0, 16.0, 26.7)
            - 0.065 * pg(w, 501.1, 20.4, 26.2);
    float Y = 0.821 * pg(w, 568.8, 46.9, 40.5)
            + 0.286 * pg(w, 530.9, 16.3, 31.1);
    float Z = 1.217 * pg(w, 437.0, 11.8, 36.0)
            + 0.681 * pg(w, 459.0, 26.0, 13.8);
    return float3(X, Y, Z);
}
float3 xyz2srgb(float3 c) {
    return float3( 3.2406 * c.x - 1.5372 * c.y - 0.4986 * c.z,
                  -0.9689 * c.x + 1.8758 * c.y + 0.0415 * c.z,
                   0.0557 * c.x - 0.2040 * c.y + 1.0570 * c.z);
}

// ---- 解析环境（银底反射）：灰房 + 跟随光源的窄亮带 + 软晕 + 冷补光 ----

float3 envColor(float3 d, float rough, float3 lightDir, float metalGain, float tintSel) {
    float up = d.y * 0.5 + 0.5;
    float3 c = mix(float3(0.030, 0.033, 0.040), float3(0.090, 0.100, 0.115), up);
    float3 kd = normalize(lightDir);
    float3 hAxis = normalize(cross(kd, float3(0.0, 1.0, 0.0)));
    float3 sAxis = normalize(cross(hAxis, kd));
    float devS = dot(d, sAxis);
    float devL = max(fabs(dot(d, hAxis)) - 0.55, 0.0);
    float face = step(0.0, dot(d, kd));
    float sk = face * exp(-devS * devS * mix(900.0, 60.0, rough))
                    * exp(-devL * devL * mix(80.0, 12.0, rough));
    // 银 5.0/5.3/5.8；金 6.4/4.4/1.8
    float3 key = tintSel > 0.5 ? float3(6.4, 4.4, 1.8) : float3(5.0, 5.3, 5.8);
    c += key * sk * metalGain;
    c += float3(0.16, 0.18, 0.21) * pow(max(dot(d, kd), 0.0), 2.0);
    float3 fd = normalize(float3(0.75, -0.25, 0.45));
    c += float3(0.12, 0.14, 0.18) * pow(max(dot(d, fd), 0.0), mix(24.0, 3.0, rough));
    return c;
}

// ---- 单层线性衍射光栅：反解光栅方程，逐阶取精确波长 ----

float3 gratingLayer(float3 inDir, float3 V, float3 T, float3 B,
                    float pitchNm, float sharpT, float kWin) {
    float dt = dot(V, T) - dot(inDir, T);
    float dev = dot(V, B) - dot(inDir, B);
    float azWeight = exp(-dt * dt * sharpT);
    float wSpec = exp(-dev * dev * kWin);
    float3 acc = float3(0.0);
    float nOrd = 0.0;
    for (int m = -8; m <= 8; m++) {
        if (m == 0) continue;
        float lam = pitchNm * dev / float(m);
        if (lam < 380.0 || lam > 720.0) continue;
        float mf = float(m);
        float env = 1.0 / (1.0 + 0.25 * mf * mf); // 闪耀包络
        acc += cie1931(lam) * env;
        nOrd += 1.0;
    }
    acc /= (0.5 + 0.5 * nOrd);
    return acc * (azWeight * wSpec);
}

// ---- 星光层：稀疏压印星形微光栅，十字闪光随视角迁移 ----

float3 starField(float2 p, float3 N, float3 V, float3 L, float3 bx, float3 by,
                 float density) {
    float3 H = normalize(L + V);
    float3 sum = float3(0.0);
    float cell = 0.16;
    float2 base = floor(p / cell);
    for (int i = -1; i <= 1; i++)
        for (int j = -1; j <= 1; j++) {
            float2 c = base + float2(float(i), float(j));
            float h0 = hash21(c);
            if (h0 > density) continue;
            float2 jitter = hash22(c + 11.0);
            float2 center = (c + 0.15 + 0.7 * jitter) * cell;
            float2 rel = p - center;
            // 压印星形：任意角度可见的柔和高光
            float emboss = exp(-dot(rel, rel) * 900.0) * 0.6;
            // 十字耀斑：两条各向异性亮杆 + 核心，由微法线 N·H 门控
            float cone = 0.35;
            float3 nS = normalize(N + (bx * (jitter.x - 0.5) + by * (jitter.y - 0.5)) * cone);
            float gate = pow(max(dot(nS, H), 0.0), 60.0);
            float2 ax = normalize(float2(1.0, 0.35));
            float2 ay = normalize(float2(-0.35, 1.0));
            float bar = exp(-pow(abs(dot(rel, float2(-ax.y, ax.x))) * 260.0, 1.2))
                      + exp(-pow(abs(dot(rel, float2(-ay.y, ay.x))) * 260.0, 1.2));
            float core = exp(-dot(rel, rel) * 5200.0) * 3.0;
            float flash = (bar + core) * gate;
            float3 tint = hueShift(float3(1.0), (h0 - 0.5) * 4.0);
            sum += tint * (emboss * 0.35 + flash * 1.6);
        }
    return sum;
}

// ---- 八种镭射工艺（作用于合成后的彩虹）----

float3 applyPattern(float3 foil, float2 local, float2 vproj,
                    float patMask, float patScale, float patStrength,
                    float crossA, float4 vor) {
    float s = patStrength;
    float modI = 1.0;
    float hue = 0.0;
    if (patOn(patMask, 1) > 0.5) {
        // 细丝拉丝：细密平行亮丝
        float lx = crossA * 34.0 / patScale;
        float lid = floor(lx);
        float lph = hash21(float2(lid, 0.0)) * 6.2832;
        float lamp = mix(0.4, 1.0, hash21(float2(lid, 17.0)));
        float line = pow(0.5 + 0.5 * sin(fract(lx) * 6.2832 + lph), 1.2) * lamp;
        modI *= mix(1.0, mix(0.25, 1.5, line), 0.85);
    }
    if (patOn(patMask, 2) > 0.5) {
        // 柱状光束：少量宽 diagonal 热柱
        float px = crossA * 6.0 / patScale;
        float pid = floor(px);
        float pph = hash21(float2(pid, 5.1)) * 6.2832;
        float pamp = mix(0.7, 1.0, hash21(float2(pid, 9.3)));
        float beam = pow(0.5 + 0.5 * sin(fract(px) * 6.2832 + pph), 0.8) * pamp;
        modI *= mix(0.10, 1.9, beam);
    }
    if (patOn(patMask, 3) > 0.5) {
        // 交叉网纹：45° 双线组，交点亮如小方钻
        float2 uv = float2(local.x + local.y, local.x - local.y) * 0.7071;
        uv *= 30.0 / patScale;
        float lu = pow(0.5 + 0.5 * sin(uv.x * 6.2832), 2.0);
        float lv = pow(0.5 + 0.5 * sin(uv.y * 6.2832), 2.0);
        modI *= 0.12 + 0.55 * (lu + lv) + 1.2 * lu * lv;
    }
    if (patOn(patMask, 4) > 0.5) {
        // 碎冰：voronoi 碎片 + 片间跳色 + 亮棱
        float edge = 1.0 - smoothstep(0.0, 0.055, vor.y);
        hue += (vor.w - 0.5) * 2.2;
        modI *= 0.75 + 0.45 * vor.z + 1.6 * edge;
    }
    if (patOn(patMask, 5) > 0.5) {
        // 闪粉：稀疏抖动针点，碎钻感
        float2 gp = local * 44.0 / patScale;
        float2 gc = floor(gp);
        float2 dp = 0.30 + 0.40 * hash22(gc);
        float gkeep = step(hash21(gc + 4.2), 0.55);
        float gdd = length(fract(gp) - dp);
        float gdot = gkeep * smoothstep(0.28, 0.144, gdd);
        hue += (hash21(gc + 8.8) - 0.5) * 2.094 * gdot;
        modI *= mix(0.10, 1.0, gdot);
    }
    if (patOn(patMask, 6) > 0.5) {
        // 水波：亮度鼓包（groove 扰动已在主函数施加）
        modI *= 1.0 + 0.66 * rippleAngle(local / patScale);
    }
    if (patOn(patMask, 7) > 0.5) {
        // 猫眼：透镜阵列，瞳孔随视角视差
        float2 cp = local / (0.12 * patScale);
        float2 luv = fract(cp) - 0.5;
        float2 pupil = -vproj * 0.32;
        float pd = length(luv - pupil);
        float iris = smoothstep(0.30, 0.08, pd);
        float rim = smoothstep(0.05, 0.0, fabs(pd - 0.26));
        modI *= 0.22 + 2.2 * iris;
        hue += rim * 2.5;
    }
    float3 outc = hueShift(foil, hue * s);
    return outc * mix(1.0, modI, s);
}

float softClip(float c) {
    return c <= 0.7 ? c : 0.7 + 0.3 * (1.0 - exp(-(c - 0.7) / 0.3));
}

} // namespace Foil

// SwiftUI .layerEffect 入口。
// 参数：卡面尺寸 / 倾斜 / 光源 / 工艺掩码与强度 / 曝光 / 星光 / 边缘与画窗遮罩。
[[ stitchable ]] half4 foilEffect(float2 position, SwiftUI::Layer layer,
                                float2 cardSize, float2 tilt, float3 lightDir,
                                float patMask, float patScale, float patStrength,
                                float exposure, float starAmt, float gainB, float spread,
                                float brushed, float metalGain, float tintSel,
                                float edgeOnly, float edgeBand,
                                float4 artWin, float artSoft, float matteBottom) {
    using namespace Foil;
    float2 uv = position / cardSize;
    float aspect = cardSize.x / max(cardSize.y, 1.0);
    float2 local = float2(uv.x * aspect, uv.y);

    float3 N = float3(0.0, 0.0, 1.0);
    float3 V = normalize(float3(tilt.x * 0.9, -tilt.y * 0.9, 1.0));
    float3 L = normalize(lightDir);
    float3 inDir = -L; // 指向光源的反向 = 入射光方向

    // 卡面油墨（层内容）
    half4 artC = layer.sample(position);
    float3 paper = float3(artC.rgb);

    // ---- 遮罩：1 = 箔面，0 = 哑光纸 ----
    float m = 1.0;
    if (edgeOnly > 0.5) {
        float dEdge = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
        m = 1.0 - smoothstep(edgeBand * 0.45, edgeBand, dEdge); // 仅边缘环带
    }
    // 画窗哑光（局部UV）：中心立绘区保持清晰
    {
        float2 half_ = artWin.zw * 0.5;
        float2 q = fabs(uv - (artWin.xy + half_)) - half_;
        float sd = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
        float outside = smoothstep(-artSoft, artSoft, sd); // 窗内 0 → 窗外 1
        m *= outside;
    }
    // 底部信息带哑光
    m *= 1.0 - smoothstep(1.0 - matteBottom - artSoft, 1.0 - matteBottom, uv.y);

    // ---- 银底金属 ----
    float rough = 0.12;
    float3 R = reflect(-V, N);
    float cosV = clamp(dot(N, V), 0.0, 1.0);
    float3 F0 = tintSel > 0.5 ? float3(0.99, 0.85, 0.45) : float3(0.94, 0.95, 0.97);
    float3 F = F0 + (1.0 - F0) * pow(1.0 - cosV, 5.0);
    // groove 方向：两层交叉光栅
    float aA = -0.35, aB = 1.22;
    float3 T_A = float3(cos(aA), sin(aA), 0.0);
    float3 B_A = normalize(cross(N, T_A));
    float3 T_B = float3(cos(aB), sin(aB), 0.0);
    float3 B_B = normalize(cross(N, T_B));
    // 拉丝：沿 groove 方向各向异性拉伸反射
    float stretch = mix(1.0, 4.5, brushed);
    float3 Rb = normalize(R - T_A * dot(R, T_A) * (1.0 - 1.0 / stretch));
    float3 metal = envColor(Rb, rough, lightDir, metalGain, tintSel) * F;

    // ---- 衍射彩虹 ----
    float ndl = max(dot(N, L), 0.0);
    float3 foil = float3(0.0);
    float4 vor = float4(0.0);
    float dAng = 0.0;
    if (patOn(patMask, 4) > 0.5) {
        vor = voronoi(local / (0.09 * patScale));
        dAng += (vor.z - 0.5) * 2.4;
    }
    if (patOn(patMask, 6) > 0.5) {
        dAng += rippleAngle(local / patScale);
    }
    if (fabs(dAng) > 1e-5) {
        dAng *= patStrength;
        float ca = cos(dAng), sa = sin(dAng);
        float3 tA = T_A * ca + B_A * sa; B_A = B_A * ca - T_A * sa; T_A = tA;
        float3 tB = T_B * ca + B_B * sa; B_B = B_B * ca - T_B * sa; T_B = tB;
    }
    {
        float sharpT = mix(2.5, 0.4, spread);
        float kWin = mix(1.2, 0.25, spread);
        float reliefGain = 1.0; // 浮雕深度折算进 exposure
        float3 xyzA = gratingLayer(inDir, V, T_A, B_A, 1050.0, sharpT, kWin);
        float3 xyzB = gratingLayer(inDir, V, T_B, B_B, 1450.0, sharpT, kWin);
        float3 fcol = xyz2srgb(xyzA + xyzB * gainB);
        // vproj 供猫眼工艺做视差
        float3 bx = T_A, by = B_A;
        float2 vproj = float2(dot(V, bx), dot(V, by));
        fcol = applyPattern(fcol, local, vproj, patMask, patScale, patStrength,
                            dot(local, float2(-sin(aA), cos(aA))), vor);
        float lum = dot(fcol, float3(0.2126, 0.7152, 0.0722));
        fcol = mix(fcol, float3(lum), spread * 0.35);
        float grain = mix(0.85, 1.15, hash21(floor(uv * float2(420.0, 180.0))));
        foil = fcol * (exposure * reliefGain) * F * ndl * grain;
    }

    // ---- 星光 ----
    float3 stars = starField(local, N, V, L, T_A, B_A, 0.30) * starAmt * F;

    // ---- 合成：油墨调制（暗部保持清晰）+ 少量加性提亮 ----
    float3 foilTerms = metal * 0.8 + foil + stars;
    float3 foiled = paper * (0.42 + foilTerms) + foil * 0.12 + stars * 0.4;
    float3 col = mix(paper, foiled, m);
    col = float3(softClip(col.x), softClip(col.y), softClip(col.z));

    return half4(half3(col), artC.a);
}
