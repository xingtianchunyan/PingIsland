import XCTest
@testable import PingIslandKit

/// 展示优先级（执行文档 11.4）：异常休眠 > 夜间 > 里程碑 > 遭遇 > 日常。
final class PresentationPolicyTests: XCTestCase {
    private func calendar(_ hour: Int) -> (Date, Calendar) {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        // 2026-11-02 指定小时
        let date = c.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: hour, minute: 0))!
        return (date, c)
    }

    func testAnomalySleepWinsOverEverything() {
        let input = PresentationInput(latestDelta: .zero, hasAnomalySleep: true, isNight: false)
        XCTAssertEqual(PresentationPolicy.resolve(input), .confirmedAnomalySleep)
    }

    func testNightWinsOverMilestone() {
        let input = PresentationInput(latestDelta: .zero, hasAnomalySleep: false, isNight: true)
        XCTAssertEqual(PresentationPolicy.resolve(input), .nightRest)
    }

    func testOracleIsMilestone() {
        var d = SettlementDelta.zero
        d.oracleIssued = true
        XCTAssertEqual(PresentationPolicy.resolve(PresentationInput(latestDelta: d)), .milestone)
    }

    func testClassChangeIsMilestone() {
        var d = SettlementDelta.zero
        d.classChanged = .bard
        XCTAssertEqual(PresentationPolicy.resolve(PresentationInput(latestDelta: d)), .milestone)
    }

    func testMilestoneGrantIsMilestone() {
        var d = SettlementDelta.zero
        d.milestoneGrants = [MilestoneGrant(experienceXP: 10, attributePoints: [:],
                                            mainEquipment: nil, mainSkill: nil,
                                            extraEquipment: nil)]
        XCTAssertEqual(PresentationPolicy.resolve(PresentationInput(latestDelta: d)), .milestone)
    }

    func testMonsterEncounterBeatsDailyLife() {
        var d = SettlementDelta.zero
        d.diaries = [DiaryRecord(recordedAt: Date(), group: .games,
                                 entryType: .monsterLose, textKey: "败给史莱姆", rewardSummary: "")]
        XCTAssertEqual(PresentationPolicy.resolve(PresentationInput(latestDelta: d)), .recentEncounter)
    }

    func testDailyLifeIsDefault() {
        XCTAssertEqual(PresentationPolicy.resolve(PresentationInput()), .dailyLife)
        let life: SettlementDelta = .zero
        XCTAssertEqual(PresentationPolicy.resolve(PresentationInput(latestDelta: life)), .dailyLife)
    }

    func testNightHours() {
        for hour in [23, 0, 3, 6] {
            let (date, cal) = calendar(hour)
            XCTAssertTrue(PresentationPolicy.isNight(date, calendar: cal), "hour \(hour) should be night")
        }
        for hour in [7, 12, 19, 22] {
            let (date, cal) = calendar(hour)
            XCTAssertFalse(PresentationPolicy.isNight(date, calendar: cal), "hour \(hour) should be day")
        }
    }

    func testBannerTexts() {
        XCTAssertNotNil(PresentationPolicy.banner(for: .confirmedAnomalySleep, input: PresentationInput()))
        XCTAssertNotNil(PresentationPolicy.banner(for: .nightRest, input: PresentationInput()))
        XCTAssertNil(PresentationPolicy.banner(for: .dailyLife, input: PresentationInput()))
        var d = SettlementDelta.zero
        d.classChanged = .monk
        XCTAssertEqual(PresentationPolicy.banner(for: .milestone, input: PresentationInput(latestDelta: d)),
                       "职业觉醒：武僧")
    }
}
