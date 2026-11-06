import PingIslandKit
import SwiftUI

// MARK: - 美术资产键解析（内容库 → Imageset）

/// 卡面立绘键统一入口：内容库缺失时全部返回 nil，调用方自行降级（emoji / SF Symbol）。
enum CardArt {
    /// 职业立绘键；未觉醒（className 无法映射职业）返回 nil（调用方可用 appIconKey 占位）
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

// MARK: - 闪卡档位（holo-card-studio 风格 → SwiftUI 移植）

/// 闪卡效果档位：
/// - plain：普通卡面
/// - silverEdge：边缘银色闪卡
/// - goldEdge：边缘金色闪卡
/// - rainbow：全面彩色闪卡
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

// MARK: - 2.5D 倾斜交互（小角度翻转，松手回正）

/// 按住拖动时以 ±maxAngle 的小角度做 2.5D 翻转；松手弹簧回正。
/// 供已放大的装备卡与角色卡使用。
struct HoloTilt<Content: View>: View {
    var maxAngle: Double = 9
    @ViewBuilder var content: () -> Content

    @State private var drag: CGSize = .zero

    private var angleX: Double {
        min(max(-Double(drag.height) * 0.12, -maxAngle), maxAngle)
    }

    private var angleY: Double {
        min(max(Double(drag.width) * 0.12, -maxAngle), maxAngle)
    }

    var body: some View {
        content()
            .rotation3DEffect(.degrees(angleX), axis: (x: 1, y: 0, z: 0), perspective: 0.55)
            .rotation3DEffect(.degrees(angleY), axis: (x: 0, y: 1, z: 0), perspective: 0.55)
            .shadow(color: .black.opacity(0.35), radius: 14, y: 10)
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        // 增量累计并限幅（避免快速甩动过度旋转）
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

    @State private var lastTranslation: CGSize = .zero
}

// MARK: - 闪卡覆层

/// 依闪卡档位渲染覆层：普通 = 高光；银/金 = 边缘流光；全彩 = 整面彩虹流光。
/// 由 TimelineView 驱动逐帧重绘（约 30fps，覆层本身无状态）。
struct FoilOverlay: View {
    let foil: HoloFoil

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 3.6) / 3.6
            ZStack {
                switch foil {
                case .plain:
                    LinearGradient(colors: [.white.opacity(0.16), .clear, .white.opacity(0.07)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                case .silverEdge:
                    edgeShimmer(phase: phase, colors: [
                        Color(white: 0.85), .white, Color(white: 0.7),
                        .white, Color(white: 0.9), .white, Color(white: 0.8),
                    ])
                case .goldEdge:
                    edgeShimmer(phase: phase, colors: [
                        Color(red: 0.72, green: 0.55, blue: 0.2), .yellow, Color(red: 0.85, green: 0.68, blue: 0.3),
                        .white, .yellow, Color(red: 0.75, green: 0.6, blue: 0.25), .yellow,
                    ])
                case .rainbow:
                    rainbowFoil(phase: phase)
                }
            }
        }
    }

    /// 边缘流光：细窄高光带沿边框循环扫动（用偏移渐变模拟）
    private func edgeShimmer(phase: Double, colors: [Color]) -> some View {
        LinearGradient(colors: colors,
                       startPoint: UnitPoint(x: phase * 2 - 1, y: -0.2),
                       endPoint: UnitPoint(x: phase * 2, y: 1.2))
            .blendMode(.plusLighter)
    }

