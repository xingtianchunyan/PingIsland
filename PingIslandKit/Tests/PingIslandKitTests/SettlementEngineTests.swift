import XCTest
@testable import PingIslandKit

/// 执行文档 Phase 1 门禁：幂等、乱序、批量与逐条一致、重试一致、恢复一致
final class SettlementEngineTests: XCTestCase {
    private let day = "2026-11-02"
    private var settleTime: Date { Date(timeIntervalSince1970: 1_762_000_000) }

    private func event(_ id: String, _ group: TrainingGroup = .games,
                       _ minutes: Int) -> UsageEvent {
        UsageEvent(stableEventID: id, group: group, thresholdMinutes: minutes,
                   localDate: day, confirmedAt: settleTime)
    }

    // MARK: 1. 验收：30/60/90 里程碑与每日探索上限（14.1-5）

    func testMilestones30_60_90() {
        var e = SettlementEngine(groups: [.games], characterSeed: 42)
        for (i, m) in [30, 60, 90].enumerated() {
            let outcome = e.process(event("ev-\(m)", .games, m))
            guard case .settled(let delta) = outcome else { return XCTFail("第\(i+1)个事件应结算") }
            XCTAssertEqual(delta.newMinutes, 30) // 每个事件只补 30 分钟差额
            XCTAssertEqual(delta.explorations.count, 1) // 每满 30 分钟一次探索
        }
        XCTAssertEqual(e.diary.count, 3)
        XCTAssertEqual(e.growth.totalMilli,
                       Int64(e.segments[day]!.dice!.value) * 9 * 1000) // 系数 1：总分钟 × D/10
    }

    // MARK: 2. 重复事件不重复发奖（14.1-6）

    func testDuplicateEventIgnored() {
        var e = SettlementEngine(groups: [.games], characterSeed: 42)
        _ = e.process(event("dup-1", .games, 30))
        let before = e
        let outcome = e.process(event("dup-1", .games, 30))
        XCTAssertEqual(outcome, .duplicate)
        XCTAssertEqual(e, before) // 状态完全不变
        XCTAssertEqual(e.growth.totalMilli, before.growth.totalMilli)
    }

    // MARK: 3. 乱序：低阈值晚于高阈值不倒退（14.1-6）

    func testOutOfOrderNoRegression() {
        var a = SettlementEngine(groups: [.games], characterSeed: 7)
        _ = a.process(event("o-90", .games, 90))
        let outcome = a.process(event("o-30", .games, 30)) // 迟到
        guard case .settled(let delta) = outcome else { return XCTFail() }
        XCTAssertEqual(delta.newMinutes, 0) // 已入账 90，不重复补
        XCTAssertEqual(a.growth.totalMilli, Int64(a.segments[day]!.dice!.value) * 9 * 1000)
    }

    // MARK: 4. 批量 = 逐条（14.1-7）

    func testBatchEqualsSequential() {
        let events = [30, 60, 90, 120, 150].map { event("b-\($0)", .games, $0) }
        var one = SettlementEngine(groups: [.games, .reading], characterSeed: 9)
        for ev in events { _ = one.process(ev) }
        var batch = SettlementEngine(groups: [.games, .reading], characterSeed: 9)
        _ = batch.process(events)
        XCTAssertEqual(one, batch)
    }

    // MARK: 5. 重试：整序列重放全部判重，状态一致（14.1-7）

    func testRetryWholeSequenceIsIdempotent() {
        let events = [30, 60, 90].map { event("r-\($0)", .games, $0) }
        var e = SettlementEngine(groups: [.games], characterSeed: 5)
        _ = e.process(events)
        let snapshot = e
        let outcomes = e.process(events) // 重放
        XCTAssertTrue(outcomes.allSatisfy { $0 == .duplicate })
        XCTAssertEqual(e, snapshot)
    }

    // MARK: 6. 每日探索上限 5 次（14.1-5）

