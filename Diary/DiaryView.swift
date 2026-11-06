import PingIslandKit
import SwiftUI

/// 日记页（执行文档 5.3-2 / 9.7）：「屏幕使用时间」式布局——
/// 顶部本周汇总卡（总时长 + 7 天柱状图 + 经验/升级/日记数），
/// 中间「今天」分区（最常使用式行），其后按日分组展示更早记录。只读快照。
struct DiaryView: View {
    @State private var snapshot: DisplaySnapshot = SnapshotIO.load() ?? DisplaySnapshot()

    private var calendar: Calendar { Calendar.current }

    /// "今天"判定基准：真实今天 + 模拟过天偏移（调试面板"模拟过一天"）
    private var effectiveToday: Date {
        calendar.date(byAdding: .day, value: snapshot.dayOffset, to: Date()) ?? Date()
    }

    private func isEffectiveToday(_ date: Date) -> Bool {
        calendar.isDate(date, inSameDayAs: effectiveToday)
    }

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
        (snapshot.diaryDetail ?? []).filter { isEffectiveToday($0.recordedAt) }
    }

    private var earlierGrouped: [(key: String, title: String, entries: [DisplaySnapshot.DiaryDetail])] {
        let grouped = Dictionary(grouping: (snapshot.diaryDetail ?? [])
            .filter { !isEffectiveToday($0.recordedAt) },
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
                        WeekSummaryCard(week: week, today: effectiveToday)
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
            .padding(.top, 10)
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
    /// "今天"基准（含模拟过天偏移）：柱状图高亮跟随
    let today: Date

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
        Calendar.current.isDate(date, inSameDayAs: today)
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

/// 收藏页（行天改版 v2 + holo 升级）：上方四宫格 = 当前装备四部位，
/// 点按卡片放大为可小角度翻转的 2.5D 万智牌式卡牌（闪卡按品阶），
/// 再点按回归原样。下方"今日获得"分区与日记页当天同款行式。探索自动获得，无需手动领取。
struct CollectionView: View {
    @State private var snapshot: DisplaySnapshot = SnapshotIO.load() ?? DisplaySnapshot()
    /// 当前放大展示的装备卡（nil = 无放大）
    @State private var expandedItem: DisplaySnapshot.EquippedDetail?

    /// 今天获得的装备（acquiredAt 在"有效今天"内；旧存档无获得时间的不计入）
    private var effectiveToday: Date {
        Calendar.current.date(byAdding: .day, value: snapshot.dayOffset, to: Date()) ?? Date()
    }

    private var todayAcquired: [DisplaySnapshot.CollectionDetail] {
        (snapshot.collectionDetail ?? []).filter {
            guard let at = $0.acquiredAt else { return false }
            return Calendar.current.isDate(at, inSameDayAs: effectiveToday)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        if let equipped = snapshot.equippedDetail {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                                      spacing: 12) {
                                ForEach(Array(equipped.enumerated()), id: \.offset) { _, item in
                                    EquippedGridCard(item: item) {
                                        guard !item.isEmpty else { return }
                                        withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) {
                                            expandedItem = item
                                        }
                                    }
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
            .padding(.top, 10)
            .background(Color(.systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                SettlementCoordinator.settlePending()
                snapshot = SnapshotIO.load() ?? DisplaySnapshot()
            }

            // 放大的 2.5D 装备卡：点按/下拉关闭，卡面可拖动小角度翻转
            if let item = expandedItem {
                ExpandedEquipmentCard(item: item) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        expandedItem = nil
                    }
                }
                .zIndex(10)
            }
            } // ZStack
        } // NavigationStack
    }
}

/// 放大态装备卡：半透明遮罩 + 居中 2.5D 万智牌式卡牌（HoloTilt 提供拖动翻转）
private struct ExpandedEquipmentCard: View {
    let item: DisplaySnapshot.EquippedDetail
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)
                .transition(.opacity)
            GeometryReader { geo in
                HoloTilt {
                    EquipmentHoloCard(item: item)
                }
                .frame(width: min(320, geo.size.width - 48))
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
                .onTapGesture(perform: onDismiss)
            }
        }
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        "\(item.slot)装备卡，\(item.affixText)，评\(item.totalValue)，轻点收起"
    }
}

/// 装备万智牌卡：白/绿/蓝普通；紫银边闪；橙金边闪；红全彩闪（HoloFoil.equipment）
private struct EquipmentHoloCard: View {
    let item: DisplaySnapshot.EquippedDetail

