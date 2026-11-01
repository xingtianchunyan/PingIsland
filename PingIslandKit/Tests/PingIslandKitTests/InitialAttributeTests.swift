import XCTest
@testable import PingIslandKit

/// 执行文档 14.1-1：初始属性总计 10 点，权重和空选择逻辑
final class InitialAttributeTests: XCTestCase {
    func testEmptySelectionUniformWeights() {
        let w = initialAttributeWeights(groups: [])
        for attr in Attribute.allCases {
            XCTAssertEqual(w[attr], 1)
        }
    }

    func testInclinationWeights() {
        let w = initialAttributeWeights(groups: [.games, .other])
        XCTAssertEqual(w[.dex], 3) // 游戏 → 敏捷 +2，基础 1
        XCTAssertEqual(w[.con], 1) // “其他”倾向平均，不加单项
        XCTAssertEqual(w.reduce(0) { $0 + $1.value }, 8) // 6 基础 + 2
    }

    func testRolledAttributesAlwaysTotalTen() {
        for seed: UInt64 in [1, 2, 3, 42, 1000] {
            var rng = SeededRandom(seed: seed)
            let attrs = rollInitialAttributes(groups: [.games, .reading], rng: &rng)
            XCTAssertEqual(attrs.reduce(0) { $0 + $1.value }, 10)
            for attr in Attribute.allCases {
                XCTAssertGreaterThanOrEqual(attrs[attr, default: 0], 1)
            }
        }
    }

    func testDeterministicGolden() {
        var rng = SeededRandom(seed: 12345)
        let a = rollInitialAttributes(groups: [.social], rng: &rng)
        var rng2 = SeededRandom(seed: 12345)
        let b = rollInitialAttributes(groups: [.social], rng: &rng2)
        XCTAssertEqual(a, b) // 同种子同结果
    }
}

/// 执行文档 8.4/9.5：最终属性公式与外观边界（14.1-11）
final class PanelTests: XCTestCase {
    func testFinalAttributeFormula() {
        var input = PanelInput()
        input.baseValues = [.con: 10]
        input.equipmentFlat = [.con: 2]
        input.passiveFlat = [.con: 1]
        input.passivePercentTenthsSum = 15 // +15%
        let out = finalAttributes(input: input)
        XCTAssertEqual(out[.con], 14) // floor(13 × 1.15) = floor(14.95)
    }

    func testFinalAttributeNotNegative() {
        let input = PanelInput(baseValues: [.con: 0])
        XCTAssertEqual(finalAttributes(input: input)[.con], 0)
    }

    func testArmorAppearanceBoundaries() {
        XCTAssertEqual(ArmorAppearance.forWisdom(0), .cloth)
        XCTAssertEqual(ArmorAppearance.forWisdom(2450), .cloth)  // 1+49=50
        XCTAssertEqual(ArmorAppearance.forWisdom(2500), .leather) // 1+50=51
        XCTAssertEqual(ArmorAppearance.forWisdom(7450), .leather) // 1+149=150
        XCTAssertEqual(ArmorAppearance.forWisdom(7500), .iron)    // 1+150=151
        XCTAssertEqual(ArmorAppearance.forWisdom(15000), .mech)   // 1+300=301
    }
}
