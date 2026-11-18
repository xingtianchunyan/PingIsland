import PingIslandKit
import simd
import SwiftUI

// MARK: - 美术资产键解析（内容库 → Imageset）

/// 卡面立绘键统一入口：内容库缺失时全部返回 nil，调用方自行降级（emoji / SF Symbol）。
enum CardArt {
    /// 职业立绘键；未觉醒（className 无法映射职业）返回 nil
    static func classArtKey(className: String) -> String? {
        guard let cls = CharacterClass(rawValue: className) else { return nil }
        return ContentLibrary.shared?.classArt(cls)
    }

    /// 装备立绘键：部位中文 + 外观类型中文 → 内容库 imageset 名
    static func equipmentArtKey(slot: String, appearance: String) -> String? {
        guard let slot = EquipmentSlot(rawValue: slot) else { return nil }
        let tier: AppearanceTier
        switch appearance {
        case "皮甲": tier = .leather
        case "铁甲": tier = .iron
        case "机甲": tier = .mech
        default: tier = .cloth
        }
        return ContentLibrary.shared?.equipmentIcon(slot: slot, tier: tier)
    }
}


// MARK: - 闪卡档位（对外 API 保持不变）

/// 闪卡效果档位（基础映射）：
/// - plain：普通卡面
/// - silverEdge：边缘银色闪卡（默认 = 镜面闪 + 金属烫印银）
/// - goldEdge：边缘金色闪卡（默认 = 波浪闪 + 金属烫印金）
/// - rainbow：全面彩色闪卡（默认 = 碎冰闪 + 全息镭射 + 全向光流 + 局部UV）
/// 调试实验台可实时覆盖重组（HoloEffectLab）。
enum HoloFoil {
    case plain
    case silverEdge
    case goldEdge
    case rainbow

    /// 装备稀有度 → 闪卡档位（白/绿/蓝普通；紫银边；橙金边；红全彩）
    static func equipment(rarity: Int) -> HoloFoil {
        switch Rarity(rawValue: rarity) {
        case .purple: return .silverEdge
        case .orange: return .goldEdge
        case .red: return .rainbow
        default: return .plain
        }
    }

    /// 角色等级 → 闪卡档位（<100 普通；100~199 银边；200~399 金边；≥400 全彩）
    static func character(level: Int) -> HoloFoil {
        if level >= 400 { return .rainbow }
        if level >= 200 { return .goldEdge }
        if level >= 100 { return .silverEdge }
        return .plain
    }
}

// MARK: - 可组合效果模型（纹路 × 光泽 × 金属色 × 覆盖范围）

/// 折射纹路（单选，Canvas 程序化绘制，视角驱动）
enum RefractionPattern: String, CaseIterable, Identifiable, Codable, Sendable {
    case none = "无纹路"
    case crackedIce = "碎冰闪"      // 碎裂冰块/钻石切面，锋利反光
    case chrome = "镜面闪"          // 铬金属镜面，彩虹光晕
    case wave = "波浪闪"            // 水波/绸缎光流
    case atomic = "原子闪"          // 细密小方块颗粒闪烁
    case laser = "激光闪"           // 十字/放射状明亮折线
    var id: String { rawValue }
}

/// 光泽与物理质感（可多选叠加）
enum GlossFinish: String, CaseIterable, Identifiable, Codable, Sendable {
    case holographic = "全息镭射"    // 视角变化七彩渐变（薄膜干涉，随倾斜变色）
    case radialSheen = "全向光流"    // CD 盘背面的圆形金属折射
    case metallicFoil = "金属烫印"   // 名字/卡框烫金银，凹凸金属感
    case spotUV = "局部UV哑光"      // 立绘区保持哑光，背景与边框闪烁
    var id: String { rawValue }
}

/// 金属烫印色调
enum MetallicTint: String, CaseIterable, Identifiable, Codable, Sendable {
    case silver = "银"
    case gold = "金"
    var id: String { rawValue }
}

/// 一张卡的完整特效组合
struct HoloCardEffect: Equatable, Sendable {
    var pattern: RefractionPattern = .none
    var glosses: Set<GlossFinish> = []
    var tint: MetallicTint = .silver
    /// true = 纹路覆盖整卡（受局部UV约束）；false = 仅边框描边
    var fullFace: Bool = true

    static let plainDefault = HoloCardEffect()

