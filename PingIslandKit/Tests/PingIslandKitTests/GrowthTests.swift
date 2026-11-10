import XCTest
@testable import PingIslandKit

/// 规则 v1.1 验收示例（行天修订，替代 v1.0「1 XP = 1 级」）：100 XP 升 1 级。
/// 30 分钟、骰点 15、职业系数 1.1 → 49.5 XP；G=49、等级 1（差 51 XP 升级）、余 0.5
final class GrowthTests: XCTestCase {
    func testAcceptanceExample() {
        var g = GrowthAccumulator()
        let segment = g.settle(minutes: 30, dice: 15, factor: .matched)
        XCTAssertEqual(segment, 49_500) // 49.5 XP（千分之一定点）
        XCTAssertEqual(g.integerGrowth, 49)
        XCTAssertEqual(g.level, 1) // v1.1：不足 100 XP 不升级
        XCTAssertEqual(g.remainderMilli, 500)
    }

    func testHundredXpPerLevel() {
        // v1.1 口径：骰点 10（100% 速率）下 100 分钟 = 100 XP = 正好升 1 级
        var g = GrowthAccumulator()
        g.settle(minutes: 100, dice: 10) // 100 × 1.0 = 100.0 XP
        XCTAssertEqual(g.integerGrowth, 100)
        XCTAssertEqual(g.level, 2)
    }

    func testRemainderAccumulatesAcrossSegments() {
        var g = GrowthAccumulator()
        g.settle(minutes: 30, dice: 15, factor: .matched) // +49.5
        g.settle(minutes: 30, dice: 15, factor: .matched) // +49.5 → 99.0
        XCTAssertEqual(g.totalMilli, 99_000)
        XCTAssertEqual(g.integerGrowth, 99)
        XCTAssertEqual(g.level, 1) // 99 < 100
        XCTAssertEqual(g.remainderMilli, 0)
    }

    func testNeutralFactorIsOne() {
        var g = GrowthAccumulator()
        g.settle(minutes: 30, dice: 10) // 30 × 1.0 = 30.0 XP
        XCTAssertEqual(g.totalMilli, 30_000)
        XCTAssertEqual(g.level, 1)
    }

    func testRangerFactor103() {
        var g = GrowthAccumulator()
        g.settle(minutes: 100, dice: 10, factor: .ranger) // 100 × 1.03 = 103.0 XP
        XCTAssertEqual(g.totalMilli, 103_000)
        XCTAssertEqual(g.integerGrowth, 103)
        XCTAssertEqual(g.level, 2) // 103 XP 跨过 100 阈值
    }

    func testPassiveExtensionSlotDefaultsToOne() {
        var g = GrowthAccumulator()
        let a = g.settle(minutes: 10, dice: 10, passiveTenths: 10)
        var h = GrowthAccumulator()
        let b = h.settle(minutes: 10, dice: 10)
        XCTAssertEqual(a, b)
    }

    func testIntegerBoundary() {
        var g = GrowthAccumulator()
        g.settle(minutes: 100, dice: 10) // 恰好 100.0 XP → 恰好 2 级，不溢出
        XCTAssertEqual(g.integerGrowth, 100)
        XCTAssertEqual(g.level, 2)
    }
}

/// 执行文档 8.3「基础智慧 = 初始智慧 + G」经 SettlementEngine 的接入验证
final class WisdomGrowthEngineTests: XCTestCase {
    private var settleTime: Date { Date(timeIntervalSince1970: 1_762_000_000) }

    func testWisdomGrowsWithGrowthPoints() {
        var engine = SettlementEngine(groups: [.games], characterSeed: 7)
        let initialWis = engine.baseAttributes[.wis] ?? 0
        engine.process(UsageEvent(stableEventID: "w1", group: .games, thresholdMinutes: 30,
                                  localDate: "2026-11-02", confirmedAt: settleTime))
        // 规则 v1.1：不足 100 XP 不升级 → 智慧不变；升级才 +1/级
        XCTAssertEqual(engine.level, 1)
        XCTAssertEqual(engine.baseAttributes[.wis], initialWis)
    }

    func testWisdomIncreasesExactlyOnePerLevel() {
        var engine = SettlementEngine(groups: [.games], characterSeed: 7)
        let initialWis = engine.baseAttributes[.wis] ?? 0
        // 第二十一批：经验只来自活动结算（30 XP/次，上限 5 次/组/天）。
        // 两天各 150 分钟（=5 次活动）：5×30×2 = 300 XP → 等级 4；
        // 骰点固定 10（只发基础属性 CON/INT/DEX，永不触 WIS）→ WIS 精确 = 初始 + 等级 − 1。
        var ev1 = UsageEvent(stableEventID: "wl1", group: .games, thresholdMinutes: 150,
                             localDate: "2026-11-02", confirmedAt: settleTime)
        ev1.diceOverride = 10
        var ev2 = UsageEvent(stableEventID: "wl2", group: .games, thresholdMinutes: 150,
                             localDate: "2026-11-03", confirmedAt: settleTime)
        ev2.diceOverride = 10
        engine.process(ev1)
        engine.process(ev2)
        XCTAssertEqual(engine.level, 4)
        XCTAssertEqual(engine.baseAttributes[.wis], initialWis + Int(engine.level) - 1)
    }

    func testWisdomIncrementMatchesAcrossSegments() {
        var engine = SettlementEngine(groups: [.games], characterSeed: 7)
        let initialWis = engine.baseAttributes[.wis] ?? 0
        engine.process(UsageEvent(stableEventID: "w2", group: .games, thresholdMinutes: 30,
                                  localDate: "2026-11-02", confirmedAt: settleTime))
        let wisAfterFirst = engine.baseAttributes[.wis] ?? 0
        engine.process(UsageEvent(stableEventID: "w3", group: .games, thresholdMinutes: 60,
                                  localDate: "2026-11-02", confirmedAt: settleTime))
        // 不变式（v1.1 + 第二十批 v3）：WIS = 初始 +（等级 − 1）+ 活动掉落的高级属性；
        // 里程碑可能直接加 WIS（LUK/WIS/CHA 池），故取 ≥，且不低于上次结算后
        XCTAssertGreaterThanOrEqual(engine.baseAttributes[.wis] ?? 0, initialWis + Int(engine.level - 1))
        XCTAssertGreaterThanOrEqual(engine.baseAttributes[.wis] ?? 0, wisAfterFirst)
    }
}
