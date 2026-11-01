import DeviceActivity
import FamilyControls
import Foundation
import PingIslandKit

/// 监控注册（执行文档 7.2/7.3）：每组独立 activity 与事件，标识稳定可持久化。
/// Phase 0 阈值：每组 30/60/90 分钟累计事件；数量与系统上限需真机实测记录。
enum MonitoringRegistrar {
    static func register(selections: [TrainingGroup: FamilyActivitySelection]) {
        let center = DeviceActivityCenter()
        center.stopMonitoring() // 先停旧配置，保证可重建

        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true)

        let thresholds = [30, 60, 90]
        var registeredAny = false
        for (group, selection) in selections {
            let hasTokens = !selection.applicationTokens.isEmpty
                || !selection.categoryTokens.isEmpty || !selection.webDomainTokens.isEmpty
            guard hasTokens else { continue }
            let activityName = DeviceActivityName("pingisland.g\(groupIndex(group))")
            var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
            for minutes in thresholds {
                let name = DeviceActivityEvent.Name(MonitorEventParser.name(group: group, minutes: minutes))
                events[name] = DeviceActivityEvent(applications: selection.applicationTokens,
                                                   categories: selection.categoryTokens,
                                                   webDomains: selection.webDomainTokens,
                                                   threshold: DateComponents(minute: minutes))
            }
            do {
                try center.startMonitoring(activityName, during: schedule, events: events)
                registeredAny = true
            } catch {
                // 单组注册失败不阻塞其他组；记录错误提供重建入口（执行文档 13.3）
                appendLog("register.failed.\(group.rawValue).\(error.localizedDescription)")
            }
        }
        if registeredAny {
            SharedStore.defaults?.set(Date(), forKey: SharedStore.Keys.monitorRegisteredAt)
        } else {
            SharedStore.defaults?.removeObject(forKey: SharedStore.Keys.monitorRegisteredAt)
        }
    }

    private static func groupIndex(_ group: TrainingGroup) -> Int {
        TrainingGroup.allCases.firstIndex(of: group) ?? 0
    }

    private static func appendLog(_ line: String) {
        let key = "monitor.register.v1"
        let stamp = ISO8601DateFormatter().string(from: Date())
        let entry = "[\(stamp)] \(line)"
        var lines = SharedStore.defaults?.stringArray(forKey: key) ?? []
        lines.append(entry)
        if lines.count > 50 { lines.removeFirst(lines.count - 50) }
        SharedStore.defaults?.set(lines, forKey: key)
    }
}
