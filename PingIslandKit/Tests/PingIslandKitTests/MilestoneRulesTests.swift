import XCTest
@testable import PingIslandKit

/// 半小时活动结算分档（真机反馈第二十批规则 v3）：固定种子大样本统计验证。
/// v3 变化：属性包入掉落（基础 CON/INT/DEX、高级 LUK/WIS/CHA），四档概率表全面调整。
final class MilestoneRulesTests: XCTestCase {
    private let samples = 20_000

    /// 跑 n 次 resolve，返回全部 grant
    private func run(dice: Int, count: Int) -> [MilestoneGrant] {
        (0..<count).map { i in
            var rng = SeededRandom(seed: UInt64(i &* 2_654_435_761) ^ UInt64(dice) &* 0x9E3779B9)
            var equipmentID = 0
            return MilestoneRules.resolve(dice: dice, weekday: (i % 7) + 1,
                                          equipmentID: &equipmentID, rng: &rng)
        }
    }

    private func ratio(_ part: Int, of total: Int) -> Double {
        total == 0 ? 0 : Double(part) / Double(total)
    }

    func testExperienceBonusFormula() {
        XCTAssertEqual(MilestoneRules.experienceBonus(dice: 5), 15)
        XCTAssertEqual(MilestoneRules.experienceBonus(dice: 10), 30)
        XCTAssertEqual(MilestoneRules.experienceBonus(dice: 15), 45)
        XCTAssertEqual(MilestoneRules.experienceBonus(dice: 20), 60)
    }

    func testDeterministicPerSeed() {
        var rngA = SeededRandom(seed: 42)
        var rngB = SeededRandom(seed: 42)
        var idA = 0, idB = 0
        let a = MilestoneRules.resolve(dice: 15, weekday: 3, equipmentID: &idA, rng: &rngA)
        let b = MilestoneRules.resolve(dice: 15, weekday: 3, equipmentID: &idB, rng: &rngB)
        XCTAssertEqual(a, b)
    }

    // MARK: 骰点 < 10：装备率 = 骰点/10（白/绿，白色率 = (10−骰点)/10）；否则基础属性 1~3 点（60/30/10%）

    func testLowDiceEquipmentOrBaseAttribute() {
        let grants = run(dice: 5, count: samples)
        XCTAssertTrue(grants.allSatisfy { $0.mainSkill == nil && $0.extraEquipment == nil })
        let equipment = grants.filter { $0.mainEquipment != nil }
        let attributes = grants.filter { !$0.attributePoints.isEmpty }
        XCTAssertEqual(equipment.count + attributes.count, grants.count)
        XCTAssertEqual(ratio(equipment.count, of: grants.count), 0.5, accuracy: 0.02)
        // 装备只有白/绿，白色率 = (10−5)/10 = 0.5
        XCTAssertTrue(equipment.allSatisfy {
            $0.mainEquipment!.rarity == .white || $0.mainEquipment!.rarity == .green
        })
        let white = equipment.filter { $0.mainEquipment!.rarity == .white }.count
        XCTAssertEqual(ratio(white, of: equipment.count), 0.5, accuracy: 0.03)
        // 基础属性 1~3 点，60/30/10
        XCTAssertTrue(attributes.allSatisfy { grant in
            grant.attributePoints.allSatisfy { attr, points in
                RulesConfig.basePackAttributes.contains(attr) && (1...3).contains(points)
            }
        })
        let p1 = attributes.filter { $0.attributePoints.values.first! == 1 }.count
        let p2 = attributes.filter { $0.attributePoints.values.first! == 2 }.count
        let p3 = attributes.filter { $0.attributePoints.values.first! == 3 }.count
        XCTAssertEqual(ratio(p1, of: attributes.count), 0.60, accuracy: 0.02)
        XCTAssertEqual(ratio(p2, of: attributes.count), 0.30, accuracy: 0.02)
        XCTAssertEqual(ratio(p3, of: attributes.count), 0.10, accuracy: 0.015)
    }

    // MARK: 骰点 = 10：50% 装备（白/绿/蓝 60/30/10%），50% 基础属性 1~3 点

    func testDiceTenEquipmentOrBaseAttribute() {
        let grants = run(dice: 10, count: samples)
        XCTAssertTrue(grants.allSatisfy { $0.mainSkill == nil && $0.extraEquipment == nil })
        let equipment = grants.filter { $0.mainEquipment != nil }
        let attributes = grants.filter { !$0.attributePoints.isEmpty }
        XCTAssertEqual(ratio(equipment.count, of: grants.count), 0.50, accuracy: 0.02)
        XCTAssertEqual(ratio(attributes.count, of: grants.count), 0.50, accuracy: 0.02)
        let white = equipment.filter { $0.mainEquipment!.rarity == .white }.count
        let green = equipment.filter { $0.mainEquipment!.rarity == .green }.count
        let blue = equipment.filter { $0.mainEquipment!.rarity == .blue }.count
        XCTAssertEqual(ratio(white, of: equipment.count), 0.60, accuracy: 0.02)
        XCTAssertEqual(ratio(green, of: equipment.count), 0.30, accuracy: 0.02)
        XCTAssertEqual(ratio(blue, of: equipment.count), 0.10, accuracy: 0.015)
        XCTAssertTrue(attributes.allSatisfy { grant in
            grant.attributePoints.allSatisfy { RulesConfig.basePackAttributes.contains($0) }
        })
    }

    // MARK: 10 < 骰点 < 20：40% 基础属性 3~5 点；30% 六阶装备；20% 高级属性 1~3 点；10% 特质/技能

