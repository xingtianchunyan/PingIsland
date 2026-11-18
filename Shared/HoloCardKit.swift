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

// MARK: - 光学基础：光源 / 视角 / 色调映射

/// 光学渲染核心（物理化 v3）：
/// - 光源固定（左上前方 45°），静止时卡面完全稳定
/// - 全部变化由视角 V 驱动（V 从 HoloTilt 倾角推导）
/// - 微面元镜面反射：spec = pow(max(0, N·H), roughness)
/// - 薄膜干涉色散：hue = f(N·V)（单调映射，无跳变）
/// - tone mapping：softClip 压制过曝（叠加不死白）
enum HoloOptics {
    /// 固定光源方向（左上前方；与美术八轴契约的左上光一致）
    static let light = simd_normalize(SIMD3<Double>(-0.45, -0.55, 0.70))

    /// 由卡面倾角推导视角向量（物理近似：小角度旋转下的视线方向）
    /// tilt ∈ [-80, 80]；静止时 = (0,0,1) 正对卡面
    static func view(tilt: CGSize) -> SIMD3<Double> {
        let tx = Double(tilt.width) / 80
        let ty = Double(tilt.height) / 80
        return simd_normalize(SIMD3<Double>(-tx * 0.9, ty * 0.9,
                                            1 - 0.25 * (abs(tx) + abs(ty))))
    }

    /// 半程向量（镜面反射判定）
    static func half(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> SIMD3<Double> {
        simd_normalize(a + b)
    }

    /// 微面元法线：基础法线(0,0,1) + 固定哈希抖动（每面元恒定，不随时间变）
    static func facetNormal(_ seed: Int, amplitude: Double = 0.55) -> SIMD3<Double> {
        let h1 = Fract.hash(seed * 3 + 1)
        let h2 = Fract.hash(seed * 7 + 2)
        return simd_normalize(SIMD3<Double>((h1 - 0.5) * 2 * amplitude,
                                            (h2 - 0.5) * 2 * amplitude, 1))
    }

    /// 过曝软压（tone mapping）：0.7 以上平滑趋近 1，保留高光边缘色彩过渡
    static func softClip(_ v: Double) -> Double {
        v <= 0.7 ? v : 0.7 + 0.3 * (1 - exp(-(v - 0.7) / 0.12))
    }
}

/// 哈希/波纹工具
enum Fract {
    static func frac(_ v: Double) -> Double { v - v.rounded(.down) }
    static func hash(_ i: Int) -> Double { frac(sin(Double(i) * 12.9898) * 43758.5453) }
    static func triangle(_ v: Double) -> Double { 1 - abs((frac(v) * 2) - 1) }
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

// MARK: - 折射纹路（全部视角驱动：静止稳定，拖拽时按 N·H 变化）

/// 碎冰闪：哈希三角碎片网格；只有法线恰好对上光源的碎片高亮。
/// 开启全息镭射时碎片色相 = 薄膜干涉（N·V 单调映射）。
private struct CrackedIcePattern: View {
    let view: SIMD3<Double>
    var rainbow: Bool = true
    private let cell: CGFloat = 34

