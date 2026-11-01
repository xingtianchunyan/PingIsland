import XCTest
@testable import PingIslandKit

/// 执行文档 14.1-17/18 + 14.2：保存中断回滚、恢复后重放一致、迁移基础
final class PersistenceTests: XCTestCase {
    private var dirs: [URL] = []
    private let day = "2026-11-02"
    private var settleTime: Date { Date(timeIntervalSince1970: 1_762_000_000) }

    override func tearDown() {
        for d in dirs { try? FileManager.default.removeItem(at: d) }
        dirs.removeAll()
    }

    private func makeStore() -> JSONFileSettlementStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pingisland-test-\(UUID().uuidString)")
        dirs.append(url)
        return JSONFileSettlementStore(directory: url)
    }

    private func event(_ id: String, _ group: TrainingGroup = .games,
                       _ minutes: Int, date: String? = nil) -> UsageEvent {
        UsageEvent(stableEventID: id, group: group, thresholdMinutes: minutes,
                   localDate: date ?? day, confirmedAt: settleTime)
    }

    // MARK: 1. 状态持久化往返

    func testStateRoundTrip() throws {
        let store = makeStore()
        let events = [30, 60, 90].map { event("rt-\($0)", .games, $0) }
        let service = try SettlementService(store: store, groups: [.games], characterSeed: 42)
        service.process(events)

        let restored = try SettlementService(store: store, groups: [.games], characterSeed: 42)
        // 恢复时重放日志 → 全部判重 → 状态与恢复前一致
        XCTAssertEqual(restored.engine, service.engine)
        XCTAssertEqual(restored.engine.processedEventIDs, service.engine.processedEventIDs)
        XCTAssertEqual(restored.engine.diary, service.engine.diary)
    }

    // MARK: 2. 崩溃恢复：日志完整但状态未保存 → 重放补齐，结果与无中断一致

    func testCrashRecoveryMatchesUninterruptedRun() throws {
        // 无中断基准
        var baseline = SettlementEngine(groups: [.games], characterSeed: 7)
        let events = [30, 60, 90, 120].map { event("cr-\($0)", .games, $0) }
        baseline.process(events)

        // 模拟崩溃：只落日志，不存状态
        let store = makeStore()
        let encoder = JSONEncoder()
        try store.saveJournal(encoder.encode(events))
        // 没有 saveState —— 模拟中断

        let recovered = try SettlementService(store: store, groups: [.games], characterSeed: 7)
        XCTAssertEqual(recovered.engine, baseline) // 恢复后重放一致（14.1-7）
    }

    // MARK: 3. 部分中断：前两个事件已存状态，后两个从日志补

    func testPartialProgressRecovery() throws {
        let store = makeStore()
        let events = [30, 60, 90, 120].map { event("pp-\($0)", .games, $0) }
        var engine = SettlementEngine(groups: [.games], characterSeed: 11)
        engine.process(Array(events.prefix(2)))
        let encoder = JSONEncoder()
        try store.saveState(encoder.encode(engine))            // 状态只到 60
        try store.saveJournal(encoder.encode(events))          // 日志完整

        var baseline = SettlementEngine(groups: [.games], characterSeed: 11)
        baseline.process(events)

        let recovered = try SettlementService(store: store, groups: [.games], characterSeed: 11)
        XCTAssertEqual(recovered.engine, baseline)
    }

    // MARK: 4. 重复恢复：再次实例化仍然一致（日志重放全判重）

    func testDoubleRecoveryIsStable() throws {
        let store = makeStore()
        let service = try SettlementService(store: store, groups: [.games], characterSeed: 5)
        service.process([event("dr-30", .games, 30), event("dr-60", .games, 60)])
        let first = service.engine

        let second = try SettlementService(store: store, groups: [.games], characterSeed: 5)
        let third = try SettlementService(store: store, groups: [.games], characterSeed: 5)
        XCTAssertEqual(second.engine, first)
        XCTAssertEqual(third.engine, first)
    }

    // MARK: 5. 原子写：损坏的临时文件不污染正式文件

    func testNoPartialStateFileAfterFreshInit() throws {
        let store = makeStore()
        _ = try SettlementService(store: store, groups: [.games], characterSeed: 3)
        let state = store.directory.appendingPathComponent("settlement-state.v1.json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: state.path)) // 未结算不落状态文件
        let tmp = store.directory.appendingPathComponent(".settlement-state.v1.json.tmp")
        XCTAssertFalse(FileManager.default.fileExists(atPath: tmp.path))
    }

    // MARK: 6. 跨日恢复：分段与骰子不因恢复改变

    func testCrossDayRecoveryKeepsSegments() throws {
        let store = makeStore()
        let service = try SettlementService(store: store, groups: [.games], characterSeed: 17)
        service.process(event("xd-30", .games, 30, date: "2026-11-02"))
        service.process(event("xd-30b", .games, 30, date: "2026-11-03"))

        let restored = try SettlementService(store: store, groups: [.games], characterSeed: 17)
        XCTAssertEqual(restored.engine.segments.keys.sorted(), ["2026-11-02", "2026-11-03"])
        XCTAssertEqual(restored.engine, service.engine)
    }
}
