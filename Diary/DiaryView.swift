import PingIslandKit
import SwiftUI

/// 日记页（执行文档 5.3-2 / 9.7）：「屏幕使用时间」式布局——
/// 顶部本周汇总卡（总时长 + 7 天柱状图 + 经验/升级/日记数），
/// 中间「今天」分区（最常使用式行），其后按日分组展示更早记录。只读快照。
struct DiaryView: View {
    @State private var snapshot: DisplaySnapshot = SnapshotIO.load() ?? DisplaySnapshot()

    private var calendar: Calendar { Calendar.current }

    /// 本地日期 key（同日分组）
    private func dayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private func dayTitle(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "M月d日 EEEE"
        return f.string(from: date)
    }

    private var todayEntries: [DisplaySnapshot.DiaryDetail] {
        (snapshot.diaryDetail ?? []).filter { calendar.isDateInToday($0.recordedAt) }
    }

    private var earlierGrouped: [(key: String, title: String, entries: [DisplaySnapshot.DiaryDetail])] {
        let grouped = Dictionary(grouping: (snapshot.diaryDetail ?? [])
            .filter { !calendar.isDateInToday($0.recordedAt) },
            by: { dayKey($0.recordedAt) })
        return grouped
            .sorted { $0.key > $1.key }
            .compactMap { key, entries in
                guard let first = entries.first else { return nil }
                return (key: key, title: dayTitle(first.recordedAt),
                        entries: entries.sorted { $0.recordedAt > $1.recordedAt })
            }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    if let week = snapshot.weekStats {
                        WeekSummaryCard(week: week)
                    }
                    DiaryDaySection(title: "今天", entries: todayEntries,
                                    isToday: true)
                    ForEach(Array(earlierGrouped.enumerated()), id: \.element.key) { _, group in
                        DiaryDaySection(title: group.title, entries: group.entries,
                                        isToday: false)
                    }
                    if snapshot.diaryDetail == nil, let diaries = snapshot.recentDiaries, !diaries.isEmpty {
                        // 旧快照回退：结构化字段缺失时按原字符串列表展示
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(diaries.enumerated()), id: \.offset) { _, entry in
                                Text(entry).font(.callout)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemGroupedBackground),
                                    in: RoundedRectangle(cornerRadius: 14))
                    }
                    if snapshot.diaryDetail?.isEmpty ?? true, snapshot.recentDiaries?.isEmpty ?? true {
                        Text("还没有日记。完成首次设置并产生已确认修行时长后，这里会自动出现岛上生活的记录。")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                    }
                }
                .padding()
            }
            .navigationTitle("日记")
            .toolbar(.hidden, for: .navigationBar)
            .background(Color(.systemGroupedBackground))
            .onAppear {
                SettlementCoordinator.settlePending()
                snapshot = SnapshotIO.load() ?? DisplaySnapshot()
            }
        }
    }
}

/// 「本周」汇总卡（屏幕使用时间·每周模块风格）
private struct WeekSummaryCard: View {
    let week: DisplaySnapshot.WeekStats

    private var weekdayLabels: [String] { ["一", "二", "三", "四", "五", "六", "日"] }
    private var maxMinutes: Int { max(1, week.days.map(\.minutes).max() ?? 0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("本周").font(.headline)
                Spacer()
                Text(weekRangeTitle)
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text("\(week.totalMinutes)")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                Text("分钟修行")
                    .font(.title3).foregroundStyle(.secondary)
            }
            Text("获得经验 \(week.totalGrowthMilli / 1000) XP · 升级 \(week.levelGained) 级"
                 + " · 日记 \(week.diaryCount) 条")
                .font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(Array(week.days.enumerated()), id: \.offset) { index, day in
                    VStack(spacing: 4) {
                        if day.minutes > 0 {
                            Text("\(day.minutes)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isToday(day.date) ? Color.indigo : Color.indigo.opacity(0.3))
                            .frame(height: barHeight(day.minutes))
                        Text(weekdayLabels[index])
                            .font(.caption2)
                            .foregroundStyle(isToday(day.date) ? .primary : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 96)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16))
    }

    private var weekRangeTitle: String {
        let start = week.weekStart.formatted(.dateTime.month(.defaultDigits).day())
        return "\(start) – \(endTitle)"
    }

    private var endTitle: String {
        let end = Calendar.current.date(byAdding: .day, value: 6, to: week.weekStart) ?? week.weekStart
        return end.formatted(.dateTime.month(.defaultDigits).day())
    }

    private func isToday(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
    }

    private func barHeight(_ minutes: Int) -> CGFloat {
        minutes == 0 ? 4 : max(6, 72 * CGFloat(minutes) / CGFloat(maxMinutes))
    }
}

/// 单日分区（「最常使用」式行：图标 + 内容 + 奖励/时间）
private struct DiaryDaySection: View {
    let title: String
    let entries: [DisplaySnapshot.DiaryDetail]
    let isToday: Bool

    var body: some View {
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.headline)
                    .padding(.horizontal, 4)
                VStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                        DiaryEntryRow(entry: entry)
                        if index < entries.count - 1 {
                            Divider().padding(.leading, 44)
                        }
                    }
                }
                .padding(.vertical, 6)
                .background(Color(.secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }
}

private struct DiaryEntryRow: View {
    let entry: DisplaySnapshot.DiaryDetail