    var body: some View {
        Canvas { context, size in
            let half = HoloOptics.half(HoloOptics.light, view)
            let cols = Int(size.width / cell) + 1
            let rows = Int(size.height / cell) + 1
            for row in 0...rows {
                for col in 0...cols {
                    let ox = CGFloat(col) * cell
                    let oy = CGFloat(row) * cell
                    let h1 = Fract.hash(row * 131 + col * 17)
                    let h2 = Fract.hash(row * 57 + col * 211)
                    let midX = ox + cell * (0.3 + CGFloat(h2) * 0.4)
                    let midY = oy + cell * (0.3 + CGFloat(h1) * 0.4)
                    let corners: [CGPoint]
                    if h1 > 0.5 {
                        corners = [CGPoint(x: ox, y: oy), CGPoint(x: ox + cell, y: oy),
                                   CGPoint(x: midX, y: midY), CGPoint(x: ox, y: oy + cell),
                                   CGPoint(x: ox + cell, y: oy + cell)]
                    } else {
                        corners = [CGPoint(x: ox, y: oy), CGPoint(x: ox + cell, y: oy + cell),
                                   CGPoint(x: midX, y: midY), CGPoint(x: ox, y: oy + cell),
                                   CGPoint(x: ox + cell, y: oy + cell)]
                    }
                    for i in 0..<corners.count {
                        let a = corners[i]
                        let b = corners[(i + 1) % corners.count]
                        guard i != 1 || h1 <= 0.5 else { continue }
                        guard i != 3 || h1 > 0.5 else { continue }
                        let shard = Fract.hash(row * 97 + col * 31 + i)
                        let n = HoloOptics.facetNormal(row * 461 + col * 89 + i * 7)
                        let spec = pow(max(0, simd_dot(n, half)), 22)
                        let brightness = HoloOptics.softClip(spec * 0.65 + shard * 0.04)
                        guard brightness > 0.03 else { continue }
                        var path = Path()
                        path.move(to: a)
                        path.addLine(to: b)
                        path.addLine(to: CGPoint(x: midX, y: midY))
                        path.closeSubpath()
                        if rainbow {
                            // 薄膜干涉：色相由视角与法线夹角决定（单调、连续、无时间项）
                            let hue = Fract.frac(0.5
                                + simd_dot(n, view) * 0.35
                                + simd_dot(n, HoloOptics.light) * 0.15)
                            context.fill(path, with: .color(
                                Color(hue: hue, saturation: 0.75, brightness: 1.0)
                                    .opacity(brightness * 0.7)))
                        } else {
                            context.fill(path, with: .color(.white.opacity(brightness)))
                        }
                    }
                }
            }
        }
        .blendMode(.plusLighter)
    }
}

/// 镜面闪（铬）：镜面高光带位置 = f(视角)（拖到哪亮到哪，反向扫动）；
/// 带内彩虹条带随视角平移。
private struct ChromePattern: View {
    let view: SIMD3<Double>

