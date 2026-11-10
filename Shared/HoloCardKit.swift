import PingIslandKit
import SwiftUI

// MARK: - 闪卡档位（对外 API 保持不变）

/// 闪卡效果档位（基础映射）：
/// - plain：普通卡面
/// - silverEdge：边缘银色闪卡（默认 = 镜面闪 + 金属烫印银）
/// - goldEdge：边缘金色闪卡（默认 = 波浪闪 + 金属烫印金）
/// - rainbow：全面彩色闪卡（默认 = 碎冰闪 + 全息镭射 + 全向光流 + 局部UV + 激光闪）
/// 每档默认组合可在调试面板（卡牌特效实验台）实时覆盖重组。
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

/// 折射纹路（卡面的几何图案，单选）
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
    case holographic = "全息镭射"    // 视角变化七彩渐变（随倾斜变色）
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

    // MARK: 档位默认组合

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

// MARK: - 倾斜状态环境（光随视角动：折射物理感）

private struct HoloTiltKey: EnvironmentKey {
    static let defaultValue: CGSize = .zero
}

extension EnvironmentValues {
    /// 当前 2.5D 倾斜量（-80...80），供覆层计算"视角"（高光偏移、色相旋转）
    var holoTilt: CGSize {
        get { self[HoloTiltKey.self] }
        set { self[HoloTiltKey.self] = newValue }
    }
}

// MARK: - 2.5D 倾斜交互（小角度翻转，松手回正；向环境广播倾斜量）

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

// MARK: - 折射纹路（Canvas 程序化绘制，逐帧由 TimelineView 驱动）

/// 碎冰闪：不规则三角碎片，每片亮度随相位与视角扫动；rainbow 耦合七彩
private struct CrackedIcePattern: View {
    let phase: Double
    let tilt: CGSize
    var rainbow: Bool = true
    private let cell: CGFloat = 34