    static let silverEdgeDefault = HoloCardEffect(
        pattern: .chrome, glosses: [.metallicFoil], tint: .silver, fullFace: false)

    static let goldEdgeDefault = HoloCardEffect(
        pattern: .wave, glosses: [.metallicFoil], tint: .gold, fullFace: false)

    static let rainbowDefault = HoloCardEffect(
        pattern: .crackedIce,
        glosses: [.holographic, .radialSheen, .metallicFoil, .spotUV],
        tint: .gold, fullFace: true)

    static func `default`(for foil: HoloFoil) -> HoloCardEffect {
        switch foil {
        case .plain: return plainDefault
        case .silverEdge: return silverEdgeDefault
        case .goldEdge: return goldEdgeDefault
        case .rainbow: return rainbowDefault
        }
    }
}

// MARK: - 倾斜状态环境（HoloTilt 向环境广播）

private struct HoloTiltKey: EnvironmentKey {
    static let defaultValue: CGSize = .zero
}

extension EnvironmentValues {
    /// 当前 2.5D 倾斜量（-80...80），供覆层推导视角
    var holoTilt: CGSize {
        get { self[HoloTiltKey.self] }
        set { self[HoloTiltKey.self] = newValue }
    }
}

// MARK: - 2.5D 倾斜交互（小角度翻转，松手回正；广播倾斜量）

struct HoloTilt<Content: View>: View {
    var maxAngle: Double = 9
    @ViewBuilder var content: () -> Content

    @State private var drag: CGSize = .zero
    @State private var lastTranslation: CGSize = .zero

    private var angleX: Double {
        min(max(-Double(drag.height) * 0.12, -maxAngle), maxAngle)
    }

    private var angleY: Double {
        min(max(Double(drag.width) * 0.12, -maxAngle), maxAngle)
    }

    var body: some View {
        content()
            .environment(\.holoTilt, drag)
            .rotation3DEffect(.degrees(angleX), axis: (x: 1, y: 0, z: 0), perspective: 0.55)
            .rotation3DEffect(.degrees(angleY), axis: (x: 0, y: 1, z: 0), perspective: 0.55)
            .shadow(color: .black.opacity(0.35), radius: 14, y: 10)
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        let nextW = drag.width + value.translation.width - lastTranslation.width
                        let nextH = drag.height + value.translation.height - lastTranslation.height
                        drag = CGSize(width: min(max(nextW, -80), 80),
                                      height: min(max(nextH, -80), 80))
                        lastTranslation = value.translation
                    }
                    .onEnded { _ in
                        withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.6)) {
                            drag = .zero
                        }
                        lastTranslation = .zero
                    }
            )
    }
}

// MARK: - 金属烫印渐变（名字/卡框的凹凸金属感）

