import XCTest
@testable import PingIslandKit

/// 装备外观（执行文档 9.5）与六行效果模板（执行文档 9.6）
final class ContentPoolTests: XCTestCase {
    func testAppearanceTierFormula() {
        XCTAssertEqual(EquipmentAppearance.appearanceTier(finalWisdom: 0), 1)
        XCTAssertEqual(EquipmentAppearance.appearanceTier(finalWisdom: 49), 1)
        XCTAssertEqual(EquipmentAppearance.appearanceTier(finalWisdom: 50), 2)
        XCTAssertEqual(EquipmentAppearance.appearanceTier(finalWisdom: 2500), 51)
        XCTAssertEqual(EquipmentAppearance.appearanceTier(finalWisdom: -5), 1) // 负值不下溢
    }

    func testAppearanceTypeBands() {
        XCTAssertEqual(EquipmentAppearance.appearanceType(tier: 1), "布甲")
        XCTAssertEqual(EquipmentAppearance.appearanceType(tier: 50), "布甲")
        XCTAssertEqual(EquipmentAppearance.appearanceType(tier: 51), "皮甲")
        XCTAssertEqual(EquipmentAppearance.appearanceType(tier: 150), "皮甲")
        XCTAssertEqual(EquipmentAppearance.appearanceType(tier: 151), "铁甲")
        XCTAssertEqual(EquipmentAppearance.appearanceType(tier: 300), "铁甲")
        XCTAssertEqual(EquipmentAppearance.appearanceType(tier: 301), "机甲")
    }

    func testWeekdayTemplates() {
        XCTAssertEqual(SkillRules.template(forWeekday: 1).element, "木")
        XCTAssertEqual(SkillRules.template(forWeekday: 4).passiveAttribute, .luk)
        XCTAssertEqual(SkillRules.template(forWeekday: 5).activeName, "冰晶涟漪")
        XCTAssertEqual(SkillRules.template(forWeekday: 6).element, "雷")
        XCTAssertEqual(SkillRules.template(forWeekday: 7).element, "雷")
        XCTAssertEqual(SkillRules.template(forWeekday: 7).passiveAttribute, .cha)
    }

    func testPassiveValueLv1IsRarityNumber() {
        for rarity in Rarity.allCases {
            XCTAssertEqual(SkillRules.passiveValue(rarity: rarity, level: 1), rarity.rawValue)
        }
    }

    func testPassiveValueMultipliers() {
        XCTAssertEqual(SkillRules.passiveValue(rarity: .blue, level: 2), 4)  // 3 × 1.3 = 3.9 → 4
        XCTAssertEqual(SkillRules.passiveValue(rarity: .blue, level: 3), 5)  // 3 × 1.5 = 4.5 → 5（.rounded 取偶）
        XCTAssertEqual(SkillRules.passiveValue(rarity: .purple, level: 5), 7) // 4 × 1.8 = 7.2 → 7
    }

    func testDuplicateConversionPools() {
        XCTAssertEqual(SkillRules.duplicateConversionPoints(rarity: .white), 1)
        XCTAssertEqual(SkillRules.duplicateConversionPoints(rarity: .red), 6)
        XCTAssertEqual(SkillRules.duplicateConversionPool(rarity: .blue), [.con, .int, .dex])
        XCTAssertEqual(SkillRules.duplicateConversionPool(rarity: .orange), [.luk, .wis, .cha])
    }
}
