import XCTest
@testable import PingIslandKit

/// 执行文档 8.3 验收示例：30 分钟、骰点 15、职业系数 1.1 → 成长 49.5；G=49、等级 50、余 0.5
final class GrowthTests: XCTestCase {
    func testAcceptanceExample() {
        var g = GrowthAccumulator()
        let segment = g.settle(minutes: 30, dice: 15, factor: .matched)
        XCTAssertEqual(segment, 49_500) // 49.5 成长值（千分之一定点）
        XCTAssertEqual(g.integerGrowth, 49)
        XCTAssertEqual(g.level, 50)
        XCTAssertEqual(g.remainderMilli, 500)
    }

    func testRemainderAccumulatesAcrossSegments() {
        var g = GrowthAccumulator()
        g.settle(minutes: 30, dice: 15, factor: .matched) // +49.5
        g.settle(minutes: 30, dice: 15, factor: .matched) // +49.5 → 99.0
        XCTAssertEqual(g.totalMilli, 99_000)
        XCTAssertEqual(g.integerGrowth, 99)
        XCTAssertEqual(g.level, 100)
        XCTAssertEqual(g.remainderMilli, 0)
    }

    func testNeutralFactorIsOne() {
        var g = GrowthAccumulator()
        g.settle(minutes: 30, dice: 10) // 30 × 1.0 = 30.0
        XCTAssertEqual(g.totalMilli, 30_000)
        XCTAssertEqual(g.level, 31)
    }

    func testRangerFactor103() {
        var g = GrowthAccumulator()
        g.settle(minutes: 100, dice: 10, factor: .ranger) // 100 × 1.03 = 103.0
        XCTAssertEqual(g.totalMilli, 103_000)
        XCTAssertEqual(g.integerGrowth, 103)
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
        g.settle(minutes: 100, dice: 10) // 恰好 100.0，不溢出到 101
        XCTAssertEqual(g.integerGrowth, 100)
        XCTAssertEqual(g.level, 101)
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
        // 30min × D≥10 → G≥30；智慧增量 = G（与成长点一致，不只给 1 点）
        XCTAssertEqual(engine.baseAttributes[.wis], initialWis + Int(engine.level - 1))
    }

    func testWisdomIncrementMatchesAcrossSegments() {
        var engine = SettlementEngine(groups: [.games], characterSeed: 7)
        let initialWis = engine.baseAttributes[.wis] ?? 0
        engine.process(UsageEvent(stableEventID: "w2", group: .games, thresholdMinutes: 30,
                                  localDate: "2026-11-02", confirmedAt: settleTime))
        let wisAfterFirst = engine.baseAttributes[.wis] ?? 0
        engine.process(UsageEvent(stableEventID: "w3", group: .games, thresholdMinutes: 60,
                                  localDate: "2026-11-02", confirmedAt: settleTime))
        // 不变式：任意时刻 WIS = 初始智慧 + G；第二段只补 G 的增量
        XCTAssertEqual(engine.baseAttributes[.wis], initialWis + Int(engine.level - 1))
        XCTAssertGreaterThan(engine.baseAttributes[.wis] ?? 0, wisAfterFirst)
    }
}