    var body: some View {
        ZStack {
            Canvas { context, size in
                // 视角决定高光带中心（反向：拖拽向右 → 带向左移）
                let bandCenter = 0.5 - view.x * 0.45
                let bandY = 0.5 + view.y * 0.35
                let bandWidth = 0.22
                let bandHeight = 0.65
                let rect = CGRect(x: size.width * (bandCenter - bandWidth / 2),
                                  y: size.height * (bandY - bandHeight / 2),
                                  width: size.width * bandWidth,
                                  height: size.height * bandHeight)
                // 带内彩虹条带（静态纹理；亮度由视角门控）
                let n = HoloOptics.facetNormal(777, amplitude: 0.25)
                let half = HoloOptics.half(HoloOptics.light, view)
                let gate = HoloOptics.softClip(pow(max(0, simd_dot(n, half)), 8) * 0.9 + 0.15)
                for i in 0..<7 {
                    let hue = Fract.frac(Double(i) / 7 * 1.2 + view.x * 0.3)
                    let strip = CGRect(x: rect.minX,
                                       y: rect.minY + rect.height * CGFloat(i) / 7,
                                       width: rect.width,
                                       height: rect.height / 7)
                    context.fill(Path(strip), with: .color(
                        Color(hue: hue, saturation: 0.8, brightness: 1.0)
                            .opacity(gate * 0.28)))
                }
                // 镜面核心高光（最强、最窄）
                let core = rect.insetBy(dx: rect.width * 0.3, dy: rect.height * 0.35)
                context.fill(Path(roundedRect: core, cornerRadius: core.width * 0.2),
                             with: .color(.white.opacity(gate * 0.6)))
            }
            .blendMode(.plusLighter)
            // 环境底光（极弱、固定方向，保证任何角度都有"铬存在感"）
            LinearGradient(colors: [Color(white: 0.9).opacity(0.10), .clear,
                                    Color(white: 0.7).opacity(0.06)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .blendMode(.plusLighter)
        }
    }
}

/// 波浪闪：绸缎光流；每段亮带亮度 = 段法线与半程向量夹角（拖拽时亮带沿波移动）
private struct WavePattern: View {
    let view: SIMD3<Double>
    var tint: Color = Color(red: 0.9, green: 0.72, blue: 0.3)

    var body: some View {
        Canvas { context, size in
            let half = HoloOptics.half(HoloOptics.light, view)
            let bands = 9
            let amplitude = size.height * 0.05
            for k in 0..<bands {
                let progress = Double(k) / Double(bands)
                var points: [CGPoint] = []
                let steps = 24
                for s in 0...steps {
                    let x = size.width * CGFloat(s) / CGFloat(steps)
                    let wave = sin(Double(s) / Double(steps) * Double.pi * 2 + progress * 5.0)
                    let y = size.height * (0.5 + (progress - 0.5) * 0.9)
                        + CGFloat(wave) * amplitude
                    points.append(CGPoint(x: x, y: y))
                }
                // 每段按局部斜率法线算镜面亮度（分 4 段采样）
                for seg in 0..<4 {
                    let i0 = points.count * seg / 4
                    let i1 = points.count * (seg + 1) / 4 - 1
                    guard i0 < i1 else { continue }
                    let dx = points[i1].x - points[i0].x
                    let dy = points[i1].y - points[i0].y
                    let len = max(0.001, (dx * dx + dy * dy).squareRoot())
                    let slopeX = Double(dy / len)
                    let slopeY = -Double(dx / len)
                    let n = simd_normalize(SIMD3<Double>(slopeX * 0.6, slopeY * 0.6, 1))
                    let spec = HoloOptics.softClip(pow(max(0, simd_dot(n, half)), 14) * 0.7)
                    let alpha = 0.05 + spec * 0.5
                    guard alpha > 0.06 else { continue }
                    // 重建该段的子路径
                    var sub = Path()
                    sub.move(to: CGPoint(x: -4, y: -4))
                    for idx in i0...i1 { sub.addLine(to: points[idx]) }
                    sub.addLine(to: CGPoint(x: points[i1].x, y: -4))
                    sub.closeSubpath()
                    context.stroke(sub, with: .color(tint.opacity(alpha)), lineWidth: 2.4)
                }
            }
        }
        .blendMode(.plusLighter)
    }
}

/// 原子闪：方块点阵；每块法线固定 → 特定视角下特定方块群点亮（静态、确定性）
private struct AtomicPattern: View {
    let view: SIMD3<Double>
    private let cell: CGFloat = 15

    var body: some View {
        Canvas { context, size in
            let half = HoloOptics.half(HoloOptics.light, view)
            let cols = Int(size.width / cell)
            let rows = Int(size.height / cell)
            for row in 0...rows {
                for col in 0...cols {
                    let h = Fract.hash(row * 53 + col * 127)
                    let n = HoloOptics.facetNormal(row * 311 + col * 67, amplitude: 0.7)
                    let spec = HoloOptics.softClip(pow(max(0, simd_dot(n, half)), 12))
                    let alpha = spec * (0.35 + h * 0.45)
                    guard alpha > 0.05 else { continue }
                    let side = cell * (0.45 + CGFloat(h) * 0.3)
                    let rect = CGRect(x: CGFloat(col) * cell + (cell - side) / 2,
                                      y: CGFloat(row) * cell + (cell - side) / 2,
                                      width: side, height: side)
                    context.fill(Path(rect), with: .color(.white.opacity(alpha)))
                }
            }
        }
        .blendMode(.plusLighter)
    }
}

/// 激光闪：十字线 + 放射折线；只在特定视角点亮（对角度极敏感 = 激光感）
private struct LaserPattern: View {
    let view: SIMD3<Double>

    var body: some View {
        Canvas { context, size in
            let half = HoloOptics.half(HoloOptics.light, view)
            // 十字线：法线随视角连续变化 → 只有某视角区间亮
            let nV = simd_normalize(SIMD3<Double>(view.x * 0.5, 0, 1))
            let nH = simd_normalize(SIMD3<Double>(0, view.y * 0.5, 1))
            let gateV = HoloOptics.softClip(pow(max(0, simd_dot(nV, half)), 18))
            let gateH = HoloOptics.softClip(pow(max(0, simd_dot(nH, half)), 18))
            var cross = Path()
            let x = size.width * (0.5 - view.x * 0.3)
            let y = size.height * (0.5 + view.y * 0.3)
            cross.move(to: CGPoint(x: x, y: 0))
            cross.addLine(to: CGPoint(x: x, y: size.height))
            cross.move(to: CGPoint(x: 0, y: y))
            cross.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(cross, with: .linearGradient(
                Gradient(colors: [.white.opacity(gateV * 0.8), .white.opacity(gateH * 0.8),
                                  .white.opacity(gateV * 0.7)]),
                startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)),
                lineWidth: 1.6)
            // 放射折线：中心随视角偏移，亮度按径向法线
            let center = CGPoint(x: size.width * (0.5 - view.x * 0.2),
                                 y: size.height * (0.5 + view.y * 0.2))
            for i in 0..<8 {
                let angle = Double(i) * Double.pi / 4
                let n = HoloOptics.facetNormal(i * 43 + 5, amplitude: 0.4)
                let gate = HoloOptics.softClip(pow(max(0, simd_dot(n, half)), 10) * 0.8)
                guard gate > 0.05 else { continue }
                let r0 = min(size.width, size.height) * 0.18
                let r1 = min(size.width, size.height) * 0.6
                var ray = Path()
                ray.move(to: CGPoint(x: center.x + CGFloat(cos(angle)) * r0,
                                     y: center.y + CGFloat(sin(angle)) * r0))
                ray.addLine(to: CGPoint(x: center.x + CGFloat(cos(angle)) * r1,
                                        y: center.y + CGFloat(sin(angle)) * r1))
                context.stroke(ray, with: .color(.white.opacity(gate)), lineWidth: 1.1)
            }
        }
        .blendMode(.plusLighter)
    }
}

// MARK: - 光泽层（视角驱动）

/// 全息镭射（薄膜干涉）：色相随视角连续单调移动，静止时定格
private struct HolographicSheen: View {
    let view: SIMD3<Double>

