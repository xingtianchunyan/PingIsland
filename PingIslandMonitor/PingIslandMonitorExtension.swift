import DeviceActivity
import Foundation
import PingIslandKit

/// DeviceActivityMonitor 扩展（执行文档 7）：接收阈值事件，最小化写入待结算队列。
/// 结算不在扩展内发生：主 App 下次执行机会时经 SettlementCoordinator 统一结算。
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
        // 已确认里程碑：解析阈值分钟数，以稳定事件身份入队。
        // 注意：事件名格式 pingisland.threshold.<分钟>；分组归属在八组选择接入后细化（见 MonitoringRegistrar）。
        let parts = event.rawValue.split(separator: ".")
        guard parts.count == 3, let minutes = Int(parts[2]) else {
            appendLog("threshold.unparsed.\(event.rawValue)")
            return
        }
        let now = Date()
        let usage = UsageEvent(
            stableEventID: "\(dateString(now)).\(event.rawValue)", // 每事件每日唯一，重试不重
            group: .other, // Phase 2：按 selectionVersion 映射到修行组
            thresholdMinutes: minutes,
            localDate: dateString(now),
            confirmedAt: now)
        PendingEventQueue.enqueue([usage])
        appendLog("threshold.queued.\(event.rawValue)")
    }

    override func intervalWillStartWarning(for activity: DeviceActivityName) {
        super.intervalWillStartWarning(for: activity)
    }

    override func intervalWillEndWarning(for activity: DeviceActivityName) {
        super.intervalWillEndWarning(for: activity)
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

    private func dateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }
}
