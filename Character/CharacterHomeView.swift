import PingIslandKit
import SwiftUI

/// 角色主页（执行文档 5.3-1，第二十批球星卡重构）：
/// 中央 = 球星卡式角色卡（立绘铺满整卡、六维雷达覆盖在立绘上层，仍是卡面内容；
/// 闪卡按等级；运气 ≥900 或调试开关强制 → 卡面下金雨）。卡牌在屏幕垂直居中。
/// 装备栏 · 特质栏已按第二十批反馈移除，后续按数据做动画/视觉效果。只读展示快照。
struct CharacterHomeView: View {
    @State private var snapshot: DisplaySnapshot = SnapshotIO.load() ?? DisplaySnapshot()

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView {
                    CharacterSportsCard(snapshot: snapshot)
                        .frame(maxWidth: .infinity)
                        // 垂直居中：内容不足一屏时上下留白相等
                        .frame(minHeight: proxy.size.height)
                        .padding(.horizontal, 12)
                }
            }
            .background(Color(.systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                // 消费监控扩展积累的待结算事件；无新数据时零开销
                SettlementCoordinator.settlePending()
                snapshot = SnapshotIO.load() ?? DisplaySnapshot()
            }
        }
    }
}

/// 球星卡式角色卡（第二十一批重构）：
/// - 立绘 .fill 铺满整卡（职业立绘优先，未觉醒用夜间睡姿图兜底，最后 emoji）
/// - 左侧：职业名 / 等级 / 日记风味行（靠左显示，不遮挡立绘中心）
/// - 右下：六维雷达（卡面内容一部分）
/// - 右上：d20 骰子（万智牌实体骰形象，点击在原位置滚动动画）
/// - 特效 = holo-card v2 组合（实验台覆盖 > 档位默认：银/金边 = 边缘流光，全彩 = 整卡）
/// - 运气 ≥900 或调试开关 → 卡面金雨（v2 窗玻璃雨滴）
/// - 拖动卡面小角度翻转，松手回正
private struct CharacterSportsCard: View {
    let snapshot: DisplaySnapshot

    /// 卡牌特效实验台覆盖（nil = 按闪卡档位默认组合）
    @ObservedObject private var lab = HoloEffectLab.shared
    /// 骰子当前显示值（滚动动画中变化，落定 = 当日骰点）
    @State private var shownDice: Int = 20
    @State private var isRolling = false

    private var foil: HoloFoil { HoloFoil.effectiveCharacter(level: snapshot.level) }

    /// 生效特效组合：实验台 > 档位默认
    private var fx: HoloCardEffect { lab.override ?? .default(for: foil) }

    private var hasMetallic: Bool { fx.glosses.contains(.metallicFoil) }

    private var luck: Int { snapshot.attributes?["LUK"] ?? 0 }

    /// 调试开关：强制金雨（开了直接满足触发条件，关掉恢复 LUK≥900 判定）
    private var forceGoldRain: Bool {
        SharedStore.defaults?.bool(forKey: SharedStore.Keys.debugForceGoldRain) ?? false
    }

    private var goldRainOn: Bool { luck >= 900 || forceGoldRain }

    /// 职业立绘键；未觉醒（觉醒中）用夜间睡姿图兜底（app_icon 键悬空，不再使用）
    private var classArtKey: String? {
        CardArt.classArtKey(className: snapshot.className)
            ?? ContentLibrary.shared?.nightSleepArtKey
    }

    /// 觉醒前占位符号（立绘缺失时的兜底）
    private var classEmoji: String {
        switch snapshot.className {
        case "吟游诗人": return "\u{1F3B5}"
        case "大法师": return "\u{1F52E}"
        case "角斗士": return "\u{1F6E1}\u{FE0F}"
        case "先知": return "\u{1F441}\u{FE0F}"
        case "游荡艺人": return "\u{1F3AD}"
        case "炼金术士": return "\u{2697}\u{FE0F}"
        case "武僧": return "\u{1F94B}"
        case "流浪者": return "\u{1F3F9}"
        default: return "\u{1F3DD}\u{FE0F}"
        }
    }

    /// 卡面风味行：最新日记 + 横幅 + 最近结算
    private var cardText: String {
        var lines: [String] = []
        if let latest = snapshot.diaryDetail?.first {
            lines.append("「\(latest.text)」")
        }
        if let banner = snapshot.bannerText {
            lines.append(banner)
        }
        if let at = snapshot.lastSettlementAt {
            lines.append("最近结算 \(at.formatted(.dateTime.month().day().hour().minute()))")
        }
        return lines.isEmpty ? "等待第一次结算——岛上的生活尚未开始。" : lines.joined(separator: "\n")
    }