    private var rarityColor: Color {
        guard !item.isEmpty else { return .gray }
        switch Rarity(rawValue: item.rarity) {
        case .green: return .green
        case .blue: return .blue
        case .purple: return .purple
        case .orange: return .orange
        case .red: return .red
        default: return Color(white: 0.35)
        }
    }

    private var rarityName: String {
        switch Rarity(rawValue: item.rarity) {
        case .green: return "绿"
        case .blue: return "蓝"
        case .purple: return "紫"
        case .orange: return "橙"
        case .red: return "红"
        default: return "白"
        }
    }

    /// 部位主视觉符号
    private var slotIcon: String {
        switch item.slot {
        case "头部": return "crown.fill"
        case "上身": return "tshirt.fill"
        case "下身": return "figure.walk"
        default: return "shoe.fill" // 足部
        }
    }

    /// 外观类型 → 副视觉符号
    private var appearanceIcon: String {
        switch item.appearance {
        case "皮甲": return "shield.lefthalf.filled"
        case "铁甲": return "shield.fill"
        case "机甲": return "cpu"
        default: return "tshirt.fill" // 布甲
        }
    }

    /// 部位主视觉：装备立绘（接 eq_部位_外观 美术资产；缺失时降级 SF Symbol）
    @ViewBuilder
    private var slotArt: some View {
        if let key = CardArt.equipmentArtKey(slot: item.slot, appearance: item.appearance) {
            Image(key)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(10)
        } else {
            Image(systemName: slotIcon)
                .font(.system(size: 84, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
        }
    }

    /// 品阶 → 风味语
    private var flavorText: String {
        switch Rarity(rawValue: item.rarity) {
        case .purple: return "\n边缘流转着银色的微光，某种远方的魔法尚未散尽。"
        case .orange: return "\n金色纹路沿边缘游走，仿佛有熔金在其中流动。"
        case .red: return "\n整张卡都在虹彩中呼吸。传说它来自世界的裂缝。"
        default: return "\n它在探索中被发现，安静地陪在主人身边。"
        }
    }

    /// 获得信息（第十八批）：装备卡上同步展示来源，过天后仍可追溯
    private var originLine: String {
        guard let at = item.acquiredAt else { return "" }
        let when = at.formatted(date: .abbreviated, time: .shortened)
        return "\n—— 获得于 \(when)\(item.origin.map { " · \($0)" } ?? "")"
    }

    var body: some View {
        MTGCardView(
            name: "\(item.slot) · \(item.appearance)",
            costBadge: "\(item.totalValue)",
            typeLine: "装备 · \(rarityName)阶 · 评 \(item.totalValue)",
            textBox: item.affixText + flavorText + originLine,
            foil: HoloFoil.equipment(rarity: item.rarity),
            rarityColor: rarityColor
        ) {
            ZStack {
                LinearGradient(colors: [rarityColor.opacity(0.55), rarityColor.opacity(0.15)],
                               startPoint: .top, endPoint: .bottom)
                slotArt
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Image(systemName: appearanceIcon)
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(10)
                            .background(Circle().fill(.black.opacity(0.25)))
                            .padding(10)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// 四宫格装备卡：每部位一张（部位图标 + 词条或"未装备"）；
/// 点按放大为 2.5D 卡牌（未装备不可放大）
private struct EquippedGridCard: View {
    let item: DisplaySnapshot.EquippedDetail
    var onTap: () -> Void = {}

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
            // 装备立绘（接美术资产；缺失降级 SF Symbol）
            Group {
                if let key = CardArt.equipmentArtKey(slot: item.slot, appearance: item.appearance) {
                    Image(key)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: slotIcon)
                        .font(.title2)
                }
            }
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
        .frame(height: 132)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 14))
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture(perform: onTap)
        .opacity(item.isEmpty ? 0.8 : 1)
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
        HStack(spacing: 12) {
            Image(systemName: appearanceIcon)
                .font(.title3)
                .foregroundStyle(rarityColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.text).font(.callout).foregroundStyle(rarityColor)
                if let at = entry.acquiredAt {
                    Text((entry.origin.map { "\($0) · " } ?? "")
                         + at.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if entry.isEquipped {
                Image(systemName: "checkmark.seal.fill")
                    .font(.caption)
                    .foregroundStyle(.cyan)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