    var body: some View {
        Canvas { context, size in
            let cols = Int(size.width / cell) + 1
            let rows = Int(size.height / cell) + 1
            let diagLen = Double(size.width + size.height)
            // 视角偏移：倾斜时光斑反方向移动（折射感）
            let tiltShift = Double(tilt.width + tilt.height) / 160
            for row in 0...rows {
                for col in 0...cols {
                    let ox = CGFloat(col) * cell
                    let oy = CGFloat(row) * cell
                    let h1 = Fract.hash(row * 131 + col * 17)
                    let h2 = Fract.hash(row * 57 + col * 211)
                    // 每格 2~3 片三角碎片，切分方向由哈希决定
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
                        // 扫光：碎片的法线相位 → 明暗三角形波
                        let sweep = Fract.triangle(phase * 2
                            + (Double(a.x + a.y) / diagLen) * 2.2
                            + shard * 0.7 + tiltShift)
                        let brightness = pow(sweep, 3) * 0.55 + shard * 0.06
                        guard brightness > 0.02 else { continue }
                        var path = Path()
                        path.move(to: a)
                        path.addLine(to: b)
                        path.addLine(to: CGPoint(x: midX, y: midY))
                        path.closeSubpath()
                        if rainbow {
                            // 七彩碎片：色相随视角 + 相位 + 碎片哈希
                            let hue = Fract.frac(phase * 0.5 + shard * 0.35
                                + tiltShift * 0.3 + Double(a.x) / Double(size.width) * 0.25)
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

/// 镜面闪（铬）：锋利彩虹条带 + 掠过的高光带
private struct ChromePattern: View {
    let phase: Double
    let tilt: CGSize

    var body: some View {
        ZStack {
            Canvas { context, size in
                let bandHeight: CGFloat = 26
                let count = Int(size.height / bandHeight) + 2
                let tiltShift = Double(tilt.width) / 160
                for i in 0..<count {
                    let y = CGFloat(i) * bandHeight - bandHeight / 2
                    let hue = Fract.frac(Double(i) / Double(count) * 1.4
                        + phase * 1.5 + tiltShift)
                    let rect = CGRect(x: -2, y: y, width: size.width + 4, height: bandHeight * 0.55)
                    context.fill(Path(rect), with: .color(
                        Color(hue: hue, saturation: 0.8, brightness: 1.0).opacity(0.16)))
                }
            }
            .blendMode(.plusLighter)
            LinearGradient(colors: [.clear, .white.opacity(0.5), .clear],
                           startPoint: UnitPoint(x: phase * 2.4 - 0.7 + Double(tilt.width) / 200,
                                                 y: 0),
                           endPoint: UnitPoint(x: phase * 2.4 + 0.3 + Double(tilt.width) / 200,
                                               y: 1))
                .blendMode(.plusLighter)
        }
    }
}

/// 波浪闪：丝缎/水波光流（多条正弦亮带流动）
private struct WavePattern: View {
    let phase: Double
    let tilt: CGSize
    var tint: Color = Color(red: 0.9, green: 0.72, blue: 0.3)

    var body: some View {
        Canvas { context, size in
            let bands = 9
            let amplitude = size.height * 0.05
            let tiltShift = Double(tilt.width) / 200
            for k in 0..<bands {
                let progress = Double(k) / Double(bands)
                var path = Path()
                path.move(to: CGPoint(x: -4, y: -4))
                let steps = 24
                for s in 0...steps {
                    let x = size.width * CGFloat(s) / CGFloat(steps)
                    let wave = sin(Double(s) / Double(steps) * Double.pi * 2
                        + phase * Double.pi * 2 * 1.5 + progress * 5.0 + tiltShift * 3)
                    let y = size.height * (0.5 + (progress - 0.5) * 0.9)
                        + CGFloat(wave) * amplitude
                    path.addLine(to: CGPoint(x: x, y: y))
                }
                path.addLine(to: CGPoint(x: size.width + 4, y: -4))
                path.closeSubpath()
                let sweep = Fract.triangle(phase * 1.5 + progress * 1.2 + tiltShift)
                context.stroke(path, with: .color(
                    tint.opacity(0.35 * sweep + 0.08)), lineWidth: 2.4)
            }
        }
        .blendMode(.plusLighter)
    }
}

/// 原子闪：细密小方块颗粒闪烁（低调科技感）
private struct AtomicPattern: View {
    let phase: Double
    let tilt: CGSize
    private let cell: CGFloat = 15

    var body: some View {
        Canvas { context, size in
            let cols = Int(size.width / cell)
            let rows = Int(size.height / cell)
            let tiltShift = Double(tilt.width + tilt.height) / 200
            for row in 0...rows {
                for col in 0...cols {
                    let h = Fract.hash(row * 53 + col * 127)
                    let sparkle = pow(max(0, sin(phase * Double.pi * 4
                        + Double(row + col) * 0.7 + h * 6.0 + tiltShift * 4)), 12)
                    guard sparkle > 0.03 else { continue }
                    let side = cell * (0.45 + CGFloat(h) * 0.3)
                    let rect = CGRect(x: CGFloat(col) * cell + (cell - side) / 2,
                                      y: CGFloat(row) * cell + (cell - side) / 2,
                                      width: side, height: side)
                    context.fill(Path(rect), with: .color(.white.opacity(sparkle * 0.75)))
                }
            }
        }
        .blendMode(.plusLighter)
    }
}

/// 激光闪：十字扫光线 + 放射折线
private struct LaserPattern: View {
    let phase: Double
    let tilt: CGSize

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let tiltShift = Double(tilt.width) / 160
            // 十字线：一条随相位扫动，另一条固定对角
            let sweepX = size.width * CGFloat(Fract.triangle(phase * 2 + tiltShift))
            var cross = Path()
            cross.move(to: CGPoint(x: sweepX, y: 0))
            cross.addLine(to: CGPoint(x: sweepX, y: size.height))
            cross.move(to: CGPoint(x: 0, y: size.height * CGFloat(Fract.triangle(phase * 2 + 0.5))))
            cross.addLine(to: CGPoint(x: size.width, y: size.height * CGFloat(Fract.triangle(phase * 2 + 0.5))))
            context.stroke(cross, with: .linearGradient(
                Gradient(colors: [.white.opacity(0.75), .white.opacity(0.25), .white.opacity(0.7)]),
                startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)),
                lineWidth: 1.6)
            // 放射折线：8 条短射线绕中心旋转
            let rotation = phase * 2 * Double.pi * 2 + tiltShift * 2
            for i in 0..<8 {
                let angle = rotation + Double(i) * Double.pi / 4
                let r0 = min(size.width, size.height) * 0.18
                let r1 = min(size.width, size.height) * (0.55 + 0.1 * sin(Double(i) * 2.1 + phase * 4))
                var ray = Path()
                ray.move(to: CGPoint(x: center.x + CGFloat(cos(angle)) * r0,
                                     y: center.y + CGFloat(sin(angle)) * r0))
                ray.addLine(to: CGPoint(x: center.x + CGFloat(cos(angle)) * r1,
                                        y: center.y + CGFloat(sin(angle)) * r1))
                context.stroke(ray, with: .color(.white.opacity(0.28)), lineWidth: 1.1)
            }
        }
        .blendMode(.plusLighter)
    }
}

/// 哈希/波纹工具
private enum Fract {
    static func frac(_ v: Double) -> Double { v - v.rounded(.down) }
    static func hash(_ i: Int) -> Double { frac(sin(Double(i) * 12.9898) * 43758.5453) }
    static func triangle(_ v: Double) -> Double { 1 - abs((frac(v) * 2) - 1) }
}

// MARK: - 光泽层

/// 全息镭射：色相随视角（倾斜）+ 时间旋转的七彩（红橙黄绿青蓝紫）
private struct HolographicSheen: View {
    let phase: Double
    let tilt: CGSize

    var body: some View {
        let tiltHue = Double(tilt.width) / 160
        LinearGradient(colors: [
            Color(hue: Fract.frac(0.0 + phase * 0.6 + tiltHue), saturation: 0.8, brightness: 1),
            Color(hue: Fract.frac(0.15 + phase * 0.6 + tiltHue), saturation: 0.8, brightness: 1),
            Color(hue: Fract.frac(0.33 + phase * 0.6 + tiltHue), saturation: 0.8, brightness: 1),
            Color(hue: Fract.frac(0.5 + phase * 0.6 + tiltHue), saturation: 0.8, brightness: 1),
            Color(hue: Fract.frac(0.66 + phase * 0.6 + tiltHue), saturation: 0.8, brightness: 1),
            Color(hue: Fract.frac(0.83 + phase * 0.6 + tiltHue), saturation: 0.8, brightness: 1),
        ], startPoint: UnitPoint(x: phase, y: 0), endPoint: UnitPoint(x: 1 - phase, y: 1))
            .blendMode(.plusLighter)
            .opacity(0.22)
    }
}

/// 全向光流：CD 盘背面的圆形金属折射（角度随时间与视角旋转）
private struct RadialSheen: View {
    let phase: Double
    let tilt: CGSize

    var body: some View {
        let angle = Angle.degrees(phase * 720 + Double(tilt.width) * 1.5 + Double(tilt.height) * 1.2)
        AngularGradient(colors: [
            .white.opacity(0.0), .white.opacity(0.3),
            Color(hue: 0.1, saturation: 0.6, brightness: 1).opacity(0.25),
            .white.opacity(0.0), Color(hue: 0.55, saturation: 0.6, brightness: 1).opacity(0.25),
            .white.opacity(0.35), .white.opacity(0.0),
        ], center: .center, angle: angle)
            .blendMode(.plusLighter)
    }
}

// MARK: - 卡面特效组合器

/// 依 HoloCardEffect 组合纹路与光泽，逐帧驱动（约 30fps；纯静态组合不进 Timeline）。
/// 覆盖范围（整卡/仅边缘）由调用方 mask 决定；局部UV（立绘哑光）也由调用方挖洞。
struct HoloSurface: View {
    let effect: HoloCardEffect
    @Environment(\.holoTilt) private var tilt

    private var needsAnimation: Bool {
        effect.pattern != .none || !effect.glosses.isDisjoint(with: [.holographic, .radialSheen])
    }

    var body: some View {
        if needsAnimation {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                let phase = timeline.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 3.6) / 3.6
                ZStack {
                    surface(phase: phase)
                }
            }
        } else {
            surface(phase: 0)
        }
    }

    @ViewBuilder
    private func surface(phase: Double) -> some View {
        // 1. 折射纹路
        switch effect.pattern {
        case .crackedIce:
            CrackedIcePattern(phase: phase, tilt: tilt,
                              rainbow: effect.glosses.contains(.holographic))
        case .chrome:
            ChromePattern(phase: phase, tilt: tilt)
        case .wave:
            WavePattern(phase: phase, tilt: tilt,
                        tint: effect.tint == .gold
                            ? Color(red: 0.9, green: 0.72, blue: 0.3)
                            : Color(white: 0.92))
        case .atomic:
            AtomicPattern(phase: phase, tilt: tilt)
        case .laser:
            LaserPattern(phase: phase, tilt: tilt)
        case .none:
            EmptyView()
        }
        // 2. 动态光泽
        if effect.glosses.contains(.holographic) {
            HolographicSheen(phase: phase, tilt: tilt)
        }
        if effect.glosses.contains(.radialSheen) {
            RadialSheen(phase: phase, tilt: tilt)
        }
        // 3. 静态高光（纸面微光，plain 也有）
        LinearGradient(colors: [.white.opacity(0.14), .clear, .white.opacity(0.06)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .blendMode(.plusLighter)
    }
}

// MARK: - 金色窗雨（运气 ≥ 900，v2：真实雨滴落在玻璃上的质感）

/// "金雨落在窗玻璃"三层结构（Canvas + TimelineView，无状态确定性渲染）：
/// 1. 玻璃光泽层：斜向金色光泽缓慢流动 + 掠过的柔光带（窗面湿润感）
/// 2. 贴附水珠层：数十颗静态小雨珠，径向渐变呈现凸透镜质感
///    （左上金色高光 → 半透明金体 → 底部暗边），峰值时闪出十字星芒
/// 3. 滑落雨痕层：速度各异的雨痕，水滴头（径向高光泪滴）+ 湿拖尾（渐隐金痕），
///    顶部淡入底部淡出，正弦横向摆动模拟水珠沿玻璃蠕动的路径
struct GoldRain: View {
    /// 滑落雨痕数量（兼容旧参数；静态水珠数量固定约 90 颗）
    var dropCount: Int = 30

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                drawGlassSheen(context: context, size: size, t: t)
                drawStaticDroplets(context: context, size: size, t: t)
                drawSlidingStreaks(context: context, size: size, t: t)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: 1. 玻璃光泽（湿润窗面的整体氛围）

    private func drawGlassSheen(context: GraphicsContext, size: CGSize, t: Double) {
        let drift = Fract.frac(t * 0.05)
        // 斜向金色湿光（随时间极缓慢流动）
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
            Gradient(colors: [
                Color(red: 1.0, green: 0.85, blue: 0.45).opacity(0.10),
                .clear,
                Color(red: 0.9, green: 0.65, blue: 0.2).opacity(0.08),
                .clear,
            ]),
            startPoint: CGPoint(x: size.width * CGFloat(drift) - size.width * 0.3, y: 0),
            endPoint: CGPoint(x: size.width * CGFloat(drift) + size.width * 0.5, y: size.height)))
        // 掠过的柔光带（模拟窗前光源经过）
        let sweep = CGFloat(Fract.triangle(t * 0.08))
        let bandX = size.width * (sweep * 1.4 - 0.2)
        let bandWidth = size.width * 0.35
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
            Gradient(colors: [.clear, Color(red: 1.0, green: 0.92, blue: 0.6).opacity(0.12), .clear]),
            startPoint: CGPoint(x: bandX, y: 0),
            endPoint: CGPoint(x: bandX + bandWidth, y: size.height)))
    }

    // MARK: 2. 贴附水珠（静态，凸透镜质感 + 星芒闪烁）

    private func drawStaticDroplets(context: GraphicsContext, size: CGSize, t: Double) {
        let staticCount = 90
        for i in 0..<staticCount {
            let sx = Fract.hash(i * 3 + 1)                    // 0..1
            let sy = Fract.hash(i * 7 + 2)
            let scale = 0.5 + Fract.hash(i * 11 + 5)          // 大小分层
            let r = (1.6 + scale * 4.2) * (size.width / 300)  // 随卡宽缩放
            let x = sx * size.width
            let y = sy * size.height
            // 每颗独立闪烁相位（峰值亮、谷值暗，但始终可见）
            let twinkle = 0.35 + 0.65 * (0.5 + 0.5 * sin(t * Double.pi * 2
                * (0.4 + Fract.hash(i * 13 + 7) * 0.8) + Double(i) * 2.4))
            let bodyAlpha = 0.28 + 0.30 * twinkle
            // 水珠本体：径向渐变（左上高光 → 金体 → 右下暗缘）
            let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
            let body = Path(ellipseIn: rect)
            context.fill(body, with: .radialGradient(
                Gradient(colors: [
                    Color(red: 1.0, green: 0.95, blue: 0.7).opacity(bodyAlpha + 0.25),
                    Color(red: 0.95, green: 0.75, blue: 0.25).opacity(bodyAlpha * 0.8),
                    Color(red: 0.55, green: 0.35, blue: 0.08).opacity(bodyAlpha * 0.45),
                ]),
                center: CGPoint(x: x - r * 0.35, y: y - r * 0.35),
                startRadius: 0, endRadius: r * 1.4))
            // 底缘接触阴影（贴附感）
            context.stroke(body, with: .color(Color(red: 0.45, green: 0.28, blue: 0.05)
                .opacity(0.25 + 0.15 * twinkle)), lineWidth: 0.8)
            // 星芒：闪烁峰值时四芒微光
            let sparkle = pow(twinkle, 4)
            if sparkle > 0.15 && scale > 0.75 {
                let arm = r * (1.2 + 0.8 * sparkle)
                var star = Path()
                star.move(to: CGPoint(x: x - arm, y: y))
                star.addLine(to: CGPoint(x: x + arm, y: y))
                star.move(to: CGPoint(x: x, y: y - arm))
                star.addLine(to: CGPoint(x: x, y: y + arm))
                context.stroke(star, with: .color(Color(red: 1.0, green: 0.95, blue: 0.75)
                    .opacity(sparkle * 0.8)), lineWidth: 0.9)
            }
        }
    }

    // MARK: 3. 滑落雨痕（拖尾 + 泪滴头 + 摆动）

    private func drawSlidingStreaks(context: GraphicsContext, size: CGSize, t: Double) {
        let span = size.height + 60.0
        for i in 0..<dropCount {
            let seed = Double(i)
            let sx = Fract.hash(i * 17 + 3)                       // 基准 x
            let speed = 0.05 + Fract.hash(i * 23 + 9) * 0.14      // 归一化速度/秒（慢速蠕动）
            let progress = Fract.frac(Fract.hash(i * 5 + 13) + t * speed)
            let y = progress * span - 30
            // 横向摆动：水珠沿玻璃蜿蜒下滑
            let wobble = sin(t * (1.2 + Fract.hash(i * 29 + 1) * 1.5)
                + seed * 6.28) * (3 + Fract.hash(i * 31 + 4) * 4)
            let x = sx * size.width + CGFloat(wobble)
            // 顶部/底部淡入淡出
            let fade = min(y / 50, max(0, (size.height - y) / 50), 1)
            guard fade > 0.01 else { continue }
            let strength = 0.2 + 0.6 * fade
            // 拖尾（湿痕）：头部最亮向后渐隐；速度越快拖尾越长
            let tail = 26.0 + speed * 380.0
            var trail = Path()
            trail.move(to: CGPoint(x: x, y: y - CGFloat(tail)))
            trail.addLine(to: CGPoint(x: x, y: y))
            context.stroke(trail, with: .linearGradient(
                Gradient(colors: [
                    Color(red: 0.95, green: 0.78, blue: 0.35).opacity(0),
                    Color(red: 0.95, green: 0.78, blue: 0.35).opacity(strength * 0.55),
                    Color(red: 1.0, green: 0.88, blue: 0.55).opacity(strength * 0.75),
                ]),
                startPoint: CGPoint(x: x, y: y - CGFloat(tail)),
                endPoint: CGPoint(x: x, y: y)), lineWidth: 1.6)
            // 水滴头：泪滴形（圆头 + 上尖尾），径向高光
            let headR = (2.0 + Fract.hash(i * 37 + 6) * 2.2) * (size.width / 300)
            let headRect = CGRect(x: x - headR, y: y - headR, width: headR * 2, height: headR * 2)
            let head = Path(ellipseIn: headRect)
            context.fill(head, with: .radialGradient(
                Gradient(colors: [
                    Color(red: 1.0, green: 0.96, blue: 0.75).opacity(strength + 0.2),
                    Color(red: 0.98, green: 0.82, blue: 0.4).opacity(strength * 0.85),
                    Color(red: 0.7, green: 0.45, blue: 0.1).opacity(strength * 0.5),
                ]),
                center: CGPoint(x: x - headR * 0.3, y: y - headR * 0.3),
                startRadius: 0, endRadius: headR * 1.3))
            // 头部高光点
            let dotR = max(0.6, headR * 0.28)
            context.fill(Path(ellipseIn: CGRect(
                x: x - headR * 0.45 - dotR, y: y - headR * 0.45 - dotR,
                width: dotR * 2, height: dotR * 2)),
                with: .color(Color.white.opacity(strength * 0.85)))
        }
    }
}

