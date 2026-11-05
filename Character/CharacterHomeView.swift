import PingIslandKit
import SwiftUI

/// 角色主页（执行文档 5.3-1，holo 升级）：
/// 顶部 = 可小角度翻转的 2.5D 万智牌式角色卡（闪卡按等级；运气 ≥ 900 卡面下金雨），
/// 其下 = 装备栏 · 特质栏双列，底部 = 六边形属性雷达。只读展示快照。
struct CharacterHomeView: View {
    @State private var snapshot: DisplaySnapshot = SnapshotIO.load() ?? DisplaySnapshot()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    CharacterHoloCard(snapshot: snapshot)
                    heroRow
                    Divider().opacity(0.4)
                    AttributeRadarCard(attributes: snapshot.attributes ?? [:])
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
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

    // 装备栏 · 特质栏（原 heroRow 左右两栏保留）
    private var heroRow: some View {
        HStack(alignment: .center, spacing: 14) {
            EquipmentColumn(details: snapshot.equippedDetail)
            Spacer(minLength: 0)
            TraitColumn(skills: snapshot.skills, todayDice: snapshot.todayDice)
        }
        .padding(.vertical, 4)
    }
}

/// 2.5D 万智牌式角色卡（holo-card-studio 风格）：
/// - 等级 <100 普通卡面；100~199 银边闪；200~399 金边闪；≥400 全彩闪
/// - 运气 ≥ 900 时画框背景中持续下金色雨滴
/// - 拖动卡面小角度翻转，松手回正
private struct CharacterHoloCard: View {
    let snapshot: DisplaySnapshot

    private var foil: HoloFoil { HoloFoil.character(level: snapshot.level) }

    private var luck: Int { snapshot.attributes?["LUK"] ?? 0 }

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

    /// 徽章底色随闪卡档位升级
    private var badgeColor: Color {
        switch foil {
        case .plain: return .indigo
        case .silverEdge: return Color(white: 0.45)
        case .goldEdge: return Color(red: 0.8, green: 0.62, blue: 0.15)
        case .rainbow: return .purple
        }
    }

    /// 画框主视觉渐变
    private var artGradient: [Color] {
        switch foil {
        case .plain: return [.indigo.opacity(0.5), .teal.opacity(0.2)]
        case .silverEdge: return [Color(white: 0.6).opacity(0.5), Color(white: 0.8).opacity(0.15)]
        case .goldEdge: return [Color(red: 0.85, green: 0.65, blue: 0.2).opacity(0.5), .orange.opacity(0.15)]
        case .rainbow: return [.purple.opacity(0.5), .pink.opacity(0.2), .teal.opacity(0.25)]
        }
    }

    /// 文本框：最新日记 + 横幅 + 最近结算
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
            MTGCardView(
                name: snapshot.className,
                costBadge: "\(snapshot.level)",
                typeLine: "生物 · 修行者 · \(snapshot.fatigueText)",
                textBox: cardText,
                foil: foil,
                goldRain: luck >= 900,
                rarityColor: badgeColor
            ) {
                ZStack {
                    LinearGradient(colors: artGradient,
                                   startPoint: .top, endPoint: .bottom)
                    // 稀有装饰：高级闪卡画框加入光斑
                    if foil == .rainbow {
                        LinearGradient(colors: [.white.opacity(0.35), .clear, .yellow.opacity(0.25)],
                                       startPoint: .topLeading, endPoint: .center)
                    }
                    Text(classEmoji)
                        .font(.system(size: 84))
                        .shadow(color: .black.opacity(0.35), radius: 5, y: 3)
                    VStack {
                        HStack {
                            if luck >= 900 {
                                Text("LUK \(luck)")
                                    .font(.caption2.bold().monospacedDigit())
                                    .foregroundStyle(Color(red: 0.75, green: 0.55, blue: 0.1))
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(Capsule().fill(.white.opacity(0.75)))
                            }
                            Spacer()
                        }
                        .padding(8)
                        Spacer()
                    }
                }
            }
        }
        .frame(width: 300)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("角色卡：\(snapshot.className)，等级\(snapshot.level)，\(snapshot.fatigueText)。拖动可翻转卡牌。")
    }
}

/// 左栏：四部位装备（未装备灰显；点按无操作，纯展示）
private struct EquipmentColumn: View {
    let details: [DisplaySnapshot.EquippedDetail]?

    var body: some View {
        VStack(spacing: 14) {
            ForEach(Array((details ?? []).enumerated()), id: \.offset) { _, item in
                EquipmentSlotIcon(item: item)
            }
            if details == nil {
                Text("装备在探索中自动获得")
                    .font(.caption2).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(width: 56)
    }
}

private struct EquipmentSlotIcon: View {
    let item: DisplaySnapshot.EquippedDetail

    private var slotIcon: String {
        switch item.slot {
        case "头部": return "crown.fill"
        case "上身": return "tshirt.fill"
        case "下身": return "figure.walk"
        default: return "shoe.fill" // 足部
        }
    }

    private var rarityColor: Color {
        guard !item.isEmpty else { return .gray.opacity(0.5) }
        switch Rarity(rawValue: item.rarity) {
        case .green: return .green
        case .blue: return .blue
        case .purple: return .purple
        case .orange: return .orange
        case .red: return .red
        default: return .primary
        }
    }

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: slotIcon)
                .font(.title2)
                .foregroundStyle(rarityColor)
                .opacity(item.isEmpty ? 0.35 : 1)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(rarityColor.opacity(item.isEmpty ? 0.05 : 0.14))
                )
            Text(item.slot)
                .font(.caption2)
                .foregroundStyle(item.isEmpty ? .tertiary : .secondary)
        }
        .accessibilityLabel(item.isEmpty ? "\(item.slot) 未装备" : "\(item.slot) \(item.affixText)")
    }
}

