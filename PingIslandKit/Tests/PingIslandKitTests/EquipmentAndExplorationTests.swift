import XCTest
@testable import PingIslandKit

/// 执行文档 14.1-8/9/10：概率表行和、装备词条不重复、自动择优、魅力追加边界
final class EquipmentAndExplorationTests: XCTestCase {
    func testRarityTableRowsSumTo100() {
        for (key, row) in RulesConfig.rarityPercentByDice {
            XCTAssertEqual(row.reduce(0, +), 100, "行 \(key) 概率和必须为 100")
        }
    }

    func testEquipmentGenerationByRarity() {
        var id = 0
        var rng = SeededRandom(seed: 5)
        let white = EquipmentRules.generate(id: { id += 1; return id }(), rarity: .white, rng: &rng)
        XCTAssertEqual(white.affixes.count, 1)
        XCTAssertEqual(white.totalValue, 1)

        var rng2 = SeededRandom(seed: 5)
        let purple = EquipmentRules.generate(id: 9, rarity: .purple, rng: &rng2)
        XCTAssertEqual(purple.affixes.count, 4) // 3 基础 + 1 高级
        XCTAssertEqual(purple.totalValue, 16)   // 4 条 × 4
    }

    func testBaseAffixesNonRepeatingFromCODINTDEX() {
        var rng = SeededRandom(seed: 77)
        for _ in 0..<200 {
            let item = EquipmentRules.generate(id: 1, rarity: .blue, rng: &rng) // 3 基础词条
            let baseAttrs = item.affixes.map { $0.attribute }
            XCTAssertEqual(Set(baseAttrs).count, baseAttrs.count, "词条不得重复")
            for affix in item.affixes {
                XCTAssertTrue([.con, .int, .dex, .luk, .wis, .cha].contains(affix.attribute))
            }
        }
    }

    func testAutoEquipPreference() {
        var rng = SeededRandom(seed: 8)
        let green = EquipmentRules.generate(id: 1, rarity: .green, rng: &rng)
        XCTAssertTrue(EquipmentRules.shouldEquip(newItem: green, current: nil))

        var rng2 = SeededRandom(seed: 8)
        let sameSlotGreen = EquipmentRules.generate(id: 2, rarity: .green, rng: &rng2)
        // 等阶相同、总值相同 → 保留旧装备
        if sameSlotGreen.slot == green.slot && sameSlotGreen.totalValue == green.totalValue {
            XCTAssertFalse(EquipmentRules.shouldEquip(newItem: sameSlotGreen, current: green))
        }
        let blue = EquipmentItem(id: 3, slot: green.slot, rarity: .blue,
                                 affixes: [Affix(attribute: .con, value: 3),
                                           Affix(attribute: .int, value: 3),
                                           Affix(attribute: .dex, value: 3)], isEquipped: true)
        XCTAssertTrue(EquipmentRules.shouldEquip(newItem: blue, current: green)) // 等阶高优先
        XCTAssertFalse(EquipmentRules.shouldEquip(newItem: green, current: blue)) // 等阶低不换
    }

    // MARK: 第二十一批：外观数值倍率（布×1/皮×4/铁×16/机×64）与换装比较 v2

    func testAppearanceValueMultiplier() {
        XCTAssertEqual(EquipmentAppearance.valueMultiplier(type: "布甲"), 1)
        XCTAssertEqual(EquipmentAppearance.valueMultiplier(type: "皮甲"), 4)
        XCTAssertEqual(EquipmentAppearance.valueMultiplier(type: "铁甲"), 16)
        XCTAssertEqual(EquipmentAppearance.valueMultiplier(type: "机甲"), 64)
        XCTAssertEqual(EquipmentAppearance.tierRank(type: "布甲"), 0)
        XCTAssertEqual(EquipmentAppearance.tierRank(type: "机甲"), 3)
    }

    func testGenerateWithAppearanceScalesAffixValues() {
        var rng = SeededRandom(seed: 5)
        let iron = EquipmentRules.generate(id: 9, slot: .head, rarity: .purple,
                                           appearance: "铁甲", rng: &rng)
        XCTAssertEqual(iron.affixes.count, 4)   // 3 基础 + 1 高级
        XCTAssertEqual(iron.totalValue, 4 * 4 * 16) // 4 条 × 基础 4 × 铁甲 16
        XCTAssertEqual(iron.appearance, "铁甲")  // 外观随装备入库
        // 旧两参重载默认布甲，数值行为与旧版一致
        var rng2 = SeededRandom(seed: 5)
        let cloth = EquipmentRules.generate(id: 9, rarity: .purple, rng: &rng2)
        XCTAssertEqual(cloth.totalValue, 16)
    }

