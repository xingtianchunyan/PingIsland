import Foundation

/// 共享容器（App Group）访问 —— 展示快照的唯一读取通道。
/// 展示与结算分离：Widget/灵动岛/App 只读本快照，绝不执行结算。
public enum SharedStore {
    public static let appGroup = "group.com.pingisland.shared"

    public static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroup)
    }

    public enum Keys {
        public static let snapshot = "displaySnapshot.v1"
        public static let onboardingComplete = "onboardingComplete.v1"
        public static let selectionVersion = "selectionVersion.v1"
        public static let monitorRegisteredAt = "monitorRegisteredAt.v1"
    }
}

/// 展示快照（执行文档 6.4）：展示层只读此结构
public struct DisplaySnapshot: Codable, Equatable {
    public var level: Int
    public var className: String
    public var fatigueStage: Int // 0 精神饱满 ... 4 休眠
    public var recentEvent: String
    public var lastSettlementAt: Date?
    public var snapshotVersion: Int

    public init(level: Int = 1, className: String = "觉醒中",
                fatigueStage: Int = 0, recentEvent: String = "等待第一次结算",
                lastSettlementAt: Date? = nil, snapshotVersion: Int = 1) {
        self.level = level
        self.className = className
        self.fatigueStage = fatigueStage
        self.recentEvent = recentEvent
        self.lastSettlementAt = lastSettlementAt
        self.snapshotVersion = snapshotVersion
    }

    public var fatigueText: String {
        switch fatigueStage {
        case 0: return "精神饱满"
        case 1: return "有些疲劳"
        case 2: return "打盹"
        case 3: return "倚靠休息"
        default: return "休眠"
        }
    }
}

public enum SnapshotIO {
    public static func save(_ snapshot: DisplaySnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        SharedStore.defaults?.set(data, forKey: SharedStore.Keys.snapshot)
    }

    public static func load() -> DisplaySnapshot? {
        guard let data = SharedStore.defaults?.data(forKey: SharedStore.Keys.snapshot) else { return nil }
        return try? JSONDecoder().decode(DisplaySnapshot.self, from: data)
    }
}