    /// 全彩闪：整面彩虹渐变随时间旋转 + 扫动高光
    private func rainbowFoil(phase: Double) -> some View {
        ZStack {
            LinearGradient(colors: [.red, .orange, .yellow, .green, .teal, .blue, .purple, .pink, .red],
                           startPoint: UnitPoint(x: phase, y: 0),
                           endPoint: UnitPoint(x: 1 - phase, y: 1))
                .blendMode(.plusLighter)
                .opacity(0.32)
            LinearGradient(colors: [.white.opacity(0.45), .clear, .white.opacity(0.2)],
                           startPoint: UnitPoint(x: phase * 2 - 1, y: -0.1),
                           endPoint: UnitPoint(x: phase * 2, y: 1.1))
                .blendMode(.plusLighter)
        }
    }
}

// MARK: - 边缘流光描边（银/金闪卡）

/// 银/金边闪卡的边框流光：动画渐变沿边框循环扫动。
/// 用 strokeBorder（描边全部落在形内）保证边框全覆盖——
/// 旧版 mask+stroke 方案描边一半悬在卡外被裁，只剩未覆盖的白边（第十八批修复）。
struct EdgeShimmerBorder: View {
    let cornerRadius: CGFloat
    let lineWidth: CGFloat
    let colors: [Color]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 3.6) / 3.6
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(
                    LinearGradient(colors: colors,
                                   startPoint: UnitPoint(x: phase * 2 - 1, y: -0.2),
                                   endPoint: UnitPoint(x: phase * 2, y: 1.2)),
                    lineWidth: lineWidth)
                .blendMode(.plusLighter)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - 金色雨滴（运气 ≥ 900）

/// 卡面背景中持续飘落的金色雨滴（Canvas + TimelineView，低开销、无状态）。
struct GoldRain: View {
    var dropCount: Int = 30

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                for index in 0..<dropCount {
                    let seed = Double(index)
                    let x = frac(sin(seed * 12.9898) * 43758.5453) * size.width
                    let speed = 55.0 + frac(sin(seed * 78.233) * 12543.117) * 70.0
                    let length = 7.0 + frac(sin(seed * 39.425) * 2314.928) * 8.0
                    let width = 1.8 + frac(sin(seed * 3.771) * 921.477) * 1.2
                    let span = size.height + 60
                    let y = (t * speed + seed * 97.13).truncatingRemainder(dividingBy: span) - 30
                    // 顶部/底部淡入淡出
                    let fade = min(y / 40, max(0, (size.height - y) / 40))
                    let alpha = 0.25 + 0.55 * min(1, max(0, fade))
                    let rect = CGRect(x: x, y: y, width: width, height: length)
                    let path = Path(roundedRect: rect, cornerRadius: width / 2)
                    context.fill(path, with: .linearGradient(
                        Gradient(colors: [
                            Color(red: 0.95, green: 0.78, blue: 0.25).opacity(alpha),
                            Color(red: 0.85, green: 0.62, blue: 0.12).opacity(alpha * 0.6),
                        ]),
                        startPoint: CGPoint(x: x, y: y), endPoint: CGPoint(x: x, y: y + length)))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func frac(_ v: Double) -> Double {
        v - v.rounded(.down)
    }
}

// MARK: - 万智牌式卡框

/// 万智牌布局：标题栏（名 + 右上角"费用"徽章）→ 画框 → 类型行 → 文本框。
/// foil 决定闪卡效果；goldRain 为 true 时画框背景下金雨。
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
    @ViewBuilder var art: () -> Art

    var body: some View {
        GeometryReader { geo in
            let corner = geo.size.width * 0.045
            ZStack {
                // 外框（卡牌黑边）
                RoundedRectangle(cornerRadius: corner)
                    .fill(Color(white: 0.12))
                // 内框（米黄卡纸）
                RoundedRectangle(cornerRadius: corner * 0.75)
                    .fill(Color(red: 0.93, green: 0.89, blue: 0.80))
                    .padding(geo.size.width * 0.022)
                // 卡面内容
                VStack(spacing: geo.size.height * 0.012) {
                    titleBar(width: geo.size.width)
                    artWindow(corner: corner, width: geo.size.width)
                    typeBar(width: geo.size.width)
                    textBoxView(width: geo.size.width)
                }
                .padding(geo.size.width * 0.045)
                // 闪卡覆层：全彩 = 整面；银/金边 = 边缘流光描边（全覆盖）；普通 = 轻微高光
                if foil == .rainbow {
                    FoilOverlay(foil: foil)
                        .clipShape(RoundedRectangle(cornerRadius: corner * 0.9))
                        .padding(geo.size.width * 0.008)
                } else if foil == .silverEdge {
                    EdgeShimmerBorder(cornerRadius: corner * 0.9,
                                      lineWidth: max(3, geo.size.width * 0.03),
                                      colors: [Color(white: 0.85), .white, Color(white: 0.65),
                                               .white, Color(white: 0.9), .white, Color(white: 0.75)])
                        .padding(geo.size.width * 0.008)
                } else if foil == .goldEdge {
                    EdgeShimmerBorder(cornerRadius: corner * 0.9,
                                      lineWidth: max(3, geo.size.width * 0.03),
                                      colors: [Color(red: 0.72, green: 0.55, blue: 0.2), .yellow,
                                               Color(red: 0.85, green: 0.68, blue: 0.3), .white,
                                               .yellow, Color(red: 0.75, green: 0.6, blue: 0.25), .yellow])
                        .padding(geo.size.width * 0.008)
                } else {
                    // 普通卡：轻微高光
                    FoilOverlay(foil: .plain)
                        .clipShape(RoundedRectangle(cornerRadius: corner * 0.9))
                        .padding(geo.size.width * 0.008)
                        .opacity(0.5)
                }
            }
        }
        .aspectRatio(5.0 / 7.0, contentMode: .fit)
    }

    // 标题栏：名称 + 费用徽章
    private func titleBar(width: CGFloat) -> some View {
        HStack(alignment: .center, spacing: 4) {
            Text(name)
                .font(.system(size: width * 0.052, weight: .bold, design: .serif))
                .foregroundStyle(.black.opacity(0.85))
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
                )
                .frame(width: width * 0.095, height: width * 0.095)
        }
        .padding(.horizontal, width * 0.02)
        .padding(.vertical, width * 0.012)
        .background(Color(red: 0.98, green: 0.95, blue: 0.87),
                    in: RoundedRectangle(cornerRadius: width * 0.018))
    }

    // 画框：立绘 / 主视觉，可叠金雨
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
