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

/// 骰点 20 神谕：引擎发放奖励且日记明确记录大成功（真机反馈 9-4）
final class OracleDiaryTests: XCTestCase {
    private var settleTime: Date { Date(timeIntervalSince1970: 1_762_000_000) }

    /// 找到一个该种子下骰点为 20 的日期（确定性循环，不依赖运气）
    private func findDiceTwentyDate(seed: UInt64) -> String {
        var day = Date(timeIntervalSince1970: 1_762_000_000)
        let calendar = Calendar(identifier: .gregorian)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for _ in 0..<5000 {
            let dateString = formatter.string(from: day)
            var rng = SeededRandom(seed: fnv1a64("dice|\(dateString)") &+ seed)
            if DiceRules.roll(luckSnapshot: 1, rng: &rng).value == 20 { return dateString }
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        }
        XCTFail("5000 天内未找到骰点 20 的日期")
        return "2026-11-02"
    }

    func testDiceTwentyIssuesOracleAndWritesDiary() {
        let seed: UInt64 = 7
        let date = findDiceTwentyDate(seed: seed)
        var engine = SettlementEngine(groups: [.games], characterSeed: seed)
        let outcome = engine.process(UsageEvent(stableEventID: "oracle-1", group: .games,
                                              thresholdMinutes: 5, localDate: date,
                                              confirmedAt: settleTime))
        guard case .settled(let delta) = outcome else { return XCTFail("应结算成功") }
        XCTAssertTrue(delta.oracleIssued)
        // 日记必须有明确的大成功记录（文案 + 奖励数值）
        let oracleEntries = engine.diary.filter { $0.entryType == .oracleBoon }
        XCTAssertEqual(oracleEntries.count, 1)
        XCTAssertEqual(oracleEntries.first?.textKey, "oracle.boon")
        XCTAssertTrue(oracleEntries.first?.rewardSummary.contains("神谕奖励") ?? false)
        XCTAssertTrue(DiaryText.display("oracle.boon").contains("神谕降临"))
    }

    func testOracleOncePerDayOnly() {
        let seed: UInt64 = 7
        let date = findDiceTwentyDate(seed: seed)
        var engine = SettlementEngine(groups: [.games], characterSeed: seed)
        engine.process(UsageEvent(stableEventID: "o1", group: .games, thresholdMinutes: 5,
                                  localDate: date, confirmedAt: settleTime))
        let second = engine.process(UsageEvent(stableEventID: "o2", group: .games,
                                               thresholdMinutes: 10, localDate: date,
                                               confirmedAt: settleTime))
        guard case .settled(let delta) = second else { return XCTFail("应结算成功") }
        XCTAssertFalse(delta.oracleIssued) // 每日一次
        XCTAssertEqual(engine.diary.filter { $0.entryType == .oracleBoon }.count, 1)
    }
}
