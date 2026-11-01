import PingIslandKit
import XCTest
@testable import PingIsland

/// 待结算队列与结算协调（执行文档 14.2：主 App 与扩展同一入口，不重复发奖）
final class SettlementFlowTests: XCTestCase {
    private var settleTime: Date { Date(timeIntervalSince1970: 1_762_000_000) }

    override func setUp() {
        SharedStore.defaults?.removeObject(forKey: "pendingEvents.v1")
        SharedStore.defaults?.removeObject(forKey: SharedStore.Keys.snapshot)
    }

    func testQueueDrainConsumesOnce() {
        let events = (1...3).map {
            UsageEvent(stableEventID: "q-\($0)", group: .games, thresholdMinutes: $0 * 30,
                       localDate: "2026-11-02", confirmedAt: settleTime)
        }
        PendingEventQueue.enqueue(events)
        XCTAssertEqual(PendingEventQueue.count, 3)
        let drained = PendingEventQueue.drain()
        XCTAssertEqual(drained.count, 3)
        XCTAssertEqual(PendingEventQueue.count, 0) // 消费语义：再次读取为空
        XCTAssertEqual(PendingEventQueue.drain(), [])
    }

    func testCoordinatorSettlesQueuedEvents() {
        PendingEventQueue.enqueue([
            UsageEvent(stableEventID: "c-30", group: .games, thresholdMinutes: 30,
                       localDate: "2026-11-02", confirmedAt: settleTime),
            UsageEvent(stableEventID: "c-60", group: .games, thresholdMinutes: 60,
                       localDate: "2026-11-02", confirmedAt: settleTime),
        ])
        let settled = SettlementCoordinator.settlePending()
        XCTAssertEqual(settled, 2)
        XCTAssertEqual(PendingEventQueue.count, 0)
        // 展示快照已刷新（只读，无领取操作）
        let snapshot = SnapshotIO.load()
        XCTAssertNotNil(snapshot)
        XCTAssertGreaterThanOrEqual(snapshot!.level, 1)
        XCTAssertNotNil(snapshot!.lastSettlementAt)
        // 再次结算：队列已空，0 新结算，且不重复发奖
        XCTAssertEqual(SettlementCoordinator.settlePending(), 0)
        let after = SnapshotIO.load()
        XCTAssertEqual(after?.snapshotVersion, snapshot?.snapshotVersion)
    }

    func testDuplicateQueuedEventsNotDoubleCounted() {
        // 扩展重试可能重复入队同一事件身份
        let ev = UsageEvent(stableEventID: "dup-30", group: .games, thresholdMinutes: 30,
                            localDate: "2026-11-02", confirmedAt: settleTime)
        PendingEventQueue.enqueue([ev, ev])
        XCTAssertEqual(SettlementCoordinator.settlePending(), 1)
    }
}
