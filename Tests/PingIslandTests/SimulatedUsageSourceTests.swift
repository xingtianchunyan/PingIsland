import Foundation
import PingIslandKit
import XCTest
@testable import PingIsland

/// 模拟事件源（执行文档 13.1）：与生产账本隔离、确定性、可重置。
final class SimulatedUsageSourceTests: XCTestCase {
    private var base: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("sim-tests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        super.tearDown()
        try? FileManager.default.removeItem(at: base)
    }

    func testEventIDHasSimPrefixAndUniquePerSequence() {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let a = SimulatedUsageSource.makeEvent(group: .games, thresholdMinutes: 30,
                                               localDate: "2026-11-02", confirmedAt: now, sequence: 1)
        let b = SimulatedUsageSource.makeEvent(group: .games, thresholdMinutes: 30,
                                               localDate: "2026-11-02", confirmedAt: now, sequence: 2)
        XCTAssertTrue(a.stableEventID.hasPrefix("sim."))
        XCTAssertNotEqual(a.stableEventID, b.stableEventID)
        XCTAssertEqual(a.group, .games)
        XCTAssertEqual(a.thresholdMinutes, 30)
    }

    func testSimulatedStoreIsInSeparateDirectory() {
        let simDir = SimulatedUsageSource.store(base: base).directory
        XCTAssertTrue(simDir.path.contains("settlement-simulated"))
        // 与生产目录不同路径
        let prodDir = SettlementCoordinator.store().directory
        XCTAssertNotEqual(simDir.standardizedFileURL, prodDir.standardizedFileURL)
    }

    func testSimulatedSettlementWritesOnlyToSimulatedLedger() throws {
        let simStore = SimulatedUsageSource.store(base: base)
        let service = try SettlementService(store: simStore,
                                            groups: Array(TrainingGroup.allCases),
                                            characterSeed: SimulatedUsageSource.seed)
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let event = SimulatedUsageSource.makeEvent(group: .games, thresholdMinutes: 60,
                                                   localDate: "2026-11-02", confirmedAt: now, sequence: 1)
        let outcome = service.process(event)
        if case .duplicate = outcome { XCTFail("首次模拟事件不应判重") }

        XCTAssertEqual(SimulatedUsageSource.eventCount(base: base), 1)
        XCTAssertGreaterThan(service.engine.level, 1)
        // 模拟账本有文件，目录名带 simulated 标记
        XCTAssertTrue(FileManager.default.fileExists(atPath: simStore.directory.path))
    }

    func testResetClearsSimulatedLedger() throws {
        let simStore = SimulatedUsageSource.store(base: base)
        let service = try SettlementService(store: simStore,
                                            groups: Array(TrainingGroup.allCases),
                                            characterSeed: SimulatedUsageSource.seed)
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        service.process(SimulatedUsageSource.makeEvent(group: .reading, thresholdMinutes: 30,
                                                       localDate: "2026-11-02", confirmedAt: now, sequence: 1))
        XCTAssertEqual(SimulatedUsageSource.eventCount(base: base), 1)
        SimulatedUsageSource.reset(base: base)
        XCTAssertEqual(SimulatedUsageSource.eventCount(base: base), 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: simStore.directory.path))
    }

    func testSimulatedOutcomeIsDeterministicWithFixedSeed() throws {
        func run() throws -> SettlementEngine {
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("sim-det-\(UUID().uuidString)", isDirectory: true)
            let service = try SettlementService(store: JSONFileSettlementStore(directory: dir),
                                                groups: Array(TrainingGroup.allCases),
                                                characterSeed: SimulatedUsageSource.seed)
            let now = Date(timeIntervalSince1970: 1_760_000_000)
            for (i, minutes) in [30, 60, 90].enumerated() {
                service.process(SimulatedUsageSource.makeEvent(group: .social, thresholdMinutes: minutes,
                                                               localDate: "2026-11-02", confirmedAt: now, sequence: i + 1))
            }
            return service.engine
        }
        XCTAssertEqual(try run(), try run())
    }
}
