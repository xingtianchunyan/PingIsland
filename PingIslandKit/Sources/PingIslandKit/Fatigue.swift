/// 疲劳叙事（执行文档 10.2）：只基于同一游戏日已确认总量，只改展示不改数值。

public enum FatigueStage: Int, Codable, CaseIterable, Sendable {
    case energetic = 0 // 精神饱满
    case tired = 1     // 疲劳、动作关键帧放缓
    case dozing = 2    // 打盹、站姿松散
    case leaning = 3   // 倚靠休息
    case dormant = 4   // 休眠姿态
}

public enum FatigueRules {
    /// 同一游戏日已确认总量（分钟）→ 疲劳阶段
    public static func stage(confirmedMinutesTotal: Int) -> FatigueStage {
        switch confirmedMinutesTotal {
        case ..<120: return .energetic     // 少于 2 小时
        case 120..<180: return .tired      // 2~3 小时
        case 180..<240: return .dozing     // 3~4 小时
        case 240..<360: return .leaning    // 4~6 小时
        default: return .dormant           // 6 小时及以上
        }
    }

    public static func text(_ stage: FatigueStage) -> String {
        switch stage {
        case .energetic: return "精神饱满"
        case .tired: return "有些疲劳"
        case .dozing: return "打盹"
        case .leaning: return "倚靠休息"
        case .dormant: return "休眠"
        }
    }
}