    func testAutoEquipV2LowTierNeedsDoubleValueAndHigherAppearance() {
        let cur = EquipmentItem(id: 1, slot: .head, rarity: .purple,
                                affixes: [Affix(attribute: .con, value: 4)], isEquipped: true,
                                appearance: "布甲")
        // 蓝色铁甲数值翻倍 → 允许顶替紫色布甲
        let strongIron = EquipmentItem(id: 2, slot: .head, rarity: .blue,
                                       affixes: [Affix(attribute: .con, value: 8)],
                                       isEquipped: false, appearance: "铁甲")
        XCTAssertTrue(EquipmentRules.shouldEquip(newItem: strongIron, current: cur))
        // 数值不足翻倍 → 不换
        let weakIron = EquipmentItem(id: 3, slot: .head, rarity: .blue,
                                     affixes: [Affix(attribute: .con, value: 4)],
                                     isEquipped: false, appearance: "铁甲")
        XCTAssertFalse(EquipmentRules.shouldEquip(newItem: weakIron, current: cur))
        // 外观档位不更高（同为布甲）→ 低稀有永不覆盖高稀有
        let weakCloth = EquipmentItem(id: 6, slot: .head, rarity: .blue,
                                      affixes: [Affix(attribute: .con, value: 100)],
                                      isEquipped: false, appearance: "布甲")
        XCTAssertFalse(EquipmentRules.shouldEquip(newItem: weakCloth, current: cur))
        // 高稀有（含红色）被低阶覆盖需要"外观档位更高 + 数值 ≥ 当前×2"双条件
        let red = EquipmentItem(id: 4, slot: .head, rarity: .red,
                                affixes: [Affix(attribute: .con, value: 20)], isEquipped: true,
                                appearance: "布甲")
        // 紫机甲数值不足翻倍 → 不换（红色不轻易被覆盖）
        let weakMech = EquipmentItem(id: 5, slot: .head, rarity: .purple,
                                     affixes: [Affix(attribute: .con, value: 39)],
                                     isEquipped: false, appearance: "机甲")
        XCTAssertFalse(EquipmentRules.shouldEquip(newItem: weakMech, current: red))
        // 紫机甲数值 ≥ 当前×2 且外观档位更高 → 换（规则一致性：双条件都满足）
        let strongMech = EquipmentItem(id: 7, slot: .head, rarity: .purple,
                                       affixes: [Affix(attribute: .con, value: 40)],
                                       isEquipped: false, appearance: "机甲")
        XCTAssertTrue(EquipmentRules.shouldEquip(newItem: strongMech, current: red))
    }

    func testCharmExtraBoundaries() {
        XCTAssertEqual(ExplorationRules.charmExtraChance(finalCharm: 0), 0)
        XCTAssertEqual(ExplorationRules.charmExtraChance(finalCharm: 5000), 0.5, accuracy: 0.0001)
        XCTAssertEqual(ExplorationRules.charmExtraChance(finalCharm: 10000), 1)
        XCTAssertEqual(ExplorationRules.charmExtraChance(finalCharm: 99999), 1) // 封顶
        XCTAssertEqual(ExplorationRules.charmExtraChance(finalCharm: -5), 0)    // 不下溢
    }

    func testExplorationDeterministicGolden() {
        var idA = 0
        var rngA = SeededRandom(seed: 2024)
        let a = ExplorationRules.resolve(dice: 12, finalCharm: 5000, equipmentID: &idA, rng: &rngA)
        var idB = 0
        var rngB = SeededRandom(seed: 2024)
        let b = ExplorationRules.resolve(dice: 12, finalCharm: 5000, equipmentID: &idB, rng: &rngB)
        XCTAssertEqual(a, b)
    }

    func testExplorationEquipmentCapTwo() {
        for seed: UInt64 in [1, 2, 3] {
            var id = 0
            var rng = SeededRandom(seed: seed)
            let r = ExplorationRules.resolve(dice: 20, finalCharm: 10000, equipmentID: &id, rng: &rng)
            XCTAssertLessThanOrEqual(r.equipment.count, 2) // 原奖励装备 + 魅力追加，最多 2 件
        }
    }

    func testDailyExplorationCapFive() {
        var segment = GameDaySegment(segmentID: 1, localDate: "2026-11-02", timeZoneID: "Asia/Shanghai")
        var count = 0
        while segment.tryConsumeExploration(for: .games) { count += 1 }
        XCTAssertEqual(count, 5) // 每组每日最多 5 次
    }

    func testOracleRewardOncePerDay() {
        var segment = GameDaySegment(segmentID: 1, localDate: "2026-11-02", timeZoneID: "Asia/Shanghai")
        XCTAssertTrue(segment.tryIssueOracleReward())
        XCTAssertFalse(segment.tryIssueOracleReward()) // 每日只发一次
    }

    func testDice20OracleBand() {
        XCTAssertEqual(DiceRules.band(1), 1)
        XCTAssertEqual(DiceRules.band(10), 1)
        XCTAssertEqual(DiceRules.band(11), 2)
        XCTAssertEqual(DiceRules.band(19), 2)
        XCTAssertEqual(DiceRules.band(20), 3)
    }
}
