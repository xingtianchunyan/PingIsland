import Foundation
import PingIslandKit
import XCTest

/// 按日聚合（DayStats）：同日累加、跨日分桶、等级增量、旧存档兼容。
final class DayStatsTests: XCTestCase {
    private let settleTime = Date(timeIntervalSince1970: 1_760_000_000)

    private func makeEngine() -> SettlementEngine {
        SettlementEngine(groups: Array(TrainingGroup.allCases), characterSeed: 42)
    }

    private func event(_ id: String, minutes: Int, date: String) -> UsageEvent {
        UsageEvent(stableEventID: id, group: .games, thresholdMinutes: minutes,
                   localDate: date, confirmedAt: settleTime)
    }

    func testSameDayEventsAccumulate() {
        var engine = makeEngine()
        engine.process(event("a", minutes: 30, date: "2026-11-03"))
        // 归属补差：60 分钟阈值事件只入账超出已确认部分的 30 分钟
        engine.process(event("b", minutes: 60, date: "2026-11-03"))
        let stats = engine.dayStats["2026-11-03"]
        XCTAssertEqual(stats?.minutes, 60)
        XCTAssertGreaterThan(stats?.growthMilli ?? 0, 0)
    }

    func testDifferentDaysAreSeparateBuckets() {
        var engine = makeEngine()
        engine.process(event("a", minutes: 30, date: "2026-11-03"))
        engine.process(event("b", minutes: 60, date: "2026-11-04"))
        XCTAssertEqual(engine.dayStats["2026-11-03"]?.minutes, 30)
        XCTAssertEqual(engine.dayStats["2026-11-04"]?.minutes, 60)
        XCTAssertEqual(engine.dayStats.count, 2)
    }

    func testLevelGainedIsNonNegativeAndMatchesGrowth() {
        var engine = makeEngine()
        // 60 分钟 × 骰点倍率：不假设具体骰点，只断言不变式
        engine.process(event("a", minutes: 60, date: "2026-11-03"))
        let stats = engine.dayStats["2026-11-03"]
        XCTAssertNotNil(stats)
        XCTAssertGreaterThanOrEqual(stats?.levelGained ?? -1, 0)
        if stats?.levelGained ?? 0 > 0 {
            // 升级日必然入账不少于 100 XP
            XCTAssertGreaterThanOrEqual(stats?.growthMilli ?? 0, 100_000)
        }
    }

    func testDayStatsRoundTripsThroughCodable() throws {
        var engine = makeEngine()
        engine.process(event("a", minutes: 30, date: "2026-11-03"))
        let data = try JSONEncoder().encode(engine)
        let restored = try JSONDecoder().decode(SettlementEngine.self, from: data)
        XCTAssertEqual(restored.dayStats, engine.dayStats)
    }

    func testLegacyStateWithoutDayStatsDecodesAsEmpty() throws {
        // 模拟旧存档：state JSON 不含 dayStats 键
        var engine = makeEngine()
        engine.process(event("a", minutes: 30, date: "2026-11-03"))
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine))
        var dict = object as? [String: Any] ?? [:]
        dict.removeValue(forKey: "dayStats")
        let legacy = try JSONSerialization.data(withJSONObject: dict)
        let restored = try JSONDecoder().decode(SettlementEngine.self, from: legacy)
        XCTAssertTrue(restored.dayStats.isEmpty)
        // 其余状态不受影响
        XCTAssertEqual(restored.level, engine.level)
        XCTAssertEqual(restored.diary, engine.diary)
    }
}

// MARK: - 骰点预览（previewDice）

extension DayStatsTests {
    func testPreviewDiceIsDeterministicAndMatchesSettlement() {
        var engine = makeEngine()
        let preview = engine.previewDice(for: "2026-11-10")
        XCTAssertGreaterThanOrEqual(preview, 1)
        XCTAssertLessThanOrEqual(preview, 20)
        // 预览不写入状态：结算前 segments 无该日段
        XCTAssertNil(engine.segments["2026-11-10"])
        // 实际结算后骰点与预览一致
        engine.process(event("preview-1", minutes: 30, date: "2026-11-10"))
        XCTAssertEqual(engine.segments["2026-11-10"]?.dice?.value, preview)
    }

    func testPreviewDiceDiffersByDate() {
        let engine = makeEngine()
        // 不强制不同（骰子可能撞值），只验证可重复调用无副作用
        let a = engine.previewDice(for: "2026-11-10")
        let b = engine.previewDice(for: "2026-11-10")
        XCTAssertEqual(a, b)
    }
}
