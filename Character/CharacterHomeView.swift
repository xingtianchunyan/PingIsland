import PingIslandKit
import SwiftUI

/// 角色主页（执行文档 5.3-1，行天改版：足球游戏六边形属性 + 魔兽装备面板风格）：
/// 中上 = 职业 / 等级 / 最新日记；正中 = 角色形象（左装备栏 · 形象 · 右特质栏）；
/// 中下 = 六边形属性雷达；只读展示快照，无"领取"类操作。
struct CharacterHomeView: View {
    @State private var snapshot: DisplaySnapshot = SnapshotIO.load() ?? DisplaySnapshot()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    headerSection
                    heroSection
                    AttributeRadarCard(attributes: snapshot.attributes ?? [:])
                    statusSection
                    LiveActivityControls()
                }
                .padding()
            }
            .navigationTitle("屏之岛")
            .background(Color(.systemGroupedBackground))
            .onAppear {
                // 消费监控扩展积累的待结算事件；无新数据时零开销
                SettlementCoordinator.settlePending()
                snapshot = SnapshotIO.load() ?? DisplaySnapshot()
            }
        }
    }

    // MARK: 中上：职业 / 等级 / 最新日记

    private var headerSection: some View {
        VStack(spacing: 6) {
            Text(snapshot.className)
                .font(.title2.bold())
            Text("等级 \(snapshot.level)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let latest = snapshot.diaryDetail?.first {
                HStack(spacing: 6) {
                    Image(systemName: "book.fill").font(.caption2)
                    Text(latest.text).lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(.indigo.opacity(0.1), in: Capsule())
            }
            if let banner = snapshot.bannerText {
                Text(banner)
                    .font(.caption)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(.indigo.opacity(0.12), in: Capsule())
                    .foregroundStyle(.indigo)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: 正中：左装备栏 · 角色形象 · 右特质栏

    private var heroSection: some View {
        HStack(alignment: .center, spacing: 14) {
            EquipmentColumn(details: snapshot.equippedDetail)
            Spacer(minLength: 0)
            CharacterAvatar(className: snapshot.className, level: snapshot.level)
            Spacer(minLength: 0)
            TraitColumn(skills: snapshot.skills, todayDice: snapshot.todayDice)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 20))
    }

    // MARK: 状态行（疲劳 / 最近结算）

    private var statusSection: some View {
        HStack {
            Label("状态：\(snapshot.fatigueText)", systemImage: "moon.zzz.fill")
            Spacer()
            if let at = snapshot.lastSettlementAt {
                Text("最近结算 \(at, format: .dateTime.month(.defaultDigits).day().hour().minute())")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }
}

/// 职业形象（未觉醒为岛，觉醒后为职业符号）
private struct CharacterAvatar: View {
    let className: String
    let level: Int

    private var classEmoji: String {
        switch className {
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

    var body: some View {
        VStack(spacing: 8) {
            Text(classEmoji)
                .font(.system(size: 72))
                .frame(width: 120, height: 120)
                .background(
                    Circle().fill(.indigo.opacity(0.12))
                )
                .overlay(Circle().stroke(.indigo.opacity(0.3), lineWidth: 2))
            Text("Lv.\(level)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(.indigo)
        }
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
                .frame(height: 240)
                .padding(.horizontal, 8)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16))
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
