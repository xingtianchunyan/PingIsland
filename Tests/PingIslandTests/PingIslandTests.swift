import XCTest
@testable import PingIsland

/// 共享快照读写与初始状态（执行文档 14.2/14.3）
final class PingIslandTests: XCTestCase {
    func testSnapshotRoundTrip() {
        let snapshot = DisplaySnapshot(level: 3, className: "武僧",
                                       fatigueStage: 1, recentEvent: "晨练吐纳",
                                       lastSettlementAt: Date(timeIntervalSince1970: 1_760_000_000),
                                       snapshotVersion: 2)
        SnapshotIO.save(snapshot)
        let loaded = SnapshotIO.load()
        XCTAssertEqual(loaded, snapshot)
    }

    func testSnapshotRoundTripWithAttributesAndEquipment() {
        let snapshot = DisplaySnapshot(
            level: 5, className: "武僧", fatigueStage: 1, recentEvent: "晨练",
            lastSettlementAt: Date(timeIntervalSince1970: 1_760_000_000),
            snapshotVersion: 3, displayPriority: 2, bannerText: "神谕赐予属性",
            attributes: ["CON": 3, "INT": 2, "DEX": 2, "LUK": 1, "WIS": 1, "CHA": 1],
            equipment: ["头部 · 蓝装 · 评 4", "足部 · 绿装 · 评 3"],
            recentDiaries: ["11-02 08:00 · 晨练吐纳 · CON+1"],
            collection: ["蓝装 · 头部 · 评 4 · 装备中", "绿装 · 足部 · 评 3"])
        SnapshotIO.save(snapshot)
        XCTAssertEqual(SnapshotIO.load(), snapshot)
    }

    func testFreshSnapshotDefaults() {
        let fresh = DisplaySnapshot()
        XCTAssertEqual(fresh.level, 1)
        XCTAssertEqual(fresh.className, "觉醒中")
        XCTAssertEqual(fresh.snapshotVersion, 1)
    }

    func testFatigueTextMapping() {
        XCTAssertEqual(DisplaySnapshot(fatigueStage: 0).fatigueText, "精神饱满")
        XCTAssertEqual(DisplaySnapshot(fatigueStage: 4).fatigueText, "休眠")
    }
}
