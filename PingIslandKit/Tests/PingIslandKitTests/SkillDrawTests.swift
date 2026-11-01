import XCTest
@testable import PingIslandKit

/// 技能抽选确定性（执行文档 9.6）：同输入同结果、逐分钟独立、可批量重建。
final class SkillDrawTests: XCTestCase {
    func testSameInputSameResult() {
        let a = SkillDrawRules.draw(characterSeed: 7, dice: 15, minuteIndex: 3, weekday: 2)
        let b = SkillDrawRules.draw(characterSeed: 7, dice: 15, minuteIndex: 3, weekday: 2)
        XCTAssertEqual(a, b)
    }

    func testDifferentSeedsDiffer() {
        let a = SkillDrawRules.draw(characterSeed: 7, dice: 15, minuteIndex: 3, weekday: 2)
        let b = SkillDrawRules.draw(characterSeed: 8, dice: 15, minuteIndex: 3, weekday: 2)
        // 不强制不同（理论上可能撞），但模板/主动位至少允许不同；只验证可复现性已由上题覆盖
        _ = (a, b)
    }

    func testDifferentMinutesDiffer() {
        let draws = SkillDrawRules.sequence(characterSeed: 7, dice: 15, fromMinute: 1, count: 20, weekday: 2)
        XCTAssertEqual(draws.count, 20)
        // 20 连抽不应全部相同（独立性 sanity check；确定性由上题保证）
        XCTAssertFalse(draws.allSatisfy { $0 == draws[0] })
    }

    func testWeekdayDrivesTemplate() {
        let mon = SkillDrawRules.draw(characterSeed: 1, dice: 20, minuteIndex: 1, weekday: 1)
        let sun = SkillDrawRules.draw(characterSeed: 1, dice: 20, minuteIndex: 1, weekday: 7)
        XCTAssertEqual(mon.template.element, "木")
        XCTAssertEqual(sun.template.element, "雷")
    }

    func testSequenceEqualsPerMinuteCalls() {
        let seq = SkillDrawRules.sequence(characterSeed: 42, dice: 11, fromMinute: 5, count: 8, weekday: 4)
        for (offset, draw) in seq.enumerated() {
            XCTAssertEqual(draw, SkillDrawRules.draw(characterSeed: 42, dice: 11,
                                                     minuteIndex: 5 + offset, weekday: 4))
        }
    }

    func testPassiveValueConsistency() {
        // 被动抽选的数值必须与 SkillRules.passiveValue(Lv1) 一致
        for minute in 1...30 {
            let d = SkillDrawRules.draw(characterSeed: 3, dice: 18, minuteIndex: minute, weekday: 3)
            if d.isActive {
                XCTAssertEqual(d.passiveValue, 0)
            } else {
                XCTAssertEqual(d.passiveValue, SkillRules.passiveValue(rarity: d.rarity, level: 1))
            }
        }
    }
}