    var body: some View {
        let vx = view.x
        let vy = view.y
        LinearGradient(colors: [
            Color(hue: Fract.frac(0.00 + vx * 0.25 + vy * 0.1), saturation: 0.8, brightness: 1),
            Color(hue: Fract.frac(0.17 + vx * 0.25 + vy * 0.1), saturation: 0.8, brightness: 1),
            Color(hue: Fract.frac(0.33 + vx * 0.25 + vy * 0.1), saturation: 0.8, brightness: 1),
            Color(hue: Fract.frac(0.50 + vx * 0.25 + vy * 0.1), saturation: 0.8, brightness: 1),
            Color(hue: Fract.frac(0.66 + vx * 0.25 + vy * 0.1), saturation: 0.8, brightness: 1),
            Color(hue: Fract.frac(0.83 + vx * 0.25 + vy * 0.1), saturation: 0.8, brightness: 1),
        ], startPoint: UnitPoint(x: 0.5 - vx * 0.5, y: 0),
           endPoint: UnitPoint(x: 0.5 + vx * 0.5, y: 1))
            .blendMode(.plusLighter)
            .opacity(0.20)   // tone map：全息层强度上限，防叠白
    }
}

/// 全向光流（CD）：折射角度 = f(视角)，静止时定格
private struct RadialSheen: View {
    let view: SIMD3<Double>

    var body: some View {
        let angle = Angle.degrees(view.x * 120 + view.y * 80)
        AngularGradient(colors: [
            .white.opacity(0.0), .white.opacity(0.28),
            Color(hue: 0.1, saturation: 0.6, brightness: 1).opacity(0.22),
            .white.opacity(0.0), Color(hue: 0.55, saturation: 0.6, brightness: 1).opacity(0.22),
            .white.opacity(0.32), .white.opacity(0.0),
        ], center: UnitPoint(x: 0.5 - view.x * 0.12, y: 0.5 - view.y * 0.12), angle: angle)
            .blendMode(.plusLighter)
    }
}

// MARK: - 卡面特效组合器（无时间驱动：静止 0fps，拖拽随帧）

/// 依 HoloCardEffect 组合纹路与光泽。
/// v3 物理化：**不含 TimelineView**——所有层是视角的纯函数，
/// 静止时零重绘（省电），拖拽时由手势帧驱动重绘。
struct HoloSurface: View {
    let effect: HoloCardEffect
    @Environment(\.holoTilt) private var tilt

    private var view: SIMD3<Double> { HoloOptics.view(tilt: tilt) }