    func testMidDiceFourWaySplit() {
        let grants = run(dice: 15, count: samples)
        let baseAttr = grants.filter { grant in
            grant.attributePoints.contains { RulesConfig.basePackAttributes.contains($0) }
        }
        let equipment = grants.filter { $0.mainEquipment != nil }
        let advAttr = grants.filter { grant in
            grant.attributePoints.contains { RulesConfig.oraclePackAttributes.contains($0) }
        }
        let skills = grants.filter { $0.mainSkill != nil }
        XCTAssertEqual(baseAttr.count + equipment.count + advAttr.count + skills.count, grants.count)
        XCTAssertEqual(ratio(baseAttr.count, of: grants.count), 0.40, accuracy: 0.02)
        XCTAssertEqual(ratio(equipment.count, of: grants.count), 0.30, accuracy: 0.02)
        XCTAssertEqual(ratio(advAttr.count, of: grants.count), 0.20, accuracy: 0.02)
        XCTAssertEqual(ratio(skills.count, of: grants.count), 0.10, accuracy: 0.015)

        // 基础属性 3~5 点（60/30/10）
        XCTAssertTrue(baseAttr.allSatisfy { grant in
            grant.attributePoints.values.allSatisfy { (3...5).contains($0) }
        })
        // 高级属性 1~3 点
        XCTAssertTrue(advAttr.allSatisfy { grant in
            grant.attributePoints.values.allSatisfy { (1...3).contains($0) }
        })

        // 六阶装备 40/30/20/8/1.99/0.01
        let white = equipment.filter { $0.mainEquipment!.rarity == .white }.count
        let green = equipment.filter { $0.mainEquipment!.rarity == .green }.count
        let blue = equipment.filter { $0.mainEquipment!.rarity == .blue }.count
        let purple = equipment.filter { $0.mainEquipment!.rarity == .purple }.count
        let orange = equipment.filter { $0.mainEquipment!.rarity == .orange }.count
        let red = equipment.filter { $0.mainEquipment!.rarity == .red }.count
        XCTAssertEqual(ratio(white, of: equipment.count), 0.40, accuracy: 0.02)
        XCTAssertEqual(ratio(green, of: equipment.count), 0.30, accuracy: 0.02)
        XCTAssertEqual(ratio(blue, of: equipment.count), 0.20, accuracy: 0.02)
        XCTAssertEqual(ratio(purple, of: equipment.count), 0.08, accuracy: 0.01)
        XCTAssertEqual(ratio(orange, of: equipment.count), 0.0199, accuracy: 0.005)
        XCTAssertEqual(ratio(red, of: equipment.count), 0.0001, accuracy: 0.001)

        // 特质/技能白/绿/蓝 60/30/10
        let sWhite = skills.filter { $0.mainSkill!.rarity == .white }.count
        let sGreen = skills.filter { $0.mainSkill!.rarity == .green }.count
        let sBlue = skills.filter { $0.mainSkill!.rarity == .blue }.count
        XCTAssertEqual(ratio(sWhite, of: skills.count), 0.60, accuracy: 0.03)
        XCTAssertEqual(ratio(sGreen, of: skills.count), 0.30, accuracy: 0.03)
        XCTAssertEqual(ratio(sBlue, of: skills.count), 0.10, accuracy: 0.02)
    }

    // MARK: 骰点 = 20：40% 高级属性 3~5 点；30% 装备、30% 特质·技能（紫/橙/红 80/19/1%）；必得额外高级装备

    func testDiceTwentyTriplePlusExtra() {
        let grants = run(dice: 20, count: samples)
        let advAttr = grants.filter { !$0.attributePoints.isEmpty }
        let equipment = grants.filter { $0.mainEquipment != nil }
        let skills = grants.filter { $0.mainSkill != nil }
        XCTAssertEqual(advAttr.count + equipment.count + skills.count, grants.count)
        XCTAssertEqual(ratio(advAttr.count, of: grants.count), 0.40, accuracy: 0.02)
        XCTAssertEqual(ratio(equipment.count, of: grants.count), 0.30, accuracy: 0.02)
        XCTAssertEqual(ratio(skills.count, of: grants.count), 0.30, accuracy: 0.02)

        // 高级属性 3~5 点，只落在 LUK/WIS/CHA
        XCTAssertTrue(advAttr.allSatisfy { grant in
            grant.attributePoints.allSatisfy { attr, points in
                RulesConfig.oraclePackAttributes.contains(attr) && (3...5).contains(points)
            }
        })

        // 主结果与额外装备都是紫/橙/红池
        for grant in grants {
            XCTAssertNotNil(grant.extraEquipment, "骰 20 必得额外装备")
            XCTAssertTrue([Rarity.purple, .orange, .red].contains(grant.extraEquipment!.rarity))
            if let main = grant.mainEquipment {
                XCTAssertTrue([Rarity.purple, .orange, .red].contains(main.rarity))
            }
            if let main = grant.mainSkill {
                XCTAssertTrue([Rarity.purple, .orange, .red].contains(main.rarity))
            }
        }
        let all = grants.flatMap { [$0.mainEquipment?.rarity, $0.extraEquipment?.rarity] }
            .compactMap { $0 }
        let purple = all.filter { $0 == .purple }.count
        let orange = all.filter { $0 == .orange }.count
        XCTAssertEqual(ratio(purple, of: all.count), 0.80, accuracy: 0.02)
        XCTAssertEqual(ratio(orange, of: all.count), 0.19, accuracy: 0.015)
    }
}
