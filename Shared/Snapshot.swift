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
        /// 恢复层确认异常休眠（执行文档 11.4 最高展示优先级）
        public static let anomalySleep = "anomalySleep.v1"
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
    /// 展示优先级（执行文档 11.4，DisplayPriority rawValue；nil = 日常姿态）
    public var displayPriority: Int?
    /// 优先级横幅文案（nil = 用最近事件展示）
    public var bannerText: String?

    public init(level: Int = 1, className: String = "觉醒中",
                fatigueStage: Int = 0, recentEvent: String = "等待第一次结算",
                lastSettlementAt: Date? = nil, snapshotVersion: Int = 1,
                displayPriority: Int? = nil, bannerText: String? = nil) {
        self.level = level
        self.className = className
        self.fatigueStage = fatigueStage
        self.recentEvent = recentEvent
        self.lastSettlementAt = lastSettlementAt
        self.snapshotVersion = snapshotVersion
        self.displayPriority = displayPriority
        self.bannerText = bannerText
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

    /// 距最近确认记录默认超过 6 小时：卡片展示“休眠／等待同步”（执行文档 11.2）。
    /// 仅展示口径，不据此判定系统故障。
    public var isStale: Bool {
        guard let at = lastSettlementAt else { return true } // 从未结算：等待同步
        return Date().timeIntervalSince(at) > 6 * 3600
    }

    /// 卡片状态行：优先级横幅 > 休眠 > 最近事件
    public var widgetStatusText: String {
        if let banner = bannerText { return banner }
        return isStale ? "休眠 · 等待同步" : recentEvent
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
