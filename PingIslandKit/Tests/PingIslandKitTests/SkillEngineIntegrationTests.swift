import XCTest
@testable import PingIslandKit

/// 真机反馈第十九批规则 v2：技能/装备仅由半小时活动结算产出（MilestoneRules），
/// 每分钟只积累固定 1 XP；神谕在换日（startDay）时发放，不占活动结算次数。
final class SkillEngineIntegrationTests: XCTestCase {
    private let day = "2026-11-02" // 周一
    private var settleTime: Date { Date(timeIntervalSince1970: 1_762_000_000) }

    private func event(_ id: String, _ group: TrainingGroup = .games,
                       _ minutes: Int, date: String? = nil,
                       diceOverride: Int? = nil) -> UsageEvent {
        UsageEvent(stableEventID: id, group: group, thresholdMinutes: minutes,
                   localDate: date ?? day, confirmedAt: settleTime,
                   diceOverride: diceOverride)
    }

    // MARK: 1. 每分钟不再产出技能：骰 5 注入 120 分钟 → 技能收藏为空

    func testPerMinuteGrantsNoSkills() {
        var engine = SettlementEngine(groups: [.games], characterSeed: 7)
        _ = engine.process([event("p1", .games, 30, diceOverride: 5),
                            event("p2", .games, 120, diceOverride: 5)])
        XCTAssertTrue(engine.skillCollection.items.isEmpty)
    }

    // MARK: 2. 骰 5 的半小时活动只有白/绿装备，没有特质/技能

    func testLowDiceMilestoneGrantsOnlyWhiteOrGreenEquipment() {
        var engine = SettlementEngine(groups: [.games], characterSeed: 7)
        for m in [30, 60, 90, 120, 150] {
            _ = engine.process(event("l\(m)", .games, m, diceOverride: 5))
        }
        for item in engine.equipment {
            XCTAssertTrue(item.rarity == .white || item.rarity == .green,
                          "骰 5 不应产出蓝及以上装备，实际 \(item.rarity)")
        }
        XCTAssertTrue(engine.skillCollection.items.isEmpty)
    }

    // MARK: 3. 骰 20：每次活动 = 主结果（装备或技能）+ 必得一件高级装备，且入收藏

    func testDiceTwentyMilestoneGrantsMainPlusExtra() {
        var engine = SettlementEngine(groups: [.games], characterSeed: 11)
        var outcomes: [SettlementOutcome] = []
        for m in [30, 60, 90] {
            outcomes.append(engine.process(event("t\(m)", .games, m, diceOverride: 20)))
        }
        let grants = outcomes.compactMap { outcome -> [MilestoneGrant]? in
            if case .settled(let delta) = outcome { return delta.milestoneGrants }
            return nil
        }.flatMap { $0 }
        XCTAssertEqual(grants.count, 3)
        for grant in grants {
            XCTAssertEqual(grant.experienceXP, 60) // 3 × 20
            XCTAssertNotNil(grant.extraEquipment, "骰 20 每次活动必得一件额外装备")
            // 规则 v3 主结果三选一（属性/装备/技能），与必得额外装备合计恰为 2 项产出
            let mainCount = (grant.mainEquipment == nil ? 0 : 1)
                + (grant.mainSkill == nil ? 0 : 1)
                + (grant.attributePoints.isEmpty ? 0 : 1)
            XCTAssertEqual(mainCount, 1)
            XCTAssertEqual(grant.allEquipment.count, (grant.mainEquipment == nil ? 0 : 1) + 1)
            for item in grant.allEquipment {
                XCTAssertTrue([.purple, .orange, .red].contains(item.rarity))
            }
            if let skill = grant.mainSkill {
                XCTAssertTrue([.purple, .orange, .red].contains(skill.rarity))
            }
        }
        // 装备/技能都进了收藏账本
        XCTAssertFalse(engine.equipment.isEmpty)
    }

    // MARK: 4. 神谕：换日（startDay）即触发，每日一次，不占活动结算

    func testOracleIssuesOnDayStartOnly() {
        var engine = SettlementEngine(groups: [.games], characterSeed: 3)
        // 指定骰 20 后直接开始新的一天 → 神谕发放
        _ = engine.process(event("seed-day", .games, 30, diceOverride: 20))
        let diaryBefore = engine.diary.count
        let issued = engine.startDay("2026-11-03")
        XCTAssertTrue(issued)
        XCTAssertEqual(engine.diary.count, diaryBefore + 1)
        XCTAssertEqual(engine.diary.last?.textKey, "oracle.boon")
        // 同日再次 startDay：不重复发放
        XCTAssertFalse(engine.startDay("2026-11-03"))
        XCTAssertEqual(engine.diary.count, diaryBefore + 1)
    }

    // MARK: 5. 骰 20 当日：首次活动 = 神谕 1 + 主结果 1 + 额外装备 1，共 3 条；之后每次活动 +2 条

    func testDiceTwentyDayRecordCounts() {
        var engine = SettlementEngine(groups: [.games], characterSeed: 3)
        _ = engine.process(event("d20-first", .games, 30, diceOverride: 20))
        XCTAssertEqual(engine.diary.filter { $0.entryType == .oracleBoon }.count, 1)
        XCTAssertEqual(engine.diary.filter { $0.entryType == .milestone }.count, 2)
        _ = engine.process(event("d20-second", .games, 60, diceOverride: 20))
        XCTAssertEqual(engine.diary.filter { $0.entryType == .milestone }.count, 4)
        // 神谕始终只有 1 条
        XCTAssertEqual(engine.diary.filter { $0.entryType == .oracleBoon }.count, 1)
    }

    // MARK: 6. 同种子两引擎处理同一事件序列 → 结果完全相等（确定性保持）

    func testDeterministicAcrossEngines() {
        let seed: UInt64 = 20261106
        var a = SettlementEngine(groups: [.games], characterSeed: seed)
        var b = SettlementEngine(groups: [.games], characterSeed: seed)
        let events = [event("a1", .games, 30, diceOverride: 15),
                      event("a2", .games, 90, diceOverride: 15),
                      event("a3", .games, 60, date: "2026-11-03", diceOverride: 12)]
        let outcomesA = a.process(events)
        let outcomesB = b.process(events)
        XCTAssertEqual(outcomesA, outcomesB)
        XCTAssertEqual(a.skillCollection, b.skillCollection)
        XCTAssertEqual(a.equipment, b.equipment)
    }

    // MARK: 7. 旧格式 state JSON（无 skillCollection 键）可解码

    func testLegacyStateJSONDecodesWithoutSkillCollection() throws {
        var engine = SettlementEngine(groups: [.games], characterSeed: 5)
        engine.process([event("lg1", .games, 30, diceOverride: 10)])
        var data = try JSONEncoder().encode(engine)

        var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        object.removeValue(forKey: "skillCollection")
        data = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(SettlementEngine.self, from: data)
        XCTAssertEqual(decoded.level, engine.level)
        XCTAssertEqual(decoded.processedEventIDs, engine.processedEventIDs)
        XCTAssertTrue(decoded.skillCollection.items.isEmpty)
    }
}