    func testExplorationCapFivePerGroupPerDay() {
        var e = SettlementEngine(groups: [.games], characterSeed: 11)
        _ = e.process(event("cap-180", .games, 180)) // 6 个里程碑，但上限 5
        guard case .settled(let delta) = e.process(event("cap-210", .games, 210)) else { return XCTFail() }
        // 180 时已做 5 次探索（上限）；210 不再探索
        var e2 = SettlementEngine(groups: [.games], characterSeed: 11)
        let o1 = e2.process(event("cap-180", .games, 180))
        guard case .settled(let d1) = o1 else { return XCTFail() }
        XCTAssertEqual(d1.explorations.count, 5)
        XCTAssertEqual(delta.explorations.count, 0)
    }

    // MARK: 7. 跨日：新分段重建骰子与次数（14.1-3/5）

    func testNewDayNewDiceAndCounters() {
        var e = SettlementEngine(groups: [.games], characterSeed: 3)
        _ = e.process(event("d1-30", .games, 30))
        let day2 = "2026-11-03"
        let ev2 = UsageEvent(stableEventID: "d2-30", group: .games, thresholdMinutes: 30,
                             localDate: day2, confirmedAt: settleTime)
        let outcome = e.process(ev2)
        guard case .settled(let delta) = outcome else { return XCTFail() }
        XCTAssertEqual(delta.explorations.count, 1) // 新一天重新计数
        XCTAssertNotNil(e.segments[day2]?.dice)
        XCTAssertEqual(e.segments.count, 2)
    }

    // MARK: 8. 装备自动择优与收藏（14.1-10）

    func testEquipmentAutoEquipKeepsCollection() {
        var e = SettlementEngine(groups: [.games], characterSeed: 13)
        // 多天多次探索，确保必然出现装备发现
        for (i, m) in [30, 60, 90, 120, 150].enumerated() {
            _ = e.process(event("eq-\(m)-\(i)", .games, m))
        }
        XCTAssertFalse(e.equipment.isEmpty)
        for item in e.equipment {
            if item.isEquipped {
                XCTAssertEqual(e.equipped[item.slot]?.id, item.id)
            }
        }
    }

    // MARK: 9. 满 7 天 + 60 分钟后觉醒，觉醒后职业系数生效（14.1-14）

    func testAwakeningAfterSevenDays() {
        var e = SettlementEngine(groups: [.games, .reading], characterSeed: 21)
        var changed: CharacterClass?
        for d in 1...7 {
            let date = String(format: "2026-11-%02d", d + 1)
            let ev = UsageEvent(stableEventID: "aw-\(d)", group: .games,
                                thresholdMinutes: 30, localDate: date,
                                confirmedAt: settleTime)
            if case .settled(let delta) = e.process(ev), let cls = delta.classChanged {
                changed = cls
            }
        }
        XCTAssertEqual(changed, .gladiator)
        XCTAssertEqual(e.classState, .gladiator)
        // 觉醒后下一段成长使用职业系数 1.10
        let before = e.growth.totalMilli
        let ev = UsageEvent(stableEventID: "aw-after", group: .games, thresholdMinutes: 30,
                            localDate: "2026-11-09", confirmedAt: settleTime)
        guard case .settled(let delta) = e.process(ev) else { return XCTFail() }
        XCTAssertEqual(delta.growthMilliApplied,
                       Int64(delta.newMinutes) * Int64(e.segments["2026-11-09"]!.dice!.value) * 110 * 10 * 10 / 100)
        XCTAssertGreaterThan(e.growth.totalMilli, before)
    }

    // MARK: 10. golden：固定输入确定性（14.1-7）

    func testGoldenDeterminismAcrossEngines() {
        let events = [30, 60, 90, 120].map { event("g-\($0)", .games, $0) }
        var a = SettlementEngine(groups: [.games], characterSeed: 99)
        var b = SettlementEngine(groups: [.games], characterSeed: 99)
        _ = a.process(events)
        _ = b.process(events)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.finalAttributes(), b.finalAttributes())
    }
}
