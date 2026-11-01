/// 每日骰子（执行文档 8.5）。
/// 骰点在分段首次结算时抽取并永久保存，同日不重抽。

/// 每日骰子结果：D 与成长倍率（定点，倍率 10 = 100%）
public struct DailyDice: Equatable, Codable, Sendable {
    public let value: Int // [minRoll, 20]
    public var growthMultiplierTenths: Int { value } // 成长倍率 = D/10，定点 0.1
}

public enum DiceRules {
    /// 最低骰点 = min(10, 1 + floor(运气快照 / 100))
    /// 运气 900 及以上：d11+9 → 范围 10~20
    public static func minimumRoll(luckSnapshot: Int) -> Int {
        min(10, 1 + luckSnapshot / 100)
    }

    /// 抽取当日骰点；[最低骰点, 20] 均匀整数
    public static func roll(luckSnapshot: Int, rng: inout some RandomSource) -> DailyDice {
        let lo = minimumRoll(luckSnapshot: luckSnapshot)
        return DailyDice(value: rng.nextInt(lowerBound: lo, upperBound: 20))
    }

    /// 骰点区间判定（用于稀有度表与奖励类型）
    public static func band(_ d: Int) -> Int {
        if d <= 10 { return 1 }
        if d <= 19 { return 2 }
        return 3
    }
}