/// 右栏：特质 / 技能（今日骰点置顶，技能按品阶取前 5）
private struct TraitColumn: View {
    let skills: [DisplaySnapshot.SkillDetail]?
    let todayDice: Int?

    private var weekdayName: String {
        let names = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        let index = Calendar.current.component(.weekday, from: Date()) - 1
        return names.indices.contains(index) ? names[index] : ""
    }

    var body: some View {
        VStack(spacing: 12) {
            if let dice = todayDice {
                VStack(spacing: 3) {
                    Image(systemName: "dice.fill")
                        .font(.title2)
                        .foregroundStyle(.indigo)
                        .frame(width: 34, height: 34)
                        .background(RoundedRectangle(cornerRadius: 9).fill(.indigo.opacity(0.12)))
                    Text("骰 \(dice)")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("今日骰点 \(dice)")
            }
            ForEach(Array((skills ?? []).enumerated()), id: \.offset) { _, skill in
                VStack(spacing: 3) {
                    Image(systemName: skill.isActive ? "bolt.fill" : "sparkles")
                        .font(.title2)
                        .foregroundStyle(rarityColor(skill.rarity))
                        .frame(width: 34, height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 9)
                                .fill(rarityColor(skill.rarity).opacity(0.14))
                        )
                        .overlay(alignment: .bottomTrailing) {
                            Text("\(skill.level)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(2)
                                .background(Circle().fill(.secondary))
                                .offset(x: 4, y: 4)
                        }
                    Text(skill.isActive ? "主动" : "被动")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("\(weekdayName)技能，品阶\(skill.rarity)，等级\(skill.level)")
            }
            if skills == nil || skills?.isEmpty == true {
                Text("特质随修行积累")
                    .font(.caption2).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(width: 56)
    }

    private func rarityColor(_ rarity: Int) -> Color {
        switch Rarity(rawValue: rarity) {
        case .green: return .green
        case .blue: return .blue
        case .purple: return .purple
        case .orange: return .orange
        case .red: return .red
        default: return .gray
        }
    }
}

/// 六边形属性雷达（足球游戏式）：六轴 CON/INT/DEX/LUK/WIS/CHA，含网格环与数值顶点
private struct AttributeRadarCard: View {
    let attributes: [String: Int]

    private let axisKeys = Attribute.allCases.map(\.rawValue) // [CON, INT, DEX, LUK, WIS, CHA]

    private var values: [Double] {
        axisKeys.map { Double(attributes[$0] ?? 0) }
    }

    private var maxValue: Double {
        max(20, values.max() ?? 20)
    }

    var body: some View {
        VStack(spacing: 10) {
            Text("六维属性")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
            RadarChart(values: values, labels: axisKeys, maxValue: maxValue)
                .frame(height: 190)
                .padding(.horizontal, 8)
        }
    }
}

/// 自绘六边形雷达：3 层网格环 + 数据多边形 + 轴标签
private struct RadarChart: View {
    let values: [Double]
    let labels: [String]
    let maxValue: Double

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = min(geo.size.width, geo.size.height) / 2 - 24
            ZStack {
                // 网格环（25% / 50% / 75% / 100%）
                ForEach([0.25, 0.5, 0.75, 1.0], id: \.self) { fraction in
                    PolygonShape(vertexCount: values.count, radius: radius * fraction)
                        .stroke(.secondary.opacity(0.25), lineWidth: 1)
                }
                // 轴
                ForEach(Array(0..<values.count), id: \.self) { index in
                    let angle = angleFor(index)
                    Path { path in
                        path.move(to: center)
                        path.addLine(to: vertex(center: center, radius: radius, angle: angle))
                    }
                    .stroke(.secondary.opacity(0.25), lineWidth: 1)
                }
                // 数据多边形
                RadarPolygonShape(center: center, radius: radius, values: values,
                                  maxValue: maxValue)
                    .fill(.indigo.opacity(0.35))
                RadarPolygonShape(center: center, radius: radius, values: values,
                                  maxValue: maxValue)
                    .stroke(.indigo, lineWidth: 2)
                // 顶点数值 + 轴标签
                ForEach(Array(0..<values.count), id: \.self) { index in
                    let angle = angleFor(index)
                    let value = values[index]
                    let point = vertex(center: center,
                                       radius: radius * CGFloat(value / maxValue),
                                       angle: angle)
                    Circle()
                        .fill(.indigo)
                        .frame(width: 6, height: 6)
                        .position(point)
                    let labelPoint = vertex(center: center, radius: radius + 14, angle: angle)
                    Text("\(labels[index]) \(Int(value))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
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
