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
        let today = dateString(Date())
        let priorityInput = PresentationInput(
            latestDelta: latestDelta,
            hasAnomalySleep: SharedStore.defaults?.bool(forKey: SharedStore.Keys.anomalySleep) ?? false,
            isNight: PresentationPolicy.isNight(Date()))
        let priority = PresentationPolicy.resolve(priorityInput)
        let recent = engine.diary.last
        let snapshot = DisplaySnapshot(
            level: Int(engine.level),
            className: engine.classState?.rawValue ?? "觉醒中",
            fatigueStage: FatigueRules.stage(confirmedMinutesTotal: engine.confirmedMinutes(on: today)).rawValue,
            recentEvent: recent.map { "日记：\(DiaryText.display($0.textKey))（\($0.rewardSummary)）" } ?? "等待第一次结算",
            lastSettlementAt: recent?.recordedAt ?? Date(),
            snapshotVersion: (SnapshotIO.load()?.snapshotVersion ?? 0) + 1,
            displayPriority: priority.rawValue,
            bannerText: PresentationPolicy.banner(for: priority, input: priorityInput),
            // 展示最终属性（含已装备词条加成），否则角色面板与装备栏对不上
            attributes: engine.finalAttributes().reduce(into: [String: Int]()) {
                $0[$1.key.rawValue] = $1.value
            },
            equipment: engine.equipped
                .sorted { $0.key.rawValue < $1.key.rawValue }
                .map { _, item in SnapshotPresentation.equipmentSummary(item) },
            recentDiaries: engine.diary.suffix(30).reversed().map { entry in
                let reward = entry.rewardSummary.isEmpty ? "" : " · \(entry.rewardSummary)"
                return "\(shortTimestamp(entry.recordedAt)) · \(DiaryText.display(entry.textKey))\(reward)"
            },
            collection: engine.equipment
                .sorted { ($0.rarity != $1.rarity) ? $0.rarity > $1.rarity : $0.id < $1.id }
                .map { item in
                    let worn = item.isEquipped ? " · 装备中" : ""
                    return SnapshotPresentation.equipmentSummary(item) + worn
                },
            collectionDetail: engine.equipment
                .sorted { ($0.rarity != $1.rarity) ? $0.rarity > $1.rarity : $0.id < $1.id }
                .map { item in
                    DisplaySnapshot.CollectionDetail(
                        text: SnapshotPresentation.equipmentSummary(item),
                        rarity: item.rarity.rawValue,
                        isEquipped: item.isEquipped,
                        acquiredAt: item.acquiredAt,
                        origin: item.origin,
                        appearance: EquipmentAppearance.appearanceType(
                            finalWisdom: engine.finalAttributes()[.wis, default: 0]))
                })
        SnapshotIO.save(snapshot)
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
