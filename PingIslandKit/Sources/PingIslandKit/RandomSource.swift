/// 可注入的确定性随机源。
///
/// 所有规则抽奖只依赖此协议，测试用固定种子重建结果；
/// 生产环境每个稳定事件身份绑定一个种子，重试不重抽。
public protocol RandomSource {
    mutating func next() -> UInt64
}

/// 通用随机辅助（协议扩展，任何实现可用）
public extension RandomSource {
    /// 均匀整数 [0, upperBound)
    mutating func nextInt(upperBound: Int) -> Int {
        precondition(upperBound > 0)
        let bound = UInt64(upperBound)
        let threshold = (0 &- bound) % bound
        while true {
            let r = next()
            if r >= threshold { return Int(r % bound) }
        }
    }

    /// 均匀整数 [lowerBound, upperBound]（闭区间）
    mutating func nextInt(lowerBound: Int, upperBound: Int) -> Int {
        precondition(lowerBound <= upperBound)
        return lowerBound + nextInt(upperBound: upperBound - lowerBound + 1)
    }

    /// 按权重选择索引；跳过非正权重，权重和必须为正
    mutating func pickWeighted(_ weights: [Int]) -> Int {
        let total = weights.reduce(0, +)
        precondition(total > 0, "权重和必须为正")
        var roll = nextInt(upperBound: total)
        for (index, w) in weights.enumerated() {
            if w <= 0 { continue }
            if roll < w { return index }
            roll -= w
        }
        return weights.count - 1
    }
}

/// SplitMix64 伪随机数发生器：状态小、可确定重建、跨平台稳定
public struct SeededRandom: RandomSource, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        self.state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// 系统随机源（生产环境用；测试禁止用，保证 golden tests 确定性）
public struct SystemRandom: RandomSource {
    public init() {}
    public mutating func next() -> UInt64 {
        UInt64.random(in: .min ... .max)
    }
}
