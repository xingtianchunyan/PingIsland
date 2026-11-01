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
}
