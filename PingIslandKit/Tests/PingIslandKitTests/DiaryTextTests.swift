import XCTest
@testable import PingIslandKit

/// 遭遇与日记文案（执行文档 9.7）：textKey → 展示文案单一来源。
final class DiaryTextTests: XCTestCase {
    func testMonsterWinAndLoseTexts() {
        for monster in Monster.allCases {
            XCTAssertEqual(DiaryText.display("encounter.\(monster.rawValue).win"), monster.winText)
            XCTAssertEqual(DiaryText.display("encounter.\(monster.rawValue).lose"), monster.loseText)
        }
        XCTAssertEqual(DiaryText.display("encounter.小骷髅.win"), "战胜了小骷髅")
        XCTAssertEqual(DiaryText.display("encounter.史莱姆.lose"), "被史莱姆击退")
    }

    func testDailyLifePoolCoversAllGeneratedIndices() {
        // 遭遇规则生成的 dailylife.<n> 下标必须全部能解析（n < count）
        for index in 0..<DailyLifePool.texts.count {
            XCTAssertNotEqual(DiaryText.display("dailylife.\(index)"), "dailylife.\(index)")
        }
        // EncounterRules 生成的 index 上限 = 池大小，此断言守住该契约
        var rng = SeededRandom(seed: 1)
        for _ in 0..<200 {
            let r = EncounterRules.resolve(rng: &rng)
            if r.entryType == .dailyLife {
                XCTAssertNotEqual(DiaryText.display(r.textKey), r.textKey, "unresolved daily textKey \(r.textKey)")
            } else {
                XCTAssertNotEqual(DiaryText.display(r.textKey), r.textKey)
            }
        }
    }

    func testUnknownKeysPassThrough() {
        XCTAssertEqual(DiaryText.display("dailylife.99"), "dailylife.99")
        XCTAssertEqual(DiaryText.display("encounter.未知怪物.win"), "encounter.未知怪物.win")
        XCTAssertEqual(DiaryText.display("something.else"), "something.else")
    }

    func testDailyLifeTextsNonEmpty() {
        for text in DailyLifePool.texts {
            XCTAssertFalse(text.isEmpty)
        }
    }
}