// MARK: - 万智牌式卡框（v2：特效组合 + 金属烫印 + 局部UV）

/// 万智牌布局：标题栏（名 + 右上角"费用"徽章）→ 画框 → 类型行 → 文本框。
/// - `foil` 决定基础档位（徽章色等）；`effect` 决定纹路×光泽组合（默认按档位映射）
/// - 金属烫印：名字与卡框用烫金银渐变 + 凹凸内影
/// - 局部UV：立绘画框保持哑光（纹路/光泽覆层挖洞避开），主体"跃然纸上"
/// - goldRain 为 true 时画框背景下金雨。
struct MTGCardView<Art: View>: View {
    let name: String
    /// 右上角徽章文案（如 "Lv.37" / "评 12"）
    let costBadge: String
    let typeLine: String
    /// 文本框文案（词条/风味语）
    let textBox: String
    let foil: HoloFoil
    var goldRain: Bool = false
    var rarityColor: Color = .primary
    /// 特效组合（nil = 按闪卡档位取默认组合）
    var effect: HoloCardEffect?
    @ViewBuilder var art: () -> Art

    private var fx: HoloCardEffect { effect ?? .default(for: foil) }
    private var hasMetallic: Bool { fx.glosses.contains(.metallicFoil) }

    var body: some View {
        GeometryReader { geo in
            let corner = geo.size.width * 0.045
            let width = geo.size.width
            ZStack {
                // 外框（卡牌黑边；烫印档加金属描边）
                RoundedRectangle(cornerRadius: corner)
                    .fill(Color(white: 0.12))
                if hasMetallic {
                    RoundedRectangle(cornerRadius: corner)
                        .stroke(MetallicStamp.gradient(for: fx.tint), lineWidth: width * 0.012)
                        .padding(width * 0.006)
                    // 凹凸内影
                    RoundedRectangle(cornerRadius: corner * 0.9)
                        .stroke(MetallicStamp.emboss.opacity(0.6), lineWidth: 1)
                        .padding(width * 0.016)
                }
                // 内框（米黄卡纸）
                RoundedRectangle(cornerRadius: corner * 0.75)
                    .fill(Color(red: 0.93, green: 0.89, blue: 0.80))
                    .padding(width * 0.022)
                // 卡面内容
                VStack(spacing: geo.size.height * 0.012) {
                    titleBar(width: width)
                    artWindow(corner: corner, width: width)
                    typeBar(width: width)
                    textBoxView(width: width)
                }
                .padding(width * 0.045)
                // 特效覆层
                surfaceLayer(corner: corner, width: width)
            }
        }
        .aspectRatio(5.0 / 7.0, contentMode: .fit)
    }

