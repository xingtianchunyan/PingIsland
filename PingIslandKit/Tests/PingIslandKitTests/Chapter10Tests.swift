import XCTest
@testable import PingIslandKit

/// 执行文档 14.1-14：职业满 7 日、60 分钟、并列、数据不足延长、其他组判流浪者
final class ClassAwakeningTests: XCTestCase {
    func testNotEnoughDaysExtends() {
        let r = ClassAwakening.judge(daysObserved: 6,
                                     inputs: [.init(group: .games, confirmedMinutes: 500)])
        XCTAssertEqual(r, .awakening)
    }

    func testNotEnoughMinutesExtends() {
        let r = ClassAwakening.judge(daysObserved: 7,
                                     inputs: [.init(group: .games, confirmedMinutes: 59)])
        XCTAssertEqual(r, .awakening)
    }

    func testClearTopGroupAwakens() {
        let r = ClassAwakening.judge(daysObserved: 7, inputs: [
            .init(group: .games, confirmedMinutes: 80),
            .init(group: .reading, confirmedMinutes: 30),
            .init(group: .social, confirmedMinutes: 20),
        ]) // total 130，games 61.5% vs reading 23.1%，差 >1pp
        XCTAssertEqual(r, .awakened(.gladiator))
    }

    func testTieWithinOnePercentIsRanger() {
        let r = ClassAwakening.judge(daysObserved: 8, inputs: [
            .init(group: .games, confirmedMinutes: 101),
            .init(group: .reading, confirmedMinutes: 100),
        ]) // total 201：50.25% vs 49.75%，差 0.5pp < 1pp
        XCTAssertEqual(r, .awakened(.ranger))
    }

    func testOtherGroupTopIsRanger() {
        let r = ClassAwakening.judge(daysObserved: 7, inputs: [
            .init(group: .other, confirmedMinutes: 120),
            .init(group: .games, confirmedMinutes: 30),
        ])
        XCTAssertEqual(r, .awakened(.ranger))
    }

    func testExactlySevenDaysSixtyMinutesAwakens() {
        let r = ClassAwakening.judge(daysObserved: 7,
                                     inputs: [.init(group: .health, confirmedMinutes: 60)])
        XCTAssertEqual(r, .awakened(.monk))
    }

    func testNoRetrospectiveAfterAwakened() {
        // 定型后调用方不再调用 judge；Outcome 只有 awakening/awakened，无重判路径
        let settled = ClassAwakening.judge(daysObserved: 9,
                                           inputs: [.init(group: .social, confirmedMinutes: 300)])
        guard case .awakened(let cls) = settled else { return XCTFail() }
        XCTAssertEqual(cls, .bard)
    }
}

/// 执行文档 14.1-15：疲劳只改变展示
final class FatigueTests: XCTestCase {
    func testBoundaries() {
        XCTAssertEqual(FatigueRules.stage(confirmedMinutesTotal: 0), .energetic)
        XCTAssertEqual(FatigueRules.stage(confirmedMinutesTotal: 119), .energetic)
        XCTAssertEqual(FatigueRules.stage(confirmedMinutesTotal: 120), .tired)
        XCTAssertEqual(FatigueRules.stage(confirmedMinutesTotal: 179), .tired)
        XCTAssertEqual(FatigueRules.stage(confirmedMinutesTotal: 180), .dozing)
        XCTAssertEqual(FatigueRules.stage(confirmedMinutesTotal: 239), .dozing)
        XCTAssertEqual(FatigueRules.stage(confirmedMinutesTotal: 240), .leaning)
        XCTAssertEqual(FatigueRules.stage(confirmedMinutesTotal: 359), .leaning)
        XCTAssertEqual(FatigueRules.stage(confirmedMinutesTotal: 360), .dormant)
        XCTAssertEqual(FatigueRules.stage(confirmedMinutesTotal: 2000), .dormant)
    }

    func testTextMapping() {
        XCTAssertEqual(FatigueRules.text(.energetic), "精神饱满")
        XCTAssertEqual(FatigueRules.text(.dormant), "休眠")
    }
}

/// 执行文档 14.1-13/9.7：遭遇概率、确定性、日记记录
final class EncounterTests: XCTestCase {
    func testMonsterRatioAroundThirtyPercent() {
        var rng = SeededRandom(seed: 20261102)
        var monsters = 0
        let n = 20_000
        for _ in 0..<n {
            if EncounterRules.resolve(rng: &rng).entryType != .dailyLife { monsters += 1 }
        }
        let ratio = Double(monsters) / Double(n)
        XCTAssertGreaterThan(ratio, 0.26)
        XCTAssertLessThan(ratio, 0.34)
    }

