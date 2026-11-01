import DeviceActivity
import FamilyControls
import Foundation

/// 监控注册（执行文档 7.2/7.3：Phase 0 先用 30/60/90 分钟累计阈值验证）
enum MonitoringRegistrar {
    static func register(selection: FamilyActivitySelection) {
        let center = DeviceActivityCenter()
        center.stopMonitoring() // 先停旧配置，保证可重建

        // 全天重复的监控周期
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true)

        // Phase 0 阈值：30/60/90 分钟累计事件（每组共用同一选择，
        // 分组归属在 Phase 2 由 selectionVersion + 分组映射细化）
        let thresholds = [30, 60, 90]
        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
        for minutes in thresholds {
            let name = DeviceActivityEvent.Name("pingisland.threshold.\(minutes)")
            events[name] = DeviceActivityEvent(applications: selection.applicationTokens,
                                               categories: selection.categoryTokens,
                                               webDomains: selection.webDomainTokens,
                                               threshold: DateComponents(minute: minutes))
        }

        do {
            try center.startMonitoring(.daily, during: schedule, events: events)
            SharedStore.defaults?.set(Date(), forKey: SharedStore.Keys.monitorRegisteredAt)
        } catch {
            // 监控注册失败：记录错误，提供重建入口（执行文档 13.3）
            SharedStore.defaults?.removeObject(forKey: SharedStore.Keys.monitorRegisteredAt)
        }
    }
}

extension DeviceActivityName {
    static let daily = DeviceActivityName("pingisland.daily")
}
