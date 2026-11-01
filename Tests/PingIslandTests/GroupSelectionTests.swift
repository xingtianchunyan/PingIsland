import XCTest
@testable import PingIsland

/// 八修行组选择（执行文档 5.2 / 14.3）：固定顺序、持久化结构、跨组 token 查重。
/// 真实 ApplicationToken 无法脱离系统选择器构造，查重算法用泛型 deduplicate 覆盖。
final class GroupSelectionTests: XCTestCase {
    func testOrderedGroupsMatchesDocumentOrder() {
        XCTAssertEqual(GroupSelection.orderedGroups, [
            .social, .productivity, .games, .reading,
            .entertainment, .shopping, .health, .other,
        ])
        XCTAssertEqual(GroupSelection.orderedGroups.count, 8)
    }

    func testDeduplicateRemovesTokensTakenByOtherGroups() {
        let taken: Set<String> = ["app.a", "app.b"]
        let incoming: Set<String> = ["app.a", "app.c"]
        let result = GroupSelection.deduplicate(incoming, excluding: [taken])
        XCTAssertEqual(result, ["app.c"])
    }

    func testDeduplicateUnionAcrossGroups() {
        // 同一 token 被多个组占用：仍然只留先占者语义（全部减掉）
        let r = GroupSelection.deduplicate(["x", "y", "z"], excluding: [["x"], ["y"]])
        XCTAssertEqual(r, ["z"])
    }

    func testDeduplicateEmptyIncoming() {
        XCTAssertEqual(GroupSelection.deduplicate([], excluding: [["a"]]), [])
    }

    func testStateCodableRoundTrip() {
        var state = GroupSelection.State()
        state.version = 7
        let data = try! JSONEncoder().encode(state)
        let decoded = try! JSONDecoder().decode(GroupSelection.State.self, from: data)
        XCTAssertEqual(decoded, state)
        XCTAssertEqual(decoded.selection(for: .games).applicationTokens.isEmpty, true)
    }

    func testFreshStateHasVersionOneAndEmptySelections() {
        let state = GroupSelection.State()
        XCTAssertEqual(state.version, 1)
        XCTAssertTrue(state.selections.isEmpty)
        XCTAssertTrue(state.nonEmptyGroups.isEmpty)
    }
}