    var body: some View {
        HoloTilt {
            GeometryReader { geo in
                let width = geo.size.width
                let corner = width * 0.05
                ZStack {
                    // 外框（卡牌黑边；烫印档加金属描边 + 凹凸内影）
                    RoundedRectangle(cornerRadius: corner)
                        .fill(Color(white: 0.12))
                    if hasMetallic {
                        RoundedRectangle(cornerRadius: corner)
                            .stroke(MetallicStamp.gradient(for: fx.tint),
                                    lineWidth: width * 0.012)
                            .padding(width * 0.006)
                        RoundedRectangle(cornerRadius: corner * 0.9)
                            .stroke(MetallicStamp.emboss.opacity(0.6), lineWidth: 1)
                            .padding(width * 0.016)
                    }
                    // 立绘铺满整卡 + 金雨
                    cardFaceArt(width: width)
                        .clipShape(RoundedRectangle(cornerRadius: corner * 0.8))
                        .padding(width * 0.02)
                    // 底部信息带：左侧职业/等级/风味行（靠左）+ 右下雷达
                    VStack {
                        Spacer()
                        HStack(alignment: .bottom, spacing: 4) {
                            leftInfo(width: width)
                                .padding(.leading, width * 0.05)
                            Spacer(minLength: 0)
                            // 六维雷达：卡面右下，不遮挡立绘中心
                            RadarChart(values: radarValues, labels: radarKeys,
                                       maxValue: radarMax, tint: .white, grid: .white)
                                .frame(width: width * 0.42, height: width * 0.42)
                                .padding(.trailing, width * 0.04)
                                .padding(.bottom, width * 0.03)
                        }
                        .background(
                            LinearGradient(colors: [.clear, .black.opacity(0.72)],
                                           startPoint: .top, endPoint: .bottom)
                                .frame(height: width * 0.52),
                            alignment: .bottom
                        )
                    }
                    .clipShape(RoundedRectangle(cornerRadius: corner * 0.8))
                    .padding(width * 0.02)
                    // d20 骰子：右上角，卡面内容的一部分，点击滚动
                    VStack {
                        HStack {
                            Spacer()
                            Dice20View(value: shownDice, rolling: isRolling)
                                .frame(width: width * 0.17, height: width * 0.17)
                                .onTapGesture(perform: rollDice)
                                .padding(.top, width * 0.045)
                                .padding(.trailing, width * 0.045)
                        }
                        Spacer()
                    }
                    .padding(width * 0.02)
                    // holo v2 特效覆层（整卡 or 仅边缘描边）
                    surfaceLayer(corner: corner, width: width)
                }
            }
            .aspectRatio(0.68, contentMode: .fit)
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            shownDice = snapshot.todayDice ?? 20
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("角色卡：\(snapshot.className)，等级\(snapshot.level)，骰子\(shownDice)点。轻点骰子滚动，拖动可翻转卡牌。")
    }

    // MARK: - 特效覆层（holo v2）

    /// 整卡：覆层裁剪进卡面；仅边缘：限制在边框描边内
    @ViewBuilder
    private func surfaceLayer(corner: CGFloat, width: CGFloat) -> some View {
        if fx.fullFace {
            HoloSurface(effect: fx)
                .clipShape(RoundedRectangle(cornerRadius: corner * 0.8))
                .padding(width * 0.02)
        } else {
            HoloSurface(effect: fx)
                .mask(RoundedRectangle(cornerRadius: corner)
                    .stroke(lineWidth: max(3, width * 0.024)))
        }
    }

    // MARK: - 卡面分区

    /// 立绘铺满整卡：职业立绘优先（未觉醒用夜间睡姿图兜底）+ 金雨
    private func cardFaceArt(width: CGFloat) -> some View {
        ZStack {
            LinearGradient(colors: [.indigo.opacity(0.45), .black.opacity(0.6)],
                           startPoint: .top, endPoint: .bottom)
            if let key = classArtKey {
                Image(key)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Text(classEmoji)
                    .font(.system(size: width * 0.3))
                    .shadow(color: .black.opacity(0.35), radius: 5, y: 3)
            }
            if goldRainOn {
                GoldRain()
            }
        }
    }

    /// 左侧信息列：职业名 + 等级（纯文本，三位数等级也能同行）+ 日记风味行
    private func leftInfo(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 6) {
                Text(snapshot.className)
                    .font(.system(size: width * 0.05, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("Lv.\(snapshot.level)")
                    .font(.system(size: width * 0.044, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(.horizontal, width * 0.02)
            .padding(.vertical, width * 0.008)
            // 卡面 3 技能（第二十一批 Phase B-1：克制技带闪电标记，成链发光）
            CardSkillRows(skills: snapshot.cardSkills ?? [],
                          links: snapshot.skillLinks ?? [])
                .frame(maxWidth: width * 0.48, alignment: .leading)
                .padding(.horizontal, width * 0.02)
            Text(cardText)
                .font(.system(size: width * 0.03, design: .serif))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(2)
                .frame(maxWidth: width * 0.48, alignment: .leading)
        }
        .padding(.bottom, width * 0.035)
    }

    // MARK: - 骰子滚动

    /// 点击骰子：快速轮换随机点数约 0.8 秒，落定到当日骰点（无则保持随机结果）
    private func rollDice() {
        guard !isRolling else { return }
        isRolling = true
        var ticks = 0
        Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { timer in
            shownDice = Int.random(in: 1...20)
            ticks += 1
            if ticks >= 14 {
                timer.invalidate()
                if let dice = snapshot.todayDice {
                    shownDice = dice
                }
                isRolling = false
            }
        }
    }

    // MARK: - 雷达数据

    private var radarKeys: [String] { Attribute.allCases.map(\.rawValue) }

    private var radarValues: [Double] {
        radarKeys.map { Double(snapshot.attributes?[$0] ?? 0) }
    }

    private var radarMax: Double { max(20, radarValues.max() ?? 20) }
}

/// 万智牌 20 点实体骰（spindown d20）：二十边形象牙骰体 + 凹刻数字。
/// rolling 时整体微旋，营造滚动感。
private struct Dice20View: View {
    let value: Int
    let rolling: Bool

    @State private var spin: Double = 0

    var body: some View {
        ZStack {
            // 骰体：二十边形 + 象牙渐变 + 描边
            PolygonShape(vertexCount: 20, radius: 60)
                .fill(
                    RadialGradient(colors: [Color(red: 0.98, green: 0.96, blue: 0.9),
                                            Color(red: 0.88, green: 0.84, blue: 0.74)],
                                   center: .center, startRadius: 4, endRadius: 62)
                )
                .overlay(
                    PolygonShape(vertexCount: 20, radius: 60)
                        .stroke(Color(white: 0.35), lineWidth: 2)
                )
                .shadow(color: .black.opacity(0.45), radius: 4, y: 2)
            // 凹刻数字
            Text("\(value)")
                .font(.system(size: 34, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(Color(white: 0.25))
        }
        .rotationEffect(.degrees(rolling ? spin : 0))
        .onChange(of: rolling) { _, on in
            if on {
                withAnimation(.linear(duration: 0.06).repeatCount(14, autoreverses: false)) {
                    spin += 360
                }
            } else {
                spin = 0
            }
        }
    }
}

/// 自绘六边形雷达：3 层网格环 + 数据多边形 + 轴标签
/// tint/grid 可参数化：默认保持原 indigo/secondary（浅色底），卡面立绘上用白色
private struct RadarChart: View {
    let values: [Double]
    let labels: [String]
    let maxValue: Double
    var tint: Color = .indigo
    var grid: Color = .secondary

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = min(geo.size.width, geo.size.height) / 2 - 24
            ZStack {
                // 网格环（25% / 50% / 75% / 100%）
                ForEach([0.25, 0.5, 0.75, 1.0], id: \.self) { fraction in
                    PolygonShape(vertexCount: values.count, radius: radius * fraction)
                        .stroke(grid.opacity(0.35), lineWidth: 1)
                }
                // 轴
                ForEach(Array(0..<values.count), id: \.self) { index in
                    let angle = angleFor(index)
                    Path { path in
                        path.move(to: center)
                        path.addLine(to: vertex(center: center, radius: radius, angle: angle))
                    }
                    .stroke(grid.opacity(0.35), lineWidth: 1)
                }
                // 数据多边形
                RadarPolygonShape(center: center, radius: radius, values: values,
                                  maxValue: maxValue)
                    .fill(tint.opacity(0.35))
                RadarPolygonShape(center: center, radius: radius, values: values,
                                  maxValue: maxValue)
                    .stroke(tint, lineWidth: 2)
                // 顶点数值 + 轴标签
                ForEach(Array(0..<values.count), id: \.self) { index in
                    let angle = angleFor(index)
                    let value = values[index]
                    let point = vertex(center: center,
                                       radius: radius * CGFloat(value / maxValue),
                                       angle: angle)
                    Circle()
                        .fill(tint)
                        .frame(width: 6, height: 6)
                        .position(point)
                    let labelPoint = vertex(center: center, radius: radius + 14, angle: angle)
                    Text("\(labels[index]) \(Int(value))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(grid)
                        .position(labelPoint)
                }
            }
        }
    }

    /// 顶点 0 在正上方，顺时针
    private func angleFor(_ index: Int) -> Angle {
        .degrees(-90 + Double(index) * 360 / Double(values.count))
    }

    private func vertex(center: CGPoint, radius: CGFloat, angle: Angle) -> CGPoint {
        CGPoint(x: center.x + radius * CGFloat(cos(angle.radians)),
                y: center.y + radius * CGFloat(sin(angle.radians)))
    }
}

/// 正多边形（网格环用）
private struct PolygonShape: Shape {
    let vertexCount: Int
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        for index in 0..<vertexCount {
            let angle = Angle.degrees(-90 + Double(index) * 360 / Double(vertexCount))
            let point = CGPoint(x: center.x + radius * CGFloat(cos(angle.radians)),
                                y: center.y + radius * CGFloat(sin(angle.radians)))
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

/// 数据多边形（值缩放）
private struct RadarPolygonShape: Shape {
    let center: CGPoint
    let radius: CGFloat
    let values: [Double]
    let maxValue: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for (index, value) in values.enumerated() {
            let angle = Angle.degrees(-90 + Double(index) * 360 / Double(values.count))
            let r = radius * CGFloat(value / maxValue)
            let point = CGPoint(x: center.x + r * CGFloat(cos(angle.radians)),
                                y: center.y + r * CGFloat(sin(angle.radians)))
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}
