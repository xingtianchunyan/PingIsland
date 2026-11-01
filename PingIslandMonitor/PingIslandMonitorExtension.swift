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
        // 已确认里程碑：解析组与阈值分钟数，以稳定事件身份入队。
        guard let parsed = MonitorEventParser.parse(event.rawValue) else {
            appendLog("threshold.unparsed.\(event.rawValue)")
            return
        }
        let now = Date()
        let usage = UsageEvent(
            stableEventID: "\(dateString(now)).\(event.rawValue)", // 每事件每日唯一，重试不重
            group: parsed.group,
            thresholdMinutes: parsed.minutes,
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
