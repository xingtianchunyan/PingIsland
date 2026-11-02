/// 线性成长（执行文档 8.3），定点数十进制，不依赖二进制浮点比较整数临界。
///
/// 本段成长值 = 新增已确认分钟 × 当日骰子倍率 × 职业系数 × 成长被动系数
/// 整数成长点 G = floor(累计成长值)；角色等级 = 1 + G；基础智慧 = 初始智慧 + G
///
/// 成长值以"千分之一"定点存储（milli），1 成长点 = 1000 milli。

/// 职业成长系数，以有理数表示：110/100 = 1.10，103/100 = 1.03
public struct GrowthFactor: Equatable, Codable, Sendable {
    public var numerator: Int
    public var denominator: Int

    public init(numerator: Int, denominator: Int = 100) {
        self.numerator = numerator
        self.denominator = denominator
    }

    /// 未觉醒职业系数 1
    public static let neutral = GrowthFactor(numerator: 100)
    /// 非流浪者对应组 +10%
    public static let matched = GrowthFactor(numerator: 110)
    /// 流浪者所有组 +3%
    public static let ranger = GrowthFactor(numerator: 103)
}

public struct GrowthAccumulator: Equatable, Codable, Sendable {
    /// 累计成长值（千分之一成长点）
    public private(set) var totalMilli: Int64 = 0

    public init() {}

    /// 结算一段已确认分钟。
    /// - dice: 当日骰点 D（成长倍率 = D/10）
    /// - factor: 职业系数（默认 1）
    /// - passiveTenths: 成长被动系数定点 0.1（默认 10 = 1.0），首版恒为 1，仅保留扩展位
    /// - 返回：本段成长值（千分之一成长点）
    @discardableResult
    public mutating func settle(minutes: Int, dice: Int,
                                factor: GrowthFactor = .neutral,
                                passiveTenths: Int = 10) -> Int64 {
        // 成长值 = minutes × (D/10) × (num/den) × (passiveTenths/10)
        // 千分之一定点：milli = minutes × D × num × passiveTenths × 10 / den
        let segmentMilli =
            Int64(minutes) * Int64(dice) * Int64(factor.numerator) * Int64(passiveTenths) * 10
            / Int64(factor.denominator)
        totalMilli += segmentMilli
        return segmentMilli
    }

    /// 整数成长点 G（XP；1 XP = 1000 milli）
    public var integerGrowth: Int64 { totalMilli / 1000 }

    /// 角色等级（规则 v1.1 修订：100 XP 升 1 级，替代 v1.0 的 1 XP = 1 级）
    public var level: Int64 { 1 + integerGrowth / 100 }

    /// 小数余量（千分之一），如 0.5 → 500，跨段保留
    public var remainderMilli: Int64 { totalMilli % 1000 }
}
