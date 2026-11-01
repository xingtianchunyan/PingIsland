/// 职业觉醒判定（执行文档 10.1）。
/// 观察期最短 7 个当地自然日（开始当天为第 1 日）；只使用可可靠归属到观察期的已确认量；
/// 到期且总确认量 ≥60 分钟才判定，不足则延长；一次定型，不自动重判（调用方定型后不再调用）。

public enum ClassAwakening {
    public struct ObservationInput: Equatable, Sendable {
        public var group: TrainingGroup
        /// 可可靠归属到观察期的已确认分钟
        public var confirmedMinutes: Int
        public init(group: TrainingGroup, confirmedMinutes: Int) {
            self.group = group
            self.confirmedMinutes = confirmedMinutes
        }
    }

    public enum Outcome: Equatable, Sendable {
        case awakening              // 未满 7 日或不足 60 分钟：延长观察
        case awakened(CharacterClass)
    }

    public static let minObservationDays = 7
    public static let minConfirmedMinutes = 60
    /// 最高组与第二组占比差不足该值（百分点）判流浪者
    public static let tieThreshold = 0.01

    public static func judge(daysObserved: Int,
                             inputs: [ObservationInput]) -> Outcome {
        let total = inputs.reduce(0) { $0 + $1.confirmedMinutes }
        guard daysObserved >= minObservationDays,
              total >= minConfirmedMinutes else { return .awakening }

        let sorted = inputs.filter { $0.confirmedMinutes > 0 }
            .sorted { $0.confirmedMinutes > $1.confirmedMinutes }
        guard let top = sorted.first else { return .awakened(.ranger) }

        // “其他”组最高也判流浪者
        if top.group == .other { return .awakened(.ranger) }

        let second = sorted.count > 1 ? sorted[1].confirmedMinutes : 0
        let topShare = Double(top.confirmedMinutes) / Double(total)
        let secondShare = Double(second) / Double(total)
        // 占比差不足 1 个百分点 → 流浪者
        if topShare - secondShare < tieThreshold { return .awakened(.ranger) }
        return .awakened(top.group.correspondingClass)
    }
}
