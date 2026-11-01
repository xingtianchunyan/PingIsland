import PingIslandKit
import XCTest
@testable import PingIsland

/// 监控事件名解析（执行文档 7.2）：每组独立、稳定、可持久化的事件标识。
final class MonitorEventParserTests: XCTestCase {
    func testNameParseRoundTripForAllGroups() {
        for group in TrainingGroup.allCases {
            for minutes in [30, 60, 90] {
                let name = MonitorEventParser.name(group: group, minutes: minutes)
                guard let parsed = MonitorEventParser.parse(name) else {
                    XCTFail("parse failed for \(name)")
                    continue
                }
                XCTAssertEqual(parsed.group, group)
                XCTAssertEqual(parsed.minutes, minutes)
            }
        }
    }

    func testNameUsesAllCasesIndex() {
        // allCases 索引即组序：social=0 … other=7
        XCTAssertEqual(MonitorEventParser.name(group: .social, minutes: 30), "pingisland.g0.t30")
        XCTAssertEqual(MonitorEventParser.name(group: .other, minutes: 90), "pingisland.g7.t90")
    }

    func testLegacyThresholdFormatMapsToOther() {
        let parsed = MonitorEventParser.parse("pingisland.threshold.60")
        XCTAssertEqual(parsed?.group, .other)
        XCTAssertEqual(parsed?.minutes, 60)
    }

    func testInvalidNamesReturnNil() {
        for bad in ["", "pingisland", "pingisland.g1", "pingisland.g1.t",
                    "other.g1.t30", "pingisland.g99.t30", "pingisland.gx.t30",
                    "pingisland.g1.tabc", "pingisland.g-1.t30"] {
            XCTAssertNil(MonitorEventParser.parse(bad), "expected nil for \(bad)")
        }
    }
}