    /// 条目类型 → 图标与色调
    private var icon: (name: String, color: Color) {
        switch entry.entryType {
        case "monsterWin": return ("checkmark.seal.fill", .green)
        case "monsterLose": return ("xmark.seal.fill", .orange)
        case "oracleBoon": return ("sun.max.fill", .yellow)
        default: return ("book.fill", .teal)
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon.name)
                .font(.title3)
                .foregroundStyle(icon.color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.text).font(.callout)
                Text(entry.group)
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if !entry.rewardSummary.isEmpty {
                    Text(entry.rewardSummary)
                        .font(.caption).foregroundStyle(.indigo)
                }
                Text(entry.recordedAt, format: .dateTime.hour().minute())
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

/// 收藏页（行天改版 v2）：上方四宫格 = 当前装备四部位；下方"今日获得"分区
/// （与日记页当天同款行式，只保留当天获得的装备，过天自动清空）。探索自动获得，无需手动领取。
struct CollectionView: View {
    @State private var snapshot: DisplaySnapshot = SnapshotIO.load() ?? DisplaySnapshot()

    /// 今天获得的装备（acquiredAt 为当天；旧存档无获得时间的不计入）
    private var todayAcquired: [DisplaySnapshot.CollectionDetail] {
        (snapshot.collectionDetail ?? []).filter {
            guard let at = $0.acquiredAt else { return false }
            return Calendar.current.isDateInToday(at)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    if let equipped = snapshot.equippedDetail {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                                  spacing: 12) {
                            ForEach(Array(equipped.enumerated()), id: \.offset) { _, item in
                                EquippedGridCard(item: item)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("今日获得")
                            .font(.headline)
                            .padding(.horizontal, 4)
                        if !todayAcquired.isEmpty {
                            VStack(spacing: 0) {
                                ForEach(Array(todayAcquired.enumerated()), id: \.offset) { index, entry in
                                    CollectionEntryRow(entry: entry)
                                    if index < todayAcquired.count - 1 {
                                        Divider().padding(.leading, 44)
                                    }
                                }
                            }
                            .padding(.vertical, 6)
                            .background(Color(.secondarySystemGroupedBackground),
                                        in: RoundedRectangle(cornerRadius: 14))
                        } else {
                            Text("今天还没有新装备，继续修行，探索会自动发现。")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                                .background(Color(.secondarySystemGroupedBackground),
                                            in: RoundedRectangle(cornerRadius: 14))
                        }
                    }

                    // 旧快照回退：无结构化字段时按原字符串列表展示
                    if snapshot.collectionDetail == nil, let collection = snapshot.collection,
                       !collection.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(collection.enumerated()), id: \.offset) { _, entry in
                                Text(entry).font(.callout)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemGroupedBackground),
                                    in: RoundedRectangle(cornerRadius: 14))
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                SettlementCoordinator.settlePending()
                snapshot = SnapshotIO.load() ?? DisplaySnapshot()
            }
        }
    }
}

/// 四宫格装备卡：每部位一张（部位图标 + 词条或"未装备"）
private struct EquippedGridCard: View {
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
        guard !item.isEmpty else { return .gray }
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
        VStack(spacing: 8) {
            Image(systemName: slotIcon)
                .font(.title2)
                .foregroundStyle(rarityColor)
                .opacity(item.isEmpty ? 0.35 : 1)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(rarityColor.opacity(item.isEmpty ? 0.05 : 0.14))
                )
            Text(item.slot)
                .font(.caption2)
                .foregroundStyle(.secondary)
            if item.isEmpty {
                Text("未装备")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                Text(item.affixText)
                    .font(.caption)
                    .foregroundStyle(rarityColor)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Text("评 \(item.totalValue)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct CollectionEntryRow: View {
    let entry: DisplaySnapshot.CollectionDetail

    /// 品阶 → 字体颜色（白/绿/蓝/紫/橙/红）
    private var rarityColor: Color {
        switch Rarity(rawValue: entry.rarity) {
        case .green: return .green
        case .blue: return .blue
        case .purple: return .purple
        case .orange: return .orange
        case .red: return .red
        default: return .primary // 白装
        }
    }

    /// 外观类型 → 图标（布/皮/铁/机甲）
    private var appearanceIcon: String {
        switch entry.appearance {
        case "皮甲": return "shield.lefthalf.filled"
        case "铁甲": return "shield.fill"
        case "机甲": return "cpu"
        default: return "tshirt.fill" // 布甲
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: appearanceIcon)
                .font(.title3)
                .foregroundStyle(rarityColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.text).font(.callout).foregroundStyle(rarityColor)
                    if entry.isEquipped {
                        Label("装备中", systemImage: "checkmark.seal.fill")
                            .font(.caption2).foregroundStyle(.cyan)
                    }
                }
                if let at = entry.acquiredAt {
                    Text("获得于 \(at.formatted(date: .abbreviated, time: .shortened))"
                         + (entry.origin.map { " · \($0)" } ?? ""))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
}
