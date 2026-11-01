import DeviceActivity
import Foundation

/// DeviceActivityMonitor 扩展（执行文档 7）：接收阈值事件，最小化写入共享容器。
/// 注意：扩展内不做完整结算；真实结算在 Phase 2 接入 SettlementStore 事务。
class PingIslandMonitorExtension: DeviceActivityMonitor {
    private let defaults = UserDefaults(suiteName: SharedStore.appGroup)

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        appendLog("interval.start.\(activity.rawValue)")
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        appendLog("interval.end.\(activity.rawValue)")
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name,
                                         activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        // 已确认里程碑到达：记录事件身份，主 App 下次启动时结算
        // （结算幂等由稳定事件身份保证，重试不重抽）
        appendLog("threshold.\(event.rawValue)")
        updateSnapshot(event: event.rawValue)
    }

    override func intervalWillStartWarning(for activity: DeviceActivityName) {
        super.intervalWillStartWarning(for: activity)
    }

    override func intervalWillEndWarning(for activity: DeviceActivityName) {
        super.intervalWillEndWarning(for: activity)
    }

    /// 写展示快照：等级 +1 演示“自动成长”链路打通；正式公式由结算引擎在事务内统一提交
    private func updateSnapshot(event: String) {
        var snapshot = SnapshotIO.load() ?? DisplaySnapshot()
        snapshot.level += 1
        snapshot.recentEvent = "已确认里程碑：\(event)"
        snapshot.lastSettlementAt = Date()
        snapshot.snapshotVersion += 1
        SnapshotIO.save(snapshot)
    }

    private func appendLog(_ line: String) {
        let key = "monitor.log.v1"
        let stamp = ISO8601DateFormatter().string(from: Date())
        let entry = "[\(stamp)] \(line)"
        var lines = defaults?.stringArray(forKey: key) ?? []
        lines.append(entry)
        if lines.count > 100 { lines.removeFirst(lines.count - 100) }
        defaults?.set(lines, forKey: key)
    }
}
