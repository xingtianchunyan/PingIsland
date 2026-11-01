import XCTest
@testable import PingIsland

/// 桌面卡片展示口径（执行文档 11.2）：6 小时未确认 → 休眠/等待同步。
final class WidgetPolicyTests: XCTestCase {
    func testFreshSnapshotShowsRecentEvent() {
        let recent = DisplaySnapshot(recentEvent: "晨练吐纳",
                                     lastSettlementAt: Date().addingTimeInterval(-3600))
        XCTAssertFalse(recent.isStale)
        XCTAssertEqual(recent.widgetStatusText, "晨练吐纳")
    }

    func testSevenHoursOldSnapshotIsStale() {
        let old = DisplaySnapshot(recentEvent: "晨练吐纳",
                                  lastSettlementAt: Date().addingTimeInterval(-7 * 3600))
        XCTAssertTrue(old.isStale)
        XCTAssertEqual(old.widgetStatusText, "休眠 · 等待同步")
    }

    func testNeverSettledSnapshotIsStale() {
        let fresh = DisplaySnapshot() // lastSettlementAt = nil
        XCTAssertTrue(fresh.isStale)
        XCTAssertEqual(fresh.widgetStatusText, "休眠 · 等待同步")
    }

    func testSixHoursMinusOneMinuteIsFresh() {
        let edge = DisplaySnapshot(lastSettlementAt: Date().addingTimeInterval(-(6 * 3600 - 60)))
        XCTAssertFalse(edge.isStale)
    }

    func testOldSnapshotJSONWithoutNewFieldsStillDecodes() throws {
        // 旧版本快照（无 displayPriority/bannerText）必须可解码：新字段为可选
        let oldJSON = """
        {"level":3,"className":"武僧","fatigueStage":1,"recentEvent":"晨练吐纳",\
        "lastSettlementAt":1760000000,"snapshotVersion":2}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(DisplaySnapshot.self, from: oldJSON)
        XCTAssertEqual(decoded.level, 3)
        XCTAssertNil(decoded.displayPriority)
        XCTAssertNil(decoded.bannerText)
    }

    func testBannerOverridesStatusText() {
        let s = DisplaySnapshot(recentEvent: "晨练吐纳",
                                lastSettlementAt: Date().addingTimeInterval(-3600),
                                bannerText: "职业觉醒：武僧")
        XCTAssertEqual(s.widgetStatusText, "职业觉醒：武僧")
    }

    func testAttributeSummary() {
        let withAttrs = DisplaySnapshot(attributes: ["CON": 3, "INT": 2, "CHA": 1, "DEX": 2])
        XCTAssertEqual(withAttrs.attributeSummary, "CON 3 · INT 2 · DEX 2 · CHA 1")
        XCTAssertNil(DisplaySnapshot().attributeSummary)
        XCTAssertNil(DisplaySnapshot(attributes: [:]).attributeSummary)
    }
}
