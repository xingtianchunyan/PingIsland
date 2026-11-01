/// 技能抽选（执行文档 9.6）：每个有效使用分钟只做一次逻辑技能抽选，
/// 由（角色种子、当日骰点、有效分钟序号、星期）确定性重建；
/// 不创建后台任务、不保存动画帧、不批量补播。
public struct SkillDraw: Equatable, Sendable {
    /// 当日六行模板
    public var template: SkillRules.DayTemplate
    /// 稀有度（1~6）
    public var rarity: Rarity
    /// true=主动（只影响演出）；false=被动（固定加成）
    public var isActive: Bool
    /// 被动数值（稀有度序号 × Lv1 倍率）；主动为 0
    public var passiveValue: Int
}

public enum SkillDrawRules {
    /// 第 minuteIndex 个有效分钟（1-based）的确定性抽选。
    /// 同一输入永远得到同一结果；不同分钟序号结果独立。
    public static func draw(characterSeed: UInt64, dice: Int,
                            minuteIndex: Int, weekday: Int) -> SkillDraw {
        var rng = SeededRandom(seed: fnv1a64("skill|\(characterSeed)|\(dice)|\(minuteIndex)|\(weekday)"))
        let rarity = rollExplorationRarity(dice: dice, rng: &rng)
        let isActive = rng.nextInt(upperBound: 2) == 0
        let template = SkillRules.template(forWeekday: weekday)
        return SkillDraw(template: template, rarity: rarity, isActive: isActive,
                         passiveValue: isActive ? 0
                             : SkillRules.passiveValue(rarity: rarity, level: 1))
    }

    /// 连续 count 分钟的抽选序列（批量重建用，等价于逐分钟调用）
    public static func sequence(characterSeed: UInt64, dice: Int,
                                fromMinute start: Int, count: Int, weekday: Int) -> [SkillDraw] {
        (0..<max(0, count)).map { draw(characterSeed: characterSeed, dice: dice,
                                       minuteIndex: start + $0, weekday: weekday) }
    }
}
