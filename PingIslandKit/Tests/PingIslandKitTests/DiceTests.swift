import XCTest
@testable import PingIslandKit

/// 执行文档 14.1-3：运气 0/300/900 的骰点范围，日内不重抽
final class DiceTests: XCTestCase {
    func testMinimumRoll() {
        XCTAssertEqual(DiceRules.minimumRoll(luckSnapshot: 0), 1)
        XCTAssertEqual(DiceRules.minimumRoll(luckSnapshot: 99), 1)
        XCTAssertEqual(DiceRules.minimumRoll(luckSnapshot: 100), 2)
        XCTAssertEqual(DiceRules.minimumRoll(luckSnapshot: 300), 4)
        XCTAssertEqual(DiceRules.minimumRoll(luckSnapshot: 899), 9)
        XCTAssertEqual(DiceRules.minimumRoll(luckSnapshot: 900), 10)
        XCTAssertEqual(DiceRules.minimumRoll(luckSnapshot: 5000), 10) // 封顶 10
    }

    func testRollRange() {
        for (luck, lo) in [(0, 1), (300, 4), (900, 10)] {
            var rng = SeededRandom(seed: 42)
            for _ in 0..<1000 {
                let d = DiceRules.roll(luckSnapshot: luck, rng: &rng)
                XCTAssertGreaterThanOrEqual(d.value, lo)
                XCTAssertLessThanOrEqual(d.value, 20)
            }
        }
    }

    func testLuck900IsD11Plus9() {
        var rng = SeededRandom(seed: 7)
        for _ in 0..<500 {
            let d = DiceRules.roll(luckSnapshot: 900, rng: &rng)
            XCTAssertGreaterThanOrEqual(d.value, 10)
        }
    }

    func testSameDayNoReroll() {
        var segment = GameDaySegment(segmentID: 1, localDate: "2026-11-02", timeZoneID: "Asia/Shanghai")
        var rng = SeededRandom(seed: 99)
        let first = segment.ensureDice(luckSnapshot: 0, rng: &rng)
        let second = segment.ensureDice(luckSnapshot: 0, rng: &rng)
        XCTAssertEqual(first, second) // 同日不重抽
        XCTAssertNotNil(segment.dice)
    }
}
