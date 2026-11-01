/// 游戏日分段（执行文档 8.5/10.3）：当地 00:00 为唯一换日边界；
/// 骰点抽取后永久保存，同日不重抽；神谕奖励每日只发一次。

public struct GameDaySegment: Equatable, Codable, Sendable {
    public var segmentID: Int64
    public var localDate: String // YYYY-MM-DD
    public var timeZoneID: String
    public var dice: DailyDice?
    public var oracleRewardIssued: Bool = false
    public var explorationsUsedByGroup: [TrainingGroup: Int] = [:]

    public init(segmentID: Int64, localDate: String, timeZoneID: String) {
        self.segmentID = segmentID
        self.localDate = localDate
        self.timeZoneID = timeZoneID
    }

    /// 首次结算时建立骰点；同日不重抽（已存在则返回现有骰点）
    public mutating func ensureDice(luckSnapshot: Int,
                                    rng: inout some RandomSource) -> DailyDice {
        if let dice { return dice }
        let rolled = DiceRules.roll(luckSnapshot: luckSnapshot, rng: &rng)
        dice = rolled
        return rolled
    }

    /// 神谕奖励（骰点 20 触发的高级奖励）每日只发一次
    public mutating func tryIssueOracleReward() -> Bool {
        guard !oracleRewardIssued else { return false }
        oracleRewardIssued = true
        return true
    }

    /// 每组每日探索上限
    public mutating func tryConsumeExploration(for group: TrainingGroup,
                                               max: Int = RulesConfig().maxExplorationsPerGroupPerDay) -> Bool {
        let used = explorationsUsedByGroup[group, default: 0]
        guard used < max else { return false }
        explorationsUsedByGroup[group] = used + 1
        return true
    }
}
