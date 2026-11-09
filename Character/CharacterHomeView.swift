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

/// 球星卡式角色卡（第十九批重构）：
/// - 立绘 .fill 铺满整卡（职业立绘优先，未觉醒用夜间睡姿图兜底，最后 emoji）
/// - 六维雷达覆盖在立绘上层（卡面内容的一部分，垫半透明面板保证可读）
/// - 卡底深色 scrim 承载名字条 / 日记风味行
/// - 卡牌尽量铺满屏幕宽度（水平仅留 12pt），高宽比 0.68
/// - 等级 <100 普通；100~199 银边；200~399 金边；≥400 全彩；运气 ≥900 金雨（均支持调试开关预览）
/// - 拖动卡面小角度翻转，松手回正
private struct CharacterSportsCard: View {
    let snapshot: DisplaySnapshot

    private var foil: HoloFoil { HoloFoil.effectiveCharacter(level: snapshot.level) }

    private var luck: Int { snapshot.attributes?["LUK"] ?? 0 }

    /// 调试开关：强制金雨（开了直接满足触发条件，关掉恢复 LUK≥900 判定）
    private var forceGoldRain: Bool {
        SharedStore.defaults?.bool(forKey: SharedStore.Keys.debugForceGoldRain) ?? false
    }

    /// 职业立绘键；未觉醒（觉醒中）用夜间睡姿图兜底（app_icon 键悬空，不再使用）
    private var classArtKey: String? {
        CardArt.classArtKey(className: snapshot.className)
            ?? ContentLibrary.shared?.nightSleepArtKey
    }

    /// 觉醒前占位符号（立绘缺失时的兜底）
    private var classEmoji: String {
        switch snapshot.className {
        case "吟游诗人": return "🎵"
        case "大法师": return "🔮"
        case "角斗士": return "🛡️"
        case "先知": return "👁️"
        case "游荡艺人": return "🎭"
        case "炼金术士": return "⚗️"
        case "武僧": return "🥋"
        case "流浪者": return "🏹"
        default: return "🏝️"
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
                let corner = geo.size.width * 0.05
                ZStack {
                    // 外框（卡牌黑边）
                    RoundedRectangle(cornerRadius: corner)
                        .fill(Color(white: 0.12))
                    // 立绘铺满整卡
                    cardFaceArt(width: geo.size.width)
                        .clipShape(RoundedRectangle(cornerRadius: corner * 0.8))
                        .padding(geo.size.width * 0.02)
                    // 六维雷达：覆盖在立绘上层，仍是卡面内容（无底板，直接压在立绘上）
                    VStack {
                        Spacer()
                        RadarChart(values: radarValues, labels: radarKeys, maxValue: radarMax,
                                   tint: .white, grid: .white)
                            .frame(height: geo.size.width * 0.48)
                            .padding(.horizontal, geo.size.width * 0.08)
                            .padding(.bottom, geo.size.width * 0.26)
                    }
                    // 卡底深色 scrim：名字条 + 日记风味行
                    VStack {
                        Spacer()
                        LinearGradient(colors: [.clear, .black.opacity(0.8)],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: geo.size.width * 0.36)
                            .overlay(alignment: .bottom) {
                                VStack(spacing: 4) {
                                    nameBar(width: geo.size.width)
                                    Text(cardText)
                                        .font(.system(size: geo.size.width * 0.032, design: .serif))
                                        .foregroundStyle(.white.opacity(0.85))
                                        .lineLimit(2)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.horizontal, geo.size.width * 0.07)
                                .padding(.bottom, geo.size.width * 0.035)
                            }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: corner * 0.8))
                    .padding(geo.size.width * 0.02)
                    // 闪卡覆层：全彩 = 整面；银/金 = 边缘流光描边；普通 = 轻微高光
                    if foil == .rainbow {
                        FoilOverlay(foil: foil)
                            .clipShape(RoundedRectangle(cornerRadius: corner * 0.8))
                            .padding(geo.size.width * 0.02)
                    } else if foil == .silverEdge {
                        EdgeShimmerBorder(cornerRadius: corner * 0.8,
                                          lineWidth: max(3, geo.size.width * 0.028),
                                          colors: [Color(white: 0.85), .white, Color(white: 0.65),
                                                   .white, Color(white: 0.9), .white])
                            .padding(geo.size.width * 0.02)
                    } else if foil == .goldEdge {
                        EdgeShimmerBorder(cornerRadius: corner * 0.8,
                                          lineWidth: max(3, geo.size.width * 0.028),
                                          colors: [Color(red: 0.85, green: 0.65, blue: 0.2), .yellow,
                                                   Color(red: 0.95, green: 0.85, blue: 0.4), .white,
                                                   .yellow, Color(red: 0.8, green: 0.6, blue: 0.2)])
                            .padding(geo.size.width * 0.02)
                    } else {
                        FoilOverlay(foil: .plain)
                            .clipShape(RoundedRectangle(cornerRadius: corner * 0.8))
                            .padding(geo.size.width * 0.02)
                            .opacity(0.5)
                    }
                }
            }
            .aspectRatio(0.68, contentMode: .fit)
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("角色卡：\(snapshot.className)，等级\(snapshot.level)，\(snapshot.fatigueText)。拖动可翻转卡牌。")
    }

    // MARK: - 卡面分区

    /// 立绘铺满整卡：职业立绘优先（未觉醒用夜间睡姿图兜底）+ 金雨 + LUK 徽章
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
            if luck >= 900 || forceGoldRain {
                GoldRain()
            }
            VStack {
                HStack {
                    if luck >= 900 || forceGoldRain {
                        Text("LUK \(luck)")
                            .font(.caption2.bold().monospacedDigit())
                            .foregroundStyle(Color(red: 0.75, green: 0.55, blue: 0.1))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(.white.opacity(0.8)))
                    }
                    Spacer()
                }
                .padding(8)
                Spacer()
            }
        }
    }

    /// 名字条：职业名 + 等级（纯文本，与职业同等样式；不用圆形底框，三位数等级也能同行显示）
    private func nameBar(width: CGFloat) -> some View {
        HStack(alignment: .center, spacing: 6) {
            Text(snapshot.className)
                .font(.system(size: width * 0.055, weight: .bold, design: .serif))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text("Lv.\(snapshot.level)")
                .font(.system(size: width * 0.048, weight: .bold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, width * 0.02)
        .padding(.vertical, width * 0.008)
    }

    // MARK: - 雷达数据

    private var radarKeys: [String] { Attribute.allCases.map(\.rawValue) }

    private var radarValues: [Double] {
        radarKeys.map { Double(snapshot.attributes?[$0] ?? 0) }
    }

    private var radarMax: Double { max(20, radarValues.max() ?? 20) }
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
