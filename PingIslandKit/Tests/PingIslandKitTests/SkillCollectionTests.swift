import XCTest
@testable import PingIslandKit

/// 技能收藏账本（执行文档 9.6）：同模板+同稀有度=同一收藏项；Lv5 后重复转化为属性点。
final class SkillCollectionTests: XCTestCase {
    func testFirstDrawCreatesItem() {
        var c = SkillCollection()
        let draw = SkillDrawRules.draw(characterSeed: 1, dice: 20, minuteIndex: 1, weekday: 2)
        let outcome = c.add(draw)
        guard case .newItem(let item) = outcome else { return XCTFail("应为 newItem") }
        XCTAssertEqual(item.level, 1)
        XCTAssertEqual(item.weekday, 2)
        XCTAssertEqual(item.rarity, draw.rarity)
        XCTAssertEqual(item.isActive, draw.isActive)
        XCTAssertEqual(c.items.count, 1)
    }

    func testSameIdentityLevelsUpToFive() {
        var c = SkillCollection()
        let identity = SkillDrawRules.draw(characterSeed: 9, dice: 12, minuteIndex: 1, weekday: 3)
        // 复刻同一身份：用相同 weekday/主被动/稀有度构造
        func sameIdentityDraw() -> SkillDraw {
            SkillDraw(template: identity.template, rarity: identity.rarity,
                      isActive: identity.isActive, passiveValue: identity.passiveValue,
                      weekday: identity.weekday)
        }
        XCTAssertEqual(c.add(sameIdentityDraw()), .newItem(c.items[0]))
        for expectedLevel in 2...5 {
            guard case .leveledUp(let item) = c.add(sameIdentityDraw()) else {
                return XCTFail("第 \(expectedLevel) 次应为 leveledUp")
            }
            XCTAssertEqual(item.level, expectedLevel)
        }
        XCTAssertEqual(c.items.count, 1)
    }

    func testMaxLevelConverts() {
        var c = SkillCollection()
        let base = SkillDrawRules.draw(characterSeed: 5, dice: 12, minuteIndex: 1, weekday: 4)
        let draw = SkillDraw(template: base.template, rarity: .purple, isActive: base.isActive,
                             passiveValue: 0, weekday: base.weekday)
        for _ in 0..<5 { _ = c.add(draw) } // 升至 Lv5
        let outcome = c.add(draw)
        XCTAssertEqual(outcome, .converted(points: 4, pool: [.luk, .wis, .cha]))
        // 转化不改变收藏项
        XCTAssertEqual(c.items.count, 1)
        XCTAssertEqual(c.items[0].level, 5)
    }

    func testDifferentRarityIsDifferentItem() {
        var c = SkillCollection()
        let base = SkillDrawRules.draw(characterSeed: 5, dice: 12, minuteIndex: 1, weekday: 4)
        _ = c.add(SkillDraw(template: base.template, rarity: .green, isActive: true,
                            passiveValue: 0, weekday: base.weekday))
        _ = c.add(SkillDraw(template: base.template, rarity: .red, isActive: true,
                            passiveValue: 0, weekday: base.weekday))
        XCTAssertEqual(c.items.count, 2)
    }

    func testCodableRoundTrip() throws {
        var c = SkillCollection()
        let draw = SkillDrawRules.draw(characterSeed: 2, dice: 20, minuteIndex: 1, weekday: 6)
        _ = c.add(draw)
        let data = try JSONEncoder().encode(c)
        XCTAssertEqual(try JSONDecoder().decode(SkillCollection.self, from: data), c)
    }
}
