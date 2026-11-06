import XCTest
@testable import PingIslandKit

/// 半小时活动结算分档（真机反馈第十九批规则 v2）：固定种子大样本统计验证。
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

    // MARK: 骰点 < 10：仅白/绿装备，获得率 = 骰点/10，白色率 = (10−骰点)/10

    func testLowDiceOnlyWhiteGreenEquipment() {
        let grants = run(dice: 5, count: samples)
        XCTAssertTrue(grants.allSatisfy { $0.mainSkill == nil && $0.extraEquipment == nil })
        XCTAssertTrue(grants.allSatisfy {
            $0.mainEquipment == nil || $0.mainEquipment!.rarity == .white
                || $0.mainEquipment!.rarity == .green
        })
        let acquired = grants.filter { $0.mainEquipment != nil }
        XCTAssertEqual(ratio(acquired.count, of: grants.count), 0.5, accuracy: 0.02)
        let white = acquired.filter { $0.mainEquipment!.rarity == .white }.count
        XCTAssertEqual(ratio(white, of: acquired.count), 0.5, accuracy: 0.03)
    }

    // MARK: 骰点 = 10：必得白/绿/蓝装备 60/30/10

    func testDiceTenAlwaysEquipment() {
        let grants = run(dice: 10, count: samples)
        XCTAssertTrue(grants.allSatisfy { $0.mainEquipment != nil })
        XCTAssertTrue(grants.allSatisfy { $0.mainSkill == nil && $0.extraEquipment == nil })
        let white = grants.filter { $0.mainEquipment!.rarity == .white }.count
        let green = grants.filter { $0.mainEquipment!.rarity == .green }.count
        let blue = grants.filter { $0.mainEquipment!.rarity == .blue }.count
        XCTAssertEqual(ratio(white, of: grants.count), 0.60, accuracy: 0.02)
        XCTAssertEqual(ratio(green, of: grants.count), 0.30, accuracy: 0.02)
        XCTAssertEqual(ratio(blue, of: grants.count), 0.10, accuracy: 0.015)
    }

    // MARK: 10 < 骰点 < 20：70% 全六阶装备（40/30/20/8/1.99/0.01），30% 白/绿/蓝技能

    func testMidDiceEquipmentVsSkill() {
        let grants = run(dice: 15, count: samples)
        let equipment = grants.filter { $0.mainEquipment != nil }
        let skills = grants.filter { $0.mainSkill != nil }
        XCTAssertEqual(equipment.count + skills.count, grants.count)
        XCTAssertEqual(ratio(equipment.count, of: grants.count), 0.70, accuracy: 0.02)
        XCTAssertEqual(ratio(skills.count, of: grants.count), 0.30, accuracy: 0.02)

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

        let sWhite = skills.filter { $0.mainSkill!.rarity == .white }.count
        let sGreen = skills.filter { $0.mainSkill!.rarity == .green }.count
        let sBlue = skills.filter { $0.mainSkill!.rarity == .blue }.count
        XCTAssertEqual(ratio(sWhite, of: skills.count), 0.60, accuracy: 0.02)
        XCTAssertEqual(ratio(sGreen, of: skills.count), 0.30, accuracy: 0.02)
        XCTAssertEqual(ratio(sBlue, of: skills.count), 0.10, accuracy: 0.015)
    }

    // MARK: 骰点 = 20：主结果装备/技能各 50%（紫/橙/红 80/19/1），必得额外高级装备

    func testDiceTwentyDoubleHighTierReward() {
        let grants = run(dice: 20, count: samples)
        let equipment = grants.filter { $0.mainEquipment != nil }
        let skills = grants.filter { $0.mainSkill != nil }
        XCTAssertEqual(ratio(equipment.count, of: grants.count), 0.50, accuracy: 0.02)
        XCTAssertEqual(ratio(skills.count, of: grants.count), 0.50, accuracy: 0.02)

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
