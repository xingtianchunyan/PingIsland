import Foundation
import PingIslandKit

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
    /// 六维初始属性（Attribute rawValue → 点数）
    public var attributes: [String: Int]?
    /// 已装备摘要（执行文档 9.4 择优结果；预格式化展示串）
    public var equipment: [String]?
    /// 最近日记片段（新→旧，预格式化；执行文档 9.7）
    public var recentDiaries: [String]?
    /// 收藏页：装备藏品清单（品阶降序，预格式化）
    public var collection: [String]?
    /// 收藏页结构化详情（颜色/图标/获得时间来源用；nil = 旧快照，回退 collection 字符串）
    public var collectionDetail: [CollectionDetail]?
    /// 日记页结构化条目（周/日分区展示用；nil = 旧快照，回退 recentDiaries 字符串）
    public var diaryDetail: [DiaryDetail]?
    /// 日记页"本周"聚合（屏幕使用时间式周视图；nil = 旧快照，不展示周卡）
    public var weekStats: WeekStats?
    /// 角色页装备栏（部位 → 已装备详情；nil = 旧快照，回退 equipment 字符串）
    public var equippedDetail: [EquippedDetail]?
    /// 角色页技能/特质栏（skillCollection 降序取前 N；nil = 旧快照，不展示）
    public var skills: [SkillDetail]?
    /// 今日骰点（角色页特质栏展示；nil = 未知）
    public var todayDice: Int?

    /// 日记条目结构化展示数据
    public struct DiaryDetail: Equatable, Codable, Sendable {
        public var recordedAt: Date
        /// 已本地化展示文案（不含奖励）
        public var text: String
        /// 奖励摘要行（如「神谕奖励 +8 WIS」）
        public var rewardSummary: String
        /// DiaryEntryType rawValue（图标用）
        public var entryType: String
        /// 修行组（TrainingGroup rawValue，副标题用）
        public var group: String
    }

    /// 本周聚合（周一 00:00 起 7 天）
    public struct WeekStats: Equatable, Codable, Sendable {
        /// 本周一（本地日历）
        public var weekStart: Date
        public var totalMinutes: Int
        /// 本周入账 XP（千分之一；1000 = 1 XP）
        public var totalGrowthMilli: Int64
        public var levelGained: Int
        public var diaryCount: Int
        /// 周一~周日每天一根柱
        public var days: [DayBar]

        public struct DayBar: Equatable, Codable, Sendable {
            public var date: Date
            public var minutes: Int
            public var growthMilli: Int64
        }
    }

    /// 角色页装备栏条目（每部位一行；未装备 isEmpty = true）
    public struct EquippedDetail: Equatable, Codable, Sendable {
        /// EquipmentSlot rawValue（头部/上身/下身/足部）
        public var slot: String
        public var isEmpty: Bool
        /// Rarity rawValue（未装备为 0，UI 映射灰色）
        public var rarity: Int
        /// 外观类型（布甲/皮甲/铁甲/机甲 → 图标）
        public var appearance: String
        /// 词条摘要（「CON +1、INT +2」）
        public var affixText: String
        public var totalValue: Int
    }

    /// 角色页技能条目（skillCollection 项）
    public struct SkillDetail: Equatable, Codable, Sendable {
        /// 周模板（1=周一 … 7=周日）
        public var weekday: Int
        public var isActive: Bool
        /// Rarity rawValue（UI 映射颜色）
        public var rarity: Int
        /// 1...5
        public var level: Int
    }

    /// 收藏条目结构化展示数据（执行文档 5.3-3 增强展示）
    public struct CollectionDetail: Equatable, Codable, Sendable {
        /// 预格式化主文案（部位 · 品阶 · 词条（评 N））
        public var text: String
        /// 稀有度（Rarity rawValue；UI 映射字体颜色）
        public var rarity: Int
        public var isEquipped: Bool
        /// 获得时间（"从何时获得"）
        public var acquiredAt: Date?
        /// 获得原因（"因何事获得"）
        public var origin: String?
        /// 外观类型（布甲/皮甲/铁甲/机甲，图标用）
        public var appearance: String?
    }

    public init(level: Int = 1, className: String = "觉醒中",
                fatigueStage: Int = 0, recentEvent: String = "等待第一次结算",
                lastSettlementAt: Date? = nil, snapshotVersion: Int = 1,
                displayPriority: Int? = nil, bannerText: String? = nil,
                attributes: [String: Int]? = nil, equipment: [String]? = nil,
                recentDiaries: [String]? = nil, collection: [String]? = nil,
                collectionDetail: [CollectionDetail]? = nil,
                diaryDetail: [DiaryDetail]? = nil, weekStats: WeekStats? = nil,
                equippedDetail: [EquippedDetail]? = nil, skills: [SkillDetail]? = nil,
                todayDice: Int? = nil) {
        self.level = level
        self.className = className
        self.fatigueStage = fatigueStage
        self.recentEvent = recentEvent
        self.lastSettlementAt = lastSettlementAt
        self.snapshotVersion = snapshotVersion
        self.displayPriority = displayPriority
        self.bannerText = bannerText
        self.attributes = attributes
        self.equipment = equipment
        self.recentDiaries = recentDiaries
        self.collectionDetail = collectionDetail
        self.diaryDetail = diaryDetail
        self.weekStats = weekStats
        self.equippedDetail = equippedDetail
        self.skills = skills
        self.todayDice = todayDice
        self.collection = collection
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

    /// 六维属性一行摘要（中尺寸卡片，11.2）；无属性时为 nil
    public var attributeSummary: String? {
        guard let attributes, !attributes.isEmpty else { return nil }
        let parts = ["CON", "INT", "DEX", "LUK", "WIS", "CHA"]
            .compactMap { key -> String? in
                guard let value = attributes[key] else { return nil }
                return "\(key) \(value)"
            }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
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

/// 展示层格式化助手（执行文档 9.4/9.5 品阶文案）
public enum SnapshotPresentation {
    /// 装备展示：部位 · 品阶 · 具体词条（白装也显示 +1 随机基础属性；多条词条顿号分隔）
    public static func equipmentSummary(_ item: EquipmentItem) -> String {
        let affixText = item.affixes
            .map { "\($0.attribute.rawValue) +\($0.value)" }
            .joined(separator: "、")
        return "\(item.slot.rawValue) · \(rarityName(item.rarity)) · \(affixText)（评 \(item.totalValue)）"
    }

    /// 收藏页结构化条目用：品阶已由字体颜色表达，省略「白装/绿装」文字。
    public static func equipmentSummaryWithoutRarity(_ item: EquipmentItem) -> String {
        let affixText = item.affixes
            .map { "\($0.attribute.rawValue) +\($0.value)" }
            .joined(separator: "、")
        return "\(item.slot.rawValue) · \(affixText)（评 \(item.totalValue)）"
    }

    public static func rarityName(_ rarity: Rarity) -> String {
        switch rarity {
        case .white: return "白装"
        case .green: return "绿装"
        case .blue: return "蓝装"
        case .purple: return "紫装"
        case .orange: return "橙装"
        case .red: return "红装"
        }
    }
}