enum MetallicStamp {
    /// 烫金渐变（高光 → 亮金 → 暗金 → 白 → 中金）
    static let gold = LinearGradient(
        colors: [Color(red: 0.55, green: 0.4, blue: 0.1), Color(red: 0.95, green: 0.78, blue: 0.35),
                 Color(red: 0.7, green: 0.5, blue: 0.12), .white,
                 Color(red: 0.88, green: 0.7, blue: 0.3)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    /// 烫银渐变
    static let silver = LinearGradient(
        colors: [Color(white: 0.45), Color(white: 0.98), Color(white: 0.55), .white,
                 Color(white: 0.75)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    static func gradient(for tint: MetallicTint) -> LinearGradient {
        tint == .gold ? gold : silver
    }

    /// 凹凸感：亮边 + 暗内影（叠在烫印文字/描边下方）
    static let emboss = Color.black.opacity(0.45)
}

// MARK: - 卡面特效组合器（Metal 箔面 shader：kimi 宝可梦全息卡同款光学）

/// 遮罩预设：画窗与底部哑光带的单位矩形（y 向下，0...1）
enum FoilCardKind {
    /// 角色卡：中央立绘大区哑光 + 底部信息带哑光
    case character
    /// 装备卡（万智牌布局）：中部画框哑光
    case equipment

    var artWindow: (x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) {
        switch self {
        case .character: return (0.03, 0.03, 0.94, 0.50)
        case .equipment: return (0.06, 0.26, 0.88, 0.40)
        }
    }
    var matteBottom: CGFloat {
        switch self { case .character: return 0.34; case .equipment: return 0.20 }
    }
}

/// 依 HoloCardEffect 把箔面光学应用到卡面内容上（layerEffect，视角纯函数）。
/// 合成是"油墨调制"：暗色印刷区保持清晰，亮部泛出金属/彩虹/星光。
struct HoloSurface<Content: View>: View {
    let effect: HoloCardEffect
    var cardKind: FoilCardKind = .equipment
    @ViewBuilder var content: () -> Content
    @Environment(\.holoTilt) private var tilt

    /// 纹路 → 参考实现的工艺位（1 拉丝 2 柱光 3 网纹 4 碎冰 5 闪粉 6 水波 7 猫眼；0 平滑）
    private var patternBit: Float {
        switch effect.pattern {
        case .none: return 0            // 平滑箔面
        case .chrome: return 2          // 镜面闪 = 拉丝亮丝
        case .laser: return 4           // 激光闪 = 柱状光束
        case .crackedIce: return 16     // 碎冰
        case .atomic: return 32         // 原子闪 = 闪粉
        case .wave: return 64           // 波浪闪 = 水波
        }
    }

    var body: some View {
        GeometryReader { geo in
            let w = Float(geo.size.width), h = Float(geo.size.height)
            let aw = cardKind.artWindow
            content()
                .layerEffect(ShaderLibrary.default.foilEffect(
                    float2(w, h),
                    float2(Float(tilt.width), Float(tilt.height)),
                    float3(-0.45, -0.55, 0.70),          // 固定光源（左上前方 45°）
                    patternBit,
                    1.0,                                  // 工艺尺度
                    1.0,                                  // 工艺强度
                    effect.glosses.contains(.holographic) ? 1.35 : 0.9,   // 曝光
                    effect.glosses.contains(.radialSheen) ? 1.2 : 0.75,   // 星光
                    effect.glosses.contains(.radialSheen) ? 0.9 : 0.45,   // 第二层光栅
                    0.15,                                 // 角度扩散
                    effect.glosses.contains(.metallicFoil) ? 1.0 : 0.0,     // 拉丝拉伸
                    effect.glosses.contains(.metallicFoil) ? 1.5 : 0.6,   // 金属亮带强度
                    effect.tint == .gold ? 1.0 : 0.0,     // 金属色调
                    effect.fullFace ? 0.0 : 1.0,          // 仅边缘（银边/金边）
                    0.11,                                 // 边缘环带宽
                    float4(Float(aw.x), Float(aw.y), Float(aw.w), Float(aw.h)),
                    0.035,                                // 画窗柔边
                    Float(cardKind.matteBottom)           // 底部哑光带
                ), maxSampleOffset: .zero)
        }
    }
}


// MARK: - 确定性哈希与色调映射（金雨等 Canvas 组件用）

private enum Fract {
    static func frac(_ v: Double) -> Double { v - v.rounded(.down) }
    static func hash(_ i: Int) -> Double { frac(sin(Double(i) * 12.9898) * 43758.5453) }
    static func triangle(_ v: Double) -> Double { 1 - abs((frac(v) * 2) - 1) }
}

private enum HoloOptics {
    /// 0.7 以上指数软压（shader 里有同款，Swift 侧给金雨用）
    static func softClip(_ c: Double) -> Double {
        c <= 0.7 ? c : 0.7 + 0.3 * (1 - exp(-(c - 0.7) / 0.3))
    }
}

// MARK: - 金色窗雨（运气 ≥ 900；雨落下是物理允许持续，贴附水珠静止稳定）

/// v3 纪律修正：贴附水珠**不再随时间闪烁**（每颗亮度固定）；
/// 滑落雨痕持续下落（物理行为），速度各异的蠕动 + 摆动保留。
/// （屏幕级 3D 雨与折射 shader 属第二阶段，将整体替换本组件。）
struct GoldRain: View {
    var dropCount: Int = 30

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                drawStaticDroplets(context: context, size: size)
                drawSlidingStreaks(context: context, size: size, t: t)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // 贴附水珠：静态（亮度由哈希固定，无时间项）
    private func drawStaticDroplets(context: GraphicsContext, size: CGSize) {
        let staticCount = 90
        for i in 0..<staticCount {
            let sx = Fract.hash(i * 3 + 1)
            let sy = Fract.hash(i * 7 + 2)
            let scale = 0.5 + Fract.hash(i * 11 + 5)
            let r = (1.6 + scale * 4.2) * (size.width / 300)
            let x = sx * size.width
            let y = sy * size.height
            let bodyAlpha = 0.30 + 0.25 * scale   // 固定，不闪烁
            let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
            let body = Path(ellipseIn: rect)
            context.fill(body, with: .radialGradient(
                Gradient(colors: [
                    Color(red: 1.0, green: 0.95, blue: 0.7).opacity(HoloOptics.softClip(bodyAlpha + 0.25)),
                    Color(red: 0.95, green: 0.75, blue: 0.25).opacity(bodyAlpha * 0.8),
                    Color(red: 0.55, green: 0.35, blue: 0.08).opacity(bodyAlpha * 0.45),
                ]),
                center: CGPoint(x: x - r * 0.35, y: y - r * 0.35),
                startRadius: 0, endRadius: r * 1.4))
            context.stroke(body, with: .color(Color(red: 0.45, green: 0.28, blue: 0.05)
                .opacity(0.28)), lineWidth: 0.8)
        }
    }

    // 滑落雨痕：拖尾 + 泪滴头（持续下落 = 物理行为，允许时间驱动）
    private func drawSlidingStreaks(context: GraphicsContext, size: CGSize, t: Double) {
        let span = size.height + 60.0
        for i in 0..<dropCount {
            let seed = Double(i)
            let sx = Fract.hash(i * 17 + 3)
            let speed = 0.05 + Fract.hash(i * 23 + 9) * 0.14
            let progress = Fract.frac(Fract.hash(i * 5 + 13) + t * speed)
            let y = progress * span - 30
            let wobble = sin(t * (1.2 + Fract.hash(i * 29 + 1) * 1.5)
                + seed * 6.28) * (3 + Fract.hash(i * 31 + 4) * 4)
            let x = sx * size.width + CGFloat(wobble)
            let fade = min(y / 50, max(0, (size.height - y) / 50), 1)
            guard fade > 0.01 else { continue }
            let strength = 0.2 + 0.6 * fade
            let tail = 26.0 + speed * 380.0
            var trail = Path()
            trail.move(to: CGPoint(x: x, y: y - CGFloat(tail)))
            trail.addLine(to: CGPoint(x: x, y: y))
            context.stroke(trail, with: .linearGradient(
                Gradient(colors: [
                    Color(red: 0.95, green: 0.78, blue: 0.35).opacity(0),
                    Color(red: 0.95, green: 0.78, blue: 0.35).opacity(strength * 0.55),
                    Color(red: 1.0, green: 0.88, blue: 0.55).opacity(HoloOptics.softClip(strength * 0.75)),
                ]),
                startPoint: CGPoint(x: x, y: y - CGFloat(tail)),
                endPoint: CGPoint(x: x, y: y)), lineWidth: 1.6)
            let headR = (2.0 + Fract.hash(i * 37 + 6) * 2.2) * (size.width / 300)
            let headRect = CGRect(x: x - headR, y: y - headR, width: headR * 2, height: headR * 2)
            context.fill(Path(ellipseIn: headRect), with: .radialGradient(
                Gradient(colors: [
                    Color(red: 1.0, green: 0.96, blue: 0.75).opacity(HoloOptics.softClip(strength + 0.2)),
                    Color(red: 0.98, green: 0.82, blue: 0.4).opacity(strength * 0.85),
                    Color(red: 0.7, green: 0.45, blue: 0.1).opacity(strength * 0.5),
                ]),
                center: CGPoint(x: x - headR * 0.3, y: y - headR * 0.3),
                startRadius: 0, endRadius: headR * 1.3))
            let dotR = max(0.6, headR * 0.28)
            context.fill(Path(ellipseIn: CGRect(
                x: x - headR * 0.45 - dotR, y: y - headR * 0.45 - dotR,
                width: dotR * 2, height: dotR * 2)),
                with: .color(Color.white.opacity(strength * 0.85)))
        }
    }
}

// MARK: - 万智牌式卡框（v3：双层视差 + 物理化特效）

/// 万智牌布局 v3：
/// - **双层微视差**：内容层（立绘/文本）与闪膜层（纹路/烫印描边）随 tilt 反向偏移
///   ±3pt/±2pt——"立绘浮在闪膜上"的水晶封层感（外框不动，内容出血由内边距覆盖）
/// - 特效组合与局部 UV 同 v2；纹路/光泽全部视角驱动（静止稳定）
/// - goldRain 为 true 时画框内金雨（贴附水珠已静止化）
struct MTGCardView<Art: View>: View {
    let name: String
    let costBadge: String
    let typeLine: String
    let textBox: String
    let foil: HoloFoil
    var goldRain: Bool = false
    var rarityColor: Color = .primary
    /// 特效组合（nil = 按闪卡档位取默认组合）
    var effect: HoloCardEffect?
    @ViewBuilder var art: () -> Art

    @Environment(\.holoTilt) private var tilt

    private var fx: HoloCardEffect { effect ?? .default(for: foil) }
    private var hasMetallic: Bool { fx.glosses.contains(.metallicFoil) }

    /// 视差量：内容层 +3pt 方向，闪膜层 -2pt 反方向（满倾角时）
    private var contentParallax: CGSize {
        CGSize(width: CGFloat(Double(tilt.width) / 80) * 3,
               height: CGFloat(Double(tilt.height) / 80) * 3)
    }

    var body: some View {
        HoloSurface(effect: fx, cardKind: .equipment) {
            GeometryReader { geo in
                let corner = geo.size.width * 0.045
                let width = geo.size.width
                ZStack {
                    // 外框（卡牌黑边；烫印档加金属描边）——固定层
                    RoundedRectangle(cornerRadius: corner)
                        .fill(Color(white: 0.12))
                    if hasMetallic {
                        RoundedRectangle(cornerRadius: corner)
                            .stroke(MetallicStamp.gradient(for: fx.tint), lineWidth: width * 0.012)
                            .padding(width * 0.006)
                        RoundedRectangle(cornerRadius: corner * 0.9)
                            .stroke(MetallicStamp.emboss.opacity(0.6), lineWidth: 1)
                            .padding(width * 0.016)
                    }
                    // 内框卡纸
                    RoundedRectangle(cornerRadius: corner * 0.75)
                        .fill(Color(red: 0.93, green: 0.89, blue: 0.80))
                        .padding(width * 0.022)
                    // 内容层：标题/画框/文本（正向视差，出血由 0.045w 内边距覆盖）
                    VStack(spacing: geo.size.height * 0.012) {
                        titleBar(width: width)
                        artWindow(corner: corner, width: width)
                        typeBar(width: width)
                        textBoxView(width: width)
                    }
                    .padding(width * 0.045)
                    .offset(contentParallax)
                    .clipShape(RoundedRectangle(cornerRadius: corner * 0.75))
                }
            }
        }
        .aspectRatio(5.0 / 7.0, contentMode: .fit)
    }

    // 标题栏：名称（烫印金属字）+ 费用徽章
    private func titleBar(width: CGFloat) -> some View {
        HStack(alignment: .center, spacing: 4) {
            Text(name)
                .font(.system(size: width * 0.052, weight: .bold, design: .serif))
                .foregroundStyle(nameForeground)
                .shadow(color: MetallicStamp.emboss.opacity(0.5), radius: 0.5, y: 0.8)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Spacer(minLength: 2)
            Text(costBadge)
                .font(.system(size: width * 0.042, weight: .bold, design: .serif).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, width * 0.018)
                .padding(.vertical, width * 0.008)
                .background(
                    Circle()
                        .fill(rarityColor)
                        .frame(width: width * 0.095, height: width * 0.095)
                        .overlay(
                            Circle().stroke(
                                hasMetallic ? AnyShapeStyle(MetallicStamp.gradient(for: fx.tint))
                                            : AnyShapeStyle(.white.opacity(0.5)),
                                lineWidth: 1.5))
                )
                .frame(width: width * 0.095, height: width * 0.095)
        }
        .padding(.horizontal, width * 0.02)
        .padding(.vertical, width * 0.012)
        .background(Color(red: 0.98, green: 0.95, blue: 0.87),
                    in: RoundedRectangle(cornerRadius: width * 0.018))
    }

    private var nameForeground: some ShapeStyle {
        if hasMetallic {
            return AnyShapeStyle(MetallicStamp.gradient(for: fx.tint))
        }
        return AnyShapeStyle(Color.black.opacity(0.85))
    }

    // 画框：立绘（哑光主体）+ 金雨
    private func artWindow(corner: CGFloat, width: CGFloat) -> some View {
        ZStack {
            art()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if goldRain {
                GoldRain()
            }
        }
        .frame(height: width * 0.52)
        .clipShape(RoundedRectangle(cornerRadius: width * 0.02))
        .overlay(RoundedRectangle(cornerRadius: width * 0.02)
            .stroke(Color(red: 0.55, green: 0.42, blue: 0.25).opacity(0.6), lineWidth: 1))
    }

    // 类型行
    private func typeBar(width: CGFloat) -> some View {
        Text(typeLine)
            .font(.system(size: width * 0.036, weight: .semibold, design: .serif))
            .foregroundStyle(.black.opacity(0.75))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, width * 0.02)
            .padding(.vertical, width * 0.01)
            .background(Color(red: 0.98, green: 0.95, blue: 0.87),
                        in: RoundedRectangle(cornerRadius: width * 0.015))
    }

    // 文本框（规则/风味语）
    private func textBoxView(width: CGFloat) -> some View {
        Text(textBox)
            .font(.system(size: width * 0.034, design: .serif))
            .foregroundStyle(.black.opacity(0.8))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, width * 0.025)
            .padding(.vertical, width * 0.02)
            .background(Color(red: 0.97, green: 0.94, blue: 0.85),
                        in: RoundedRectangle(cornerRadius: width * 0.015))
    }
}

// MARK: - 调试实验台（不变）

@MainActor
final class HoloEffectLab: ObservableObject {
    static let shared = HoloEffectLab()

    private let defaults = SharedStore.defaults ?? UserDefaults.standard
    private let kEnabled = "holo.lab.enabled"
    private let kPattern = "holo.lab.pattern"
    private let kGlosses = "holo.lab.glosses"
    private let kTint = "holo.lab.tint"
    private let kFullFace = "holo.lab.fullFace"

    @Published var enabled: Bool { didSet { defaults.set(enabled, forKey: kEnabled) } }
    @Published var pattern: RefractionPattern { didSet { defaults.set(pattern.rawValue, forKey: kPattern) } }
    @Published var glosses: Set<GlossFinish> { didSet {
        defaults.set(glosses.map(\.rawValue), forKey: kGlosses) } }
    @Published var tint: MetallicTint { didSet { defaults.set(tint.rawValue, forKey: kTint) } }
    @Published var fullFace: Bool { didSet { defaults.set(fullFace, forKey: kFullFace) } }

    init() {
        enabled = defaults.bool(forKey: kEnabled)
        pattern = RefractionPattern(rawValue: defaults.string(forKey: kPattern) ?? "") ?? .none
        let saved = defaults.stringArray(forKey: kGlosses) ?? []
        glosses = Set(saved.compactMap(GlossFinish.init(rawValue:)))
        tint = MetallicTint(rawValue: defaults.string(forKey: kTint) ?? "") ?? .silver
        fullFace = defaults.object(forKey: kFullFace) as? Bool ?? true
    }

    var override: HoloCardEffect? {
        guard enabled else { return nil }
        return HoloCardEffect(pattern: pattern, glosses: glosses,
                              tint: tint, fullFace: fullFace)
    }

    func resetToTierDefault() {
        enabled = false
        pattern = .none
        glosses = []
        tint = .silver
        fullFace = true
    }
}

// MARK: - 调试档位覆盖（真机反馈第十九批：闪卡档位预览，作用于 v3 特效组合）

extension HoloFoil {
    /// 调试档位覆盖（0 = 自动，1 = 普通，2 = 银边，3 = 金边，4 = 全彩）
    static func debugOverride(_ raw: Int) -> HoloFoil? {
        switch raw {
        case 1: return .plain
        case 2: return .silverEdge
        case 3: return .goldEdge
        case 4: return .rainbow
        default: return nil
        }
    }

    /// 调试覆盖后的角色卡档位（无覆盖时按等级自动）
    static func effectiveCharacter(level: Int) -> HoloFoil {
        let raw = SharedStore.defaults?.integer(forKey: SharedStore.Keys.debugFoilOverride) ?? 0
        return debugOverride(raw) ?? character(level: level)
    }

    /// 调试覆盖后的装备卡档位（无覆盖时按稀有度自动）
    static func effectiveEquipment(rarity: Int) -> HoloFoil {
        let raw = SharedStore.defaults?.integer(forKey: SharedStore.Keys.debugFoilOverride) ?? 0
        return debugOverride(raw) ?? equipment(rarity: rarity)
    }
}
