import Foundation
import PingIslandKit

/// 待结算事件队列（执行文档 4.2）：监控扩展写入，主 App 消费。
/// 队列只经过 App Group 共享容器；结算仍只在 SettlementService 一处发生。
public enum PendingEventQueue {
    private static let key = "pendingEvents.v1"

    public static func enqueue(_ events: [UsageEvent]) {
        guard !events.isEmpty else { return }
        let defaults = SharedStore.defaults
        var queue = load()
        queue.append(contentsOf: events)
        if let data = try? JSONEncoder().encode(queue) {
            defaults?.set(data, forKey: key)
        }
    }

    /// 读出并清空：消费语义（读取失败返回空，绝不重复结算）
    public static func drain() -> [UsageEvent] {
        let events = load()
        SharedStore.defaults?.removeObject(forKey: key)
        return events
    }

    public static var count: Int { load().count }

    private static func load() -> [UsageEvent] {
        guard let data = SharedStore.defaults?.data(forKey: key),
              let events = try? JSONDecoder().decode([UsageEvent].self, from: data)
        else { return [] }
        return events
    }
}