    func testWinLoseBothPossible() {
        var wins = 0, losses = 0
        for seed: UInt64 in 1...50 {
            var rng = SeededRandom(seed: seed)
            let r = EncounterRules.resolve(rng: &rng)
            if r.entryType == .monsterWin { wins += 1 }
            if r.entryType == .monsterLose { losses += 1 }
        }
        XCTAssertGreaterThan(wins, 0)
        XCTAssertGreaterThan(losses, 0)
    }

    func testDeterministicGolden() {
        var a = SeededRandom(seed: 777)
        var b = SeededRandom(seed: 777)
        for _ in 0..<100 {
            XCTAssertEqual(EncounterRules.resolve(rng: &a), EncounterRules.resolve(rng: &b))
        }
    }

    func testDiaryRecordUsesSettlementTime() {
        let settle = Date(timeIntervalSince1970: 1_762_000_000)
        var rng = SeededRandom(seed: 3)
        let r = EncounterRules.resolve(rng: &rng)
        let diary = EncounterRules.makeDiary(recordedAt: settle, group: .games,
                                             encounter: r, rewardSummary: "属性包 +2 CON")
        XCTAssertEqual(diary.recordedAt, settle)
        XCTAssertEqual(diary.group, .games)
        XCTAssertEqual(diary.rewardSummary, "属性包 +2 CON")
        XCTAssertTrue(diary.textKey.hasPrefix("encounter.") || diary.textKey.hasPrefix("dailylife."))
    }
}

/// 执行文档 14.1-16：时区、日期回退、显著跳变、新分段与旧事件不重复
final class SegmentKeeperTests: XCTestCase {
    func testNoJumpWithinTolerance() {
        var k = SegmentKeeper(localDate: "2026-11-02", timeZoneID: "Asia/Shanghai",
                              wallMillis: 1_000_000, monotonicMillis: 1_000_000)
        XCTAssertFalse(k.isSignificantJump(wallNowMillis: 1_000_000 + 4 * 60_000,
                                           monotonicNowMillis: 1_000_000 + 5 * 60_000,
                                           bootedMonotonicMillis: 900_000))
    }

    func testJumpBeyondFiveMinutes() {
        var k = SegmentKeeper(localDate: "2026-11-02", timeZoneID: "Asia/Shanghai",
                              wallMillis: 1_000_000, monotonicMillis: 1_000_000)
        XCTAssertTrue(k.isSignificantJump(wallNowMillis: 1_000_000 + 20 * 60_000,
                                          monotonicNowMillis: 1_000_000 + 60_000,
                                          bootedMonotonicMillis: 900_000))
    }

    func testManualTimeChangeBackwardAlsoDetectable() {
        var k = SegmentKeeper(localDate: "2026-11-02", timeZoneID: "Asia/Shanghai",
                              wallMillis: 1_000_000, monotonicMillis: 1_000_000)
        // 墙上时间被人为回拨 1 小时
        XCTAssertTrue(k.isSignificantJump(wallNowMillis: 1_000_000 - 60 * 60_000,
                                          monotonicNowMillis: 1_000_000 + 10_000,
                                          bootedMonotonicMillis: 900_000))
    }

    func testMonotonicRollbackMeansRebootNoComparison() {
        var k = SegmentKeeper(localDate: "2026-11-02", timeZoneID: "Asia/Shanghai",
                              wallMillis: 1_000_000, monotonicMillis: 1_000_000)
        XCTAssertFalse(k.isSignificantJump(wallNowMillis: 1_000_000 + 3600_000,
                                           monotonicNowMillis: 500_000, // 单调时钟回退＝重启过
                                           bootedMonotonicMillis: 400_000))
    }

    func testCloseAndOpenMonotonicIDs() {
        var k = SegmentKeeper(localDate: "2026-11-02", timeZoneID: "Asia/Shanghai",
                              wallMillis: 0, monotonicMillis: 0)
        let newID = k.closeAndOpen(newLocalDate: "2026-11-03", newTimeZoneID: "America/New_York",
                                   wallMillis: 86_400_000, monotonicMillis: 86_400_000)
        XCTAssertEqual(newID, 2)
        XCTAssertEqual(k.currentSegmentID, 2)
        XCTAssertEqual(k.closedSegments.count, 1)
        XCTAssertEqual(k.closedSegments.first?.localDate, "2026-11-02")
        XCTAssertEqual(k.timeZoneID, "America/New_York")
        // 再切一次继续单调递增
        let third = k.closeAndOpen(newLocalDate: "2026-11-04", newTimeZoneID: "Asia/Shanghai",
                                   wallMillis: 172_800_000, monotonicMillis: 172_800_000)
        XCTAssertEqual(third, 3)
    }
}
