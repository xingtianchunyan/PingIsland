/// 概率与数值配置的单一实现来源（执行文档 9.1/9.6）。
/// 所有表格集中于此；测试校验行和为 100%。

/// 探索奖励类型：基础属性包 / 装备 / 主动技能 / 被动特质
public enum RewardKind: String, Codable, Sendable {
    case attributePack
    case equipment
    case activeSkill
    case passiveSkill
}

public struct RulesConfig: Sendable {
    /// 探索里程碑阈值（分钟）：每组每确认 30 分钟一次探索
    public var explorationThresholdMinutes: Int = 30
    /// 每组每日探索上限
    public var maxExplorationsPerGroupPerDay: Int = 5
    /// 魅力追加装备概率分母：p = min(1, charm / charmDivisor)
    public var charmDivisor: Int = 10_000
    /// 骰点 20 的神谕奖励每日只发一次（由 GameDaySegment.oracleRewardIssued 保证）
    public var oracleDailyLimit: Int = 1

    public init() {}

    /// 探索稀有度概率表（执行文档 9.1，单位：%）。
    /// 行键为骰点区间，六个值依次为 白/绿/蓝/紫/橙/红。
    public static let rarityPercentByDice: [String: [Int]] = [
        "1-10":  [70, 30, 0, 0, 0, 0],
        "11-19": [35, 30, 20, 10, 4, 1],
        "20":    [0, 0, 0, 75, 20, 5],
    ]

    /// 基础属性包：1~3 点，等概率 CON/INT/DEX 一项
    public static let basePackAmounts: ClosedRange<Int> = 1...3
    public static let basePackAttributes: [Attribute] = [.con, .int, .dex]

    /// 高级属性包：5~10 点，等概率 LUK/WIS/CHA 一项
    public static let oraclePackAmounts: ClosedRange<Int> = 5...10
    public static let oraclePackAttributes: [Attribute] = [.luk, .wis, .cha]

    /// 被动技能等级倍率（%，Lv1~Lv5）
    public static let passiveLevelMultipliers: [Int] = [100, 130, 150, 165, 180]

    /// 装备模板表（执行文档 9.4）：等阶 → (基础词条数, 高级词条数, 每条固定值)
    public static let equipmentTable: [Rarity: (base: Int, advanced: Int, value: Int)] = [
        .white:  (1, 0, 1),
        .green:  (2, 0, 2),
        .blue:   (3, 0, 3),
        .purple: (3, 1, 4),
        .orange: (3, 2, 5),
        .red:    (3, 3, 6),
    ]
}

/// 探索稀有度抽取
public func rollExplorationRarity(dice: Int, rng: inout some RandomSource) -> Rarity {
    let row: [Int]
    if dice <= 10 { row = RulesConfig.rarityPercentByDice["1-10"]! }
    else if dice <= 19 { row = RulesConfig.rarityPercentByDice["11-19"]! }
    else { row = RulesConfig.rarityPercentByDice["20"]! }
    let index = rng.pickWeighted(row)
    return Rarity.allCases[index]
}

/// 探索奖励类型抽取（执行文档 9.1）
/// 返回 .activeSkill/.passiveSkill 时已命中技能抽取，由当日六行池继续定模板与稀有度
public func rollExplorationRewardKind(dice: Int, rng: inout some RandomSource) -> RewardKind {
    if dice >= 11 && dice <= 19 {
        // 先按 (D-10)×10% 抽主动/被动
        let skillChancePercent = (dice - 10) * 10
        if rng.nextInt(upperBound: 100) < skillChancePercent {
            return rng.nextInt(upperBound: 2) == 0 ? .activeSkill : .passiveSkill
        }
    }
    if dice >= 20 {
        return [.attributePack, .equipment, .activeSkill, .passiveSkill][rng.nextInt(upperBound: 4)]
    }
    // 1~10：基础属性包、装备各 50%
    return rng.nextInt(upperBound: 2) == 0 ? .attributePack : .equipment
}
