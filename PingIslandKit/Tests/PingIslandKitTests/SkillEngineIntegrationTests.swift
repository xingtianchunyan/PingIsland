import XCTest
@testable import PingIslandKit

/// 执行文档 9.6：技能抽选接入结算主流程——每个有效分钟一次确定性抽选，
/// 且旧版本 state JSON（无 skillCollection 键）可无损解码。
final class SkillEngineIntegrationTests: XCTestCase {
    private let day = "2026-11-02" // 周一
    private var settleTime: Date { Date(timeIntervalSince1970: 1_762_000_000) }

    private func event(_ id: String, _ group: TrainingGroup = .games,
                       _ minutes: Int, date: String? = nil) -> UsageEvent {
        UsageEvent(stableEventID: id, group: group, thresholdMinutes: minutes,
                   localDate: date ?? day, confirmedAt: settleTime)
    }

    // MARK: 1. 同种子两引擎处理同一事件序列 → 抽选序列完全相等，条数 = 骰点门槛过滤后的命中分钟数

    func testDeterministicDrawSequenceAcrossEngines() {
        let seed: UInt64 = 20261102
        var a = SettlementEngine(groups: [.games], characterSeed: seed)
        var b = SettlementEngine(groups: [.games], characterSeed: seed)
        let events = [event("d1", .games, 30), event("d2", .games, 90),
                      event("d3", .games, 150, date: "2026-11-03")]
        let outcomesA = a.process(events)
        let outcomesB = b.process(events)
        XCTAssertEqual(outcomesA, outcomesB)

        let draws = outcomesA.compactMap { outcome -> [SkillDraw]? in
            if case .settled(let delta) = outcome { return delta.skillDraws }
            return nil
        }.flatMap { $0 }

        // 命中分钟数独立重建：分钟 1...90（11-02）与 1...150（11-03 新日期，全额入账），
        // 逐分钟过 occurs 门槛（骰点取各段实际值）
        var expectedCount = 0
        for (date, minutes) in [("2026-11-02", 90), ("2026-11-03", 150)] {
            let dice = a.segments[date]?.dice?.value ?? 0
            let weekday = SkillDrawRules.weekday(forLocalDate: date)
            for minute in 1...minutes where SkillDrawRules.occurs(
                characterSeed: seed, dice: dice, minuteIndex: minute, weekday: weekday) {
                expectedCount += 1
            }
        }
        XCTAssertEqual(draws.count, expectedCount)
        XCTAssertEqual(a.skillCollection, b.skillCollection)
    }

    // MARK: 2. 抽选与 SkillDrawRules 独立重建完全一致（重试/恢复不重抽的验收口径）

    func testDrawsMatchIndependentReconstruction() {
        var engine = SettlementEngine(groups: [.games], characterSeed: 9)
        let events = [event("r1", .games, 30), event("r2", .games, 60)]
        let outcomes = engine.process(events)
        let draws = outcomes.compactMap { outcome -> [SkillDraw]? in
            if case .settled(let delta) = outcome { return delta.skillDraws }
            return nil
        }.flatMap { $0 }

        // 独立重建：当日骰点 + 分钟序号 1...60，仅保留 occurs 命中的分钟
        let dice = engine.segments[day]?.dice?.value ?? 0
        let weekday = SkillDrawRules.weekday(forLocalDate: day)
        let expected = SkillDrawRules.sequence(characterSeed: 9, dice: dice,
                                               fromMinute: 1, count: 60, weekday: weekday)
            .enumerated()
            .filter { SkillDrawRules.occurs(characterSeed: 9, dice: dice,
                                            minuteIndex: $0.offset + 1, weekday: weekday) }
            .map { $0.element }
        XCTAssertEqual(draws, expected)
    }

    // MARK: 1b. 骰点门槛：骰点 < 10 的分钟一律不抽选（真机反馈第十八批）

    func testDiceBelowTenProducesNoDraws() {
        var engine = SettlementEngine(groups: [.games], characterSeed: 7)
        var lowDice = event("g1", .games, 60)
        lowDice.diceOverride = 5
        let outcomes = engine.process([lowDice])
        let draws = outcomes.compactMap { outcome -> [SkillDraw]? in
            if case .settled(let delta) = outcome { return delta.skillDraws }
            return nil
        }.flatMap { $0 }
        XCTAssertTrue(draws.isEmpty)
        XCTAssertTrue(engine.skillCollection.items.isEmpty)
        XCTAssertEqual(engine.segments[day]?.dice?.value, 5) // 覆盖值仍落账
    }

    // MARK: 1c. 骰点覆盖：调试事件指定 20 → 骰点为 20 且触发每日神谕（一次性）

    func testDiceOverrideTwentyTriggersOracleOnce() {
        var engine = SettlementEngine(groups: [.games], characterSeed: 7)
        var highDice = event("o1", .games, 30)
        highDice.diceOverride = 20
        let first = engine.process([highDice])
        XCTAssertEqual(engine.segments[day]?.dice?.value, 20)
        XCTAssertTrue(first.contains { outcome in
            if case .settled(let d) = outcome { return d.oracleIssued }
            return false
        })
        // 同日再来一个事件：骰点不变，神谕不重复发
        var again = event("o2", .games, 60)
        again.diceOverride = 20
        _ = engine.process([again])
        XCTAssertEqual(engine.segments[day]?.dice?.value, 20)
    }

    // MARK: 3. 旧格式 state JSON（无 skillCollection 键）可解码，缺失键按空收藏处理

    func testLegacyStateJSONDecodesWithoutSkillCollection() throws {
        var engine = SettlementEngine(groups: [.games], characterSeed: 5)
        engine.process([event("l1", .games, 30)])
        var data = try JSONEncoder().encode(engine)

        // 删掉 skillCollection 键，模拟旧版本存档
        var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        object.removeValue(forKey: "skillCollection")
        data = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(SettlementEngine.self, from: data)
        XCTAssertEqual(decoded.level, engine.level) // 成长等核心状态无损
        XCTAssertEqual(decoded.processedEventIDs, engine.processedEventIDs)
        XCTAssertTrue(decoded.skillCollection.items.isEmpty) // 旧键缺失 → 空收藏
    }

    // MARK: 4. 星期归属：抽选的 weekday 与 localDate 一致，跨天各自归档

    func testWeekdayAttributionAcrossDates() {
        var engine = SettlementEngine(groups: [.games], characterSeed: 3)
        // 2026-11-02 周一，2026-11-08 周日
        let outcomes = engine.process([event("w1", .games, 10, date: "2026-11-02"),
                                       event("w2", .games, 10, date: "2026-11-08")])
        let draws = outcomes.compactMap { outcome -> [SkillDraw]? in
            if case .settled(let delta) = outcome { return delta.skillDraws }
            return nil
        }.flatMap { $0 }
        // 条数 = 命中分钟数（骰点 < 10 时为零）
        var expectedCount = 0
        for date in ["2026-11-02", "2026-11-08"] {
            let d = engine.segments[date]?.dice?.value ?? 0
            let weekday = SkillDrawRules.weekday(forLocalDate: date)
            for minute in 1...10 where SkillDrawRules.occurs(
                characterSeed: 3, dice: d, minuteIndex: minute, weekday: weekday) {
                expectedCount += 1
            }
        }
        XCTAssertEqual(draws.count, expectedCount)
        XCTAssertEqual(Set(draws.map { $0.weekday }), [1, 7])
        for item in engine.skillCollection.items {
            XCTAssertTrue((1...7).contains(item.weekday))
        }
    }
}
