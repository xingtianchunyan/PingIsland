import ActivityKit
import Foundation
import PingIslandKit

/// 结算协调器（执行文档 11.1：唯一结算入口；展示只读快照）。
/// 主 App 进入前台时调用：消费待结算队列 → 结算 → 刷新展示快照与 Live Activity。
public enum SettlementCoordinator {
    /// 本次新结算的事件数（0 = 无新数据）
    @discardableResult
    public static func settlePending() -> Int {
        let events = PendingEventQueue.drain()
        guard !events.isEmpty else { return 0 }

        do {
            let groups = GroupSelection.load().nonEmptyGroups
            let service = try SettlementService(store: store(), groups: groups,
                                                characterSeed: seed())
            let outcomes = service.process(events)
            let deltas = outcomes.compactMap { outcome -> SettlementDelta? in
                if case .settled(let d) = outcome { return d }
                return nil
            }
            refreshSnapshot(from: service.engine, latestDelta: deltas.last)
            updateLiveActivity(from: service.engine)
            return outcomes.filter { $0 != .duplicate }.count
        } catch {
            // 结算失败：事件已被 drain…保守策略：写回队列尾部，等待下次执行机会
            PendingEventQueue.enqueue(events)
            return 0
        }
    }

    /// 结算存储目录：优先 App Group 容器；模拟器/测试无容器时回退临时目录
    public static func store() -> JSONFileSettlementStore {
        let base = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: SharedStore.appGroup)
            ?? FileManager.default.temporaryDirectory
                .appendingPathComponent("pingisland-fallback", isDirectory: true)
        return JSONFileSettlementStore(directory: base.appendingPathComponent("settlement", isDirectory: true))
    }

    /// 调试桥（执行文档 13.1）：把模拟账本结算出的引擎状态同步到展示快照 / Widget / Live Activity，
    /// 让"注入模拟事件"能验证完整展示链路。仅调试面板的模拟数据使用，生产 DeviceActivity 链路不经过这里。
    public static func syncDisplayFromSimulated(_ engine: SettlementEngine) {
        refreshSnapshot(from: engine, latestDelta: nil)
        updateLiveActivity(from: engine)
    }

    private static func seed() -> UInt64 {
        UInt64(SharedStore.defaults?.integer(forKey: "characterSeed.v1") ?? 0) + 1
    }

    // MARK: - 展示刷新（展示失败不回滚结算，执行文档 11.1）

    private static func refreshSnapshot(from engine: SettlementEngine,
                                        latestDelta: SettlementDelta?) {
        // 调试"模拟过一天"偏移：今天 + N 天；展示层"今天"的判定基准随之一致
        let dayOffset = SharedStore.defaults?.integer(forKey: SharedStore.Keys.simDayOffset) ?? 0
        let effectiveToday = Calendar.current.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date()
        let today = dateString(effectiveToday)
        let priorityInput = PresentationInput(
            latestDelta: latestDelta,
            hasAnomalySleep: SharedStore.defaults?.bool(forKey: SharedStore.Keys.anomalySleep) ?? false,
            isNight: PresentationPolicy.isNight(Date()))
        let priority = PresentationPolicy.resolve(priorityInput)
        let recent = engine.diary.last
        // 上周锚点（第二十批：日记页本周/上周切换）
        let previousAnchor = Calendar.current.date(byAdding: .day, value: -7,
                                                   to: effectiveToday) ?? effectiveToday
        // 复杂子表达式先算成局部常量，避免巨型字面量类型检查超时
        let finalAttrs = engine.finalAttributes()
        let attributesDict: [String: Int] = finalAttrs.reduce(into: [String: Int]()) {
            $0[$1.key.rawValue] = $1.value
        }
        let equipmentSummaryTexts: [String] = engine.equipped
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { _, item in SnapshotPresentation.equipmentSummary(item) }
        let sortedEquipment = engine.equipment
            .sorted { ($0.rarity != $1.rarity) ? $0.rarity > $1.rarity : $0.id < $1.id }
        let collectionTexts: [String] = sortedEquipment.map { item in
            let worn = item.isEquipped ? " · 装备中" : ""
            return SnapshotPresentation.equipmentSummary(item) + worn
        }
        let collectionDetails: [DisplaySnapshot.CollectionDetail] = sortedEquipment.map { item in
            DisplaySnapshot.CollectionDetail(
                text: SnapshotPresentation.equipmentSummaryWithoutRarity(item),
                rarity: item.rarity.rawValue,
                isEquipped: item.isEquipped,
                acquiredAt: item.acquiredAt,
                origin: item.origin,
                appearance: item.appearanceOverride
                    ?? item.appearance
                    ?? EquipmentAppearance.appearanceType(
                        finalWisdom: finalAttrs[.wis, default: 0]))
        }
        let diaryDetails: [DisplaySnapshot.DiaryDetail] = engine.diary.reversed().map { entry in
            DisplaySnapshot.DiaryDetail(
                recordedAt: entry.recordedAt,
                text: DiaryText.display(entry.textKey),
                rewardSummary: entry.rewardSummary,
                entryType: entry.entryType.rawValue,
                group: entry.group.rawValue)
        }
        let recentTexts: [String] = engine.diary.suffix(30).reversed().map { entry in
            let reward = entry.rewardSummary.isEmpty ? "" : " · \(entry.rewardSummary)"
            return "\(shortTimestamp(entry.recordedAt)) · \(DiaryText.display(entry.textKey))\(reward)"
        }
        let fatigueStageRaw = FatigueRules.stage(
            confirmedMinutesTotal: engine.confirmedMinutes(on: today)).rawValue
        let recentEventText = recent
            .map { "日记：\((DiaryText.display($0.textKey)))（\($0.rewardSummary)）" } ?? "等待第一次结算"
        let snapshotVersion = (SnapshotIO.load()?.snapshotVersion ?? 0) + 1
        let banner = PresentationPolicy.banner(for: priority, input: priorityInput)
        let todayDiceValue = engine.segments[today]?.dice?.value ?? engine.previewDice(for: today)
        // 第二十一批：全量入快照（收藏墙 12×6 需要；旧 UI 只读计数不受影响）
        let skillDetails: [DisplaySnapshot.SkillDetail] = engine.skillCollection.items
            .sorted { ($0.rarity != $1.rarity) ? $0.rarity > $1.rarity : $0.level > $1.level }
            .map { DisplaySnapshot.SkillDetail(weekday: $0.weekday, isActive: $0.isActive,
                                               rarity: $0.rarity.rawValue, level: $0.level) }
        let snapshot = DisplaySnapshot(
            level: Int(engine.level),
            className: engine.classState?.rawValue ?? "觉醒中",
            fatigueStage: fatigueStageRaw,
            recentEvent: recentEventText,
            lastSettlementAt: recent?.recordedAt ?? Date(),
            snapshotVersion: snapshotVersion,
            displayPriority: priority.rawValue,
            bannerText: banner,
            // 展示最终属性（含已装备词条加成），否则角色面板与装备栏对不上
            attributes: attributesDict,
            equipment: equipmentSummaryTexts,
            recentDiaries: recentTexts,
            collection: collectionTexts,
            collectionDetail: collectionDetails,
            diaryDetail: diaryDetails,
            weekStats: makeWeekStats(from: engine, around: effectiveToday),
            previousWeekStats: makeWeekStats(from: engine, around: previousAnchor),
            // Phase A（D1-D4 默认）：卡面 3 技能（克制最近一次遭遇怪）、技能连结、图鉴
            cardSkills: CardSkillRules.select(owned: engine.skillCollection.items,
                                              countered: latestMonsterElement(in: engine)),
            skillLinks: SkillLinkRules.derive(owned: engine.skillCollection.items),
            bestiary: BestiaryRules.aggregate(diary: engine.diary),
            equippedDetail: equippedDetail(from: engine),
            skills: skillDetails,
            todayDice: todayDiceValue,
            dayOffset: dayOffset
        )
        SnapshotIO.save(snapshot)
    }

    /// 最近一次怪物遭遇的元素（卡面技能克制目标；无遭遇返回 nil）
    private static func latestMonsterElement(in engine: SettlementEngine) -> SkillElement? {
        for entry in engine.diary.reversed() where entry.entryType == .monsterWin
            || entry.entryType == .monsterLose {
            guard entry.textKey.hasPrefix("encounter.") else { continue }
            let body = String(entry.textKey.dropFirst("encounter.".count))
            let name = body.split(separator: ".", omittingEmptySubsequences: false)
                .first.map(String.init) ?? ""
            return Monster(rawValue: name)?.element
        }
        return nil
    }

    /// 本周一（本地日历，周一为一周之首）起 7 天聚合；anchor 为"今天"基准（含模拟偏移）
    private static func makeWeekStats(from engine: SettlementEngine,
                                      around anchor: Date) -> DisplaySnapshot.WeekStats {
        var calendar = Calendar.current
        calendar.firstWeekday = 2 // 周一
        let weekStart = calendar.date(
            from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: anchor)) ?? anchor
        var days: [DisplaySnapshot.WeekStats.DayBar] = []
        var totalMinutes = 0
        var totalMilli: Int64 = 0
        for i in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: i, to: weekStart) else { continue }
            let stats = engine.dayStats[dateString(date)]
            let minutes = stats?.minutes ?? 0
            let milli = stats?.growthMilli ?? 0
            days.append(DisplaySnapshot.WeekStats.DayBar(date: date, minutes: minutes,
                                                         growthMilli: milli))
            totalMinutes += minutes
            totalMilli += milli
        }
        let diaryCount = engine.diary.filter { $0.recordedAt >= weekStart }.count
        let levelGained = days.reduce(0) { $0 + (engine.dayStats[dateString($1.date)]?.levelGained ?? 0) }
        return DisplaySnapshot.WeekStats(weekStart: weekStart, totalMinutes: totalMinutes,
                                         totalGrowthMilli: totalMilli, levelGained: levelGained,
                                         diaryCount: diaryCount, days: days)
    }

    /// 角色页装备栏：四部位（头部/上身/下身/足部），未装备部位 isEmpty
    private static func equippedDetail(from engine: SettlementEngine) -> [DisplaySnapshot.EquippedDetail] {
        let wisdom = engine.finalAttributes()[.wis, default: 0]
        return EquipmentSlot.allCases.map { slot in
            guard let item = engine.equipped[slot] else {
                return DisplaySnapshot.EquippedDetail(slot: slot.rawValue, isEmpty: true,
                                                      rarity: 0, appearance: "",
                                                      affixText: "", totalValue: 0)
            }
            let affixText = item.affixes
                .map { "\($0.attribute.rawValue) +\($0.value)" }
                .joined(separator: "、")
            return DisplaySnapshot.EquippedDetail(
                slot: slot.rawValue, isEmpty: false, rarity: item.rarity.rawValue,
                appearance: item.appearanceOverride
                    ?? item.appearance
                    ?? EquipmentAppearance.appearanceType(finalWisdom: wisdom),
                affixText: affixText, totalValue: item.totalValue,
                acquiredAt: item.acquiredAt, origin: item.origin)
        }
    }

    private static func shortTimestamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }

    private static func updateLiveActivity(from engine: SettlementEngine) {
        let state = PingIslandActivityAttributes.ContentState(
            level: Int(engine.level),
            className: engine.classState?.rawValue ?? "觉醒中",
            recentEvent: engine.diary.last.map { DiaryText.display($0.textKey) } ?? "等待第一次结算")
        for activity in Activity<PingIslandActivityAttributes>.activities {
            Task { await activity.update(using: state) }
        }
    }

    private static func dateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }
}
