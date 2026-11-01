import Foundation
import PingIslandKit

/// 模拟事件源（执行文档 13.1）：明确标注的 SimulatedUsageSource。
/// 与生产 DeviceActivity 账本完全隔离——独立存储目录、事件 ID 带 sim. 前缀、固定角色种子。
/// 只用于内部测试规则链路，不得用于宣称真实自动监控已通过；UI 必须显示“模拟数据”。
public enum SimulatedUsageSource {
    public static let directoryName = "settlement-simulated"
    /// 固定种子：模拟结果确定性可复现
    public static let seed: UInt64 = 42

    public static func store(base: URL) -> JSONFileSettlementStore {
        JSONFileSettlementStore(directory: base.appendingPathComponent(directoryName, isDirectory: true))
    }

    /// 模拟事件：stableEventID 带 sim. 前缀，与真实事件永不混淆
    public static func makeEvent(group: TrainingGroup, thresholdMinutes: Int,
                                 localDate: String, confirmedAt: Date, sequence: Int) -> UsageEvent {
        UsageEvent(stableEventID: "sim.\(localDate).\(group.rawValue).t\(thresholdMinutes).s\(sequence)",
                   group: group, thresholdMinutes: thresholdMinutes,
                   localDate: localDate, confirmedAt: confirmedAt)
    }

    /// 清空模拟账本（独立目录整体删除，不触碰生产账本）
    public static func reset(base: URL) {
        try? FileManager.default.removeItem(at: store(base: base).directory)
    }

    /// 模拟账本高水位：日志中事件总数
    public static func eventCount(base: URL) -> Int {
        guard let data = try? store(base: base).loadJournal(),
              let events = try? JSONDecoder().decode([UsageEvent].self, from: data)
        else { return 0 }
        return events.count
    }
}