    var body: some View {
        ZStack {
            surface(view: view)
        }
    }

    @ViewBuilder
    private func surface(view: SIMD3<Double>) -> some View {
        // 1. 折射纹路（层强度预算：纹路 1.0）
        switch effect.pattern {
        case .crackedIce:
            CrackedIcePattern(view: view,
                              rainbow: effect.glosses.contains(.holographic))
        case .chrome:
            ChromePattern(view: view)
        case .wave:
            WavePattern(view: view,
                        tint: effect.tint == .gold
                            ? Color(red: 0.9, green: 0.72, blue: 0.3)
                            : Color(white: 0.92))
        case .atomic:
            AtomicPattern(view: view)
        case .laser:
            LaserPattern(view: view)
        case .none:
            EmptyView()
        }
        // 2. 动态光泽（层强度预算：光泽共摊 0.7，softClip + 上限防叠加死白）
        if effect.glosses.contains(.holographic) {
            HolographicSheen(view: view)
        }
        if effect.glosses.contains(.radialSheen) {
            RadialSheen(view: view)
        }
        // 3. 静态高光（纸面微光，方向随半程向量，静止时定格）
        LinearGradient(colors: [.white.opacity(0.12), .clear, .white.opacity(0.05)],
                       startPoint: UnitPoint(x: 0.1 - view.x * 0.3, y: 0.05),
                       endPoint: UnitPoint(x: 0.9 - view.x * 0.3, y: 1))
            .blendMode(.plusLighter)
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

    private var foilParallax: CGSize {
        CGSize(width: CGFloat(Double(tilt.width) / 80) * -2,
               height: CGFloat(Double(tilt.height) / 80) * -2)
    }

    var body: some View {
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
                // 闪膜层：内框卡纸 + 特效覆层（反向视差）
                Group {
                    RoundedRectangle(cornerRadius: corner * 0.75)
                        .fill(Color(red: 0.93, green: 0.89, blue: 0.80))
                    surfaceLayer(corner: corner, width: width)
                }
                .padding(width * 0.022)
                .offset(foilParallax)
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
        .aspectRatio(5.0 / 7.0, contentMode: .fit)
    }

    // MARK: 覆层组合（范围 × 局部UV）

    private func surfaceLayer(corner: CGFloat, width: CGFloat) -> some View {
        Group {
            if fx.fullFace {
                if fx.glosses.contains(.spotUV) {
                    HoloSurface(effect: fx)
                        .clipShape(RoundedRectangle(cornerRadius: corner * 0.9))
                        .mask(
                            ZStack {
                                Rectangle().fill(.white)
                                artCutout(width: width)
                                    .fill(.black)
                                    .blendMode(.destinationOut)
                            }
                            .compositingGroup()
                        )
                        .padding(width * 0.008)
                } else {
                    HoloSurface(effect: fx)
                        .clipShape(RoundedRectangle(cornerRadius: corner * 0.9))
                        .padding(width * 0.008)
                }
            } else {
                HoloSurface(effect: fx)
                    .mask(RoundedRectangle(cornerRadius: corner)
                        .stroke(lineWidth: width * 0.026))
            }
        }
        .allowsHitTesting(false)
    }

    /// 画框区域的矩形（局部UV挖洞；含内容层视差同款偏移量由 mask 内吸收，保守不放）
    private func artCutout(width: CGFloat) -> some Shape {
        ArtCutoutShape(padding: width * 0.045,
                       verticals: verticalLayout(width: width))
    }

    private func verticalLayout(width: CGFloat) -> (top: CGFloat, height: CGFloat) {
        let titleH = width * 0.118 + width * 0.024
        let spacing = width * 0.7 * 0.012
        return (top: width * 0.045 + titleH + spacing, height: width * 0.52)
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

/// 画框挖洞形状（局部UV）
private struct ArtCutoutShape: Shape {
    var padding: CGFloat
    var verticals: (top: CGFloat, height: CGFloat)

    func path(in rect: CGRect) -> Path {
        let x = rect.minX + padding
        let w = rect.width - padding * 2
        return Path(roundedRect: CGRect(x: x, y: rect.minY + verticals.top,
                                        width: w, height: verticals.height),
                    cornerRadius: w * 0.02)
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
