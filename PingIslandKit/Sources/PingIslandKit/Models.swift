/// 六项属性
public enum Attribute: String, CaseIterable, Codable, Sendable {
    case con = "CON" // 体力
    case int = "INT" // 智力
    case dex = "DEX" // 敏捷
    case luk = "LUK" // 运气
    case wis = "WIS" // 智慧
    case cha = "CHA" // 魅力
}

/// 装备等阶（白/绿/蓝/紫/橙/红），序号为 1...6
public enum Rarity: Int, CaseIterable, Codable, Comparable, Sendable {
    case white = 1, green = 2, blue = 3, purple = 4, orange = 5, red = 6

    public static func < (lhs: Rarity, rhs: Rarity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// 职业（觉醒后定型，一次定型不自动重判）
public enum CharacterClass: String, Codable, Sendable {
    case bard = "吟游诗人"        // 社交/通讯
    case archmage = "大法师"      // 效率/办公
    case gladiator = "角斗士"     // 游戏
    case oracle = "先知"          // 阅读/资讯/学习
    case wanderArtist = "游荡艺人" // 视频/音乐/娱乐
    case alchemist = "炼金术士"   // 购物/财务
    case monk = "武僧"            // 健康/运动
    case ranger = "流浪者"        // 其他/均衡
}

/// 装备部位
public enum EquipmentSlot: String, CaseIterable, Codable, Sendable {
    case head = "头部"
    case body = "上身"
    case legs = "下身"
    case feet = "足部"
}

/// 修行组与倾向属性的映射（执行文档 5.2）。单一实现来源，不散落代码。
public enum TrainingGroup: String, CaseIterable, Codable, Sendable {
    case social = "社交/通讯"
    case productivity = "效率/办公"
    case games = "游戏"
    case reading = "阅读/资讯/学习"
    case entertainment = "视频/音乐/娱乐"
    case shopping = "购物/财务"
    case health = "健康/运动"
    case other = "其他"

    /// 该组对初始属性随机分配的倾向属性
    public var inclination: Attribute {
        switch self {
        case .social: return .cha
        case .productivity: return .int
        case .games: return .dex
        case .reading: return .wis
        case .entertainment: return .cha
        case .shopping: return .luk
        case .health: return .con
        case .other: return .luk // “其他”倾向平均，见 initialAttributeWeights
        }
    }

    public var correspondingClass: CharacterClass {
        switch self {
        case .social: return .bard
        case .productivity: return .archmage
        case .games: return .gladiator
        case .reading: return .oracle
        case .entertainment: return .wanderArtist
        case .shopping: return .alchemist
        case .health: return .monk
        case .other: return .ranger
        }
    }
}