    // MARK: 覆层组合（范围 × 局部UV）

    /// 整卡覆层：局部UV 开启 → 纹路/光泽避开画框（立绘哑光）；关闭 → 覆盖整卡
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
                // 仅边缘：纹路 + 光泽限制在边框描边内
                HoloSurface(effect: fx)
                    .mask(RoundedRectangle(cornerRadius: corner)
                        .stroke(lineWidth: width * 0.026))
            }
        }
        .allowsHitTesting(false)
    }

    /// 画框区域的矩形（供局部UV挖洞；与 artWindow 布局一致）
    private func artCutout(width: CGFloat) -> some Shape {
        ArtCutoutShape(padding: width * 0.045,
                       verticals: verticalLayout(width: width))
    }

    /// 竖向布局参数（标题栏高度估算 + 画框高度 + 间距，与 VStack 布局对齐）
    private func verticalLayout(width: CGFloat) -> (top: CGFloat, height: CGFloat) {
        let titleH = width * 0.118 + width * 0.024
        let spacing = width * 0.7 * 0.012
        return (top: width * 0.045 + titleH + spacing,
                height: width * 0.52)
    }

    // 标题栏：名称（烫印金属字）+ 费用徽章
    private func titleBar(width: CGFloat) -> some View {
        HStack(alignment: .center, spacing: 4) {
            Text(name)
                .font(.system(size: width * 0.052, weight: .bold, design: .serif))
                .foregroundStyle(nameForeground)
                .shadow(color: MetallicStamp.emboss.opacity(0.5),
                        radius: 0.5, y: 0.8)
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

/// 画框挖洞形状（局部UV：立绘区不被覆层覆盖）
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

// MARK: - 调试实验台（卡牌特效组合的实时覆盖）

/// 卡牌特效实验台：调试面板选择纹路×光泽组合，实时作用于角色页卡牌。
/// 状态存 UserDefaults（仅本机调试，不入存档/不进 Widget）；enabled=false 时卡牌用档位默认。
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

    /// 角色卡取用的效果：未启用 → nil（按档位默认）
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

// MARK: - 调试档位覆盖（真机反馈第十九批：闪卡档位预览，本批起作用于 v2 特效组合）

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

