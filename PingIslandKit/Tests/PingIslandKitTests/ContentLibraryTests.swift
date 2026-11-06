/// 内容库结构校验（执行文档 9.1/9.6：概率表与内容池的单一来源；当日池必须拥有所有可抽等阶模板）
import XCTest
@testable import PingIslandKit

final class ContentLibraryTests: XCTestCase {

    let library: ContentLibrary = {
        guard let lib = ContentLibrary.load() else {
            fatalError("ContentLibrary.json 缺失或解码失败——资源未随包分发")
        }
        return lib
    }()

    func testBundleResourceLoads() {
        XCTAssertNotNil(ContentLibrary.shared)
    }

    func testTwelveTemplatesAndUniqueIDs() {
        XCTAssertEqual(library.skills.count, 12)
        XCTAssertEqual(Set(library.skills.map(\.templateID)).count, 12)
    }

    /// 9.6：周一木 … 周六日雷；模板名与 SkillRules 单一来源一致
    func testTemplateNamesMatchSkillRules() {
        for weekday in 1...7 {
            let day = SkillRules.template(forWeekday: weekday)
            for kind in [SkillKind.active, .passive] {
                let template = library.skill(weekday: weekday, kind: kind)
                XCTAssertNotNil(template, "weekday \(weekday) \(kind) 缺模板")
                let expected = kind == .active ? day.activeName : day.passiveName
                XCTAssertEqual(template?.name, expected)
            }
        }
    }

    /// 72 项内容：12 模板 × 6 稀有度，全覆盖（不允许“抽中了却发不出”）
    func testSeventyTwoVariantsCoverAllRarities() {
        for template in library.skills {
            XCTAssertEqual(template.variants.count, 6, template.templateID)
            XCTAssertEqual(Set(template.variants.map(\.rarity)), Set(Rarity.allCases), template.templateID)
        }
        XCTAssertEqual(library.skills.reduce(0) { $0 + $1.variants.count }, 72)
    }

    func testPassiveTemplatesMatchDayAttribute() {
        for template in library.skills where template.kind == .passive {
            XCTAssertEqual(template.attribute, SkillRules.template(forWeekday: template.weekday).passiveAttribute)
        }
        for template in library.skills where template.kind == .active {
            XCTAssertNil(template.attribute)
            XCTAssertNotNil(template.poseKey)
        }
    }

    /// 9.1：骰点 20 可抽紫/橙/红，11~19 可抽白~红 —— 内容池每个稀有度都有可展示变体
    func testVariantLookupByCollectionIdentity() {
        for weekday in 1...7 {
            for kind in [SkillKind.active, .passive] {
                for rarity in Rarity.allCases {
                    XCTAssertNotNil(library.variant(weekday: weekday, kind: kind, rarity: rarity),
                                    "weekday \(weekday) \(kind) \(rarity) 无变体")
                }
            }
        }
    }

    func testEquipmentIconKeysAllSlotsAndTiers() {
        for slot in EquipmentSlot.allCases {
            for tier in AppearanceTier.allCases {
                XCTAssertNotNil(library.equipmentIcon(slot: slot, tier: tier), "\(slot) \(tier)")
            }
        }
    }

    func testClassAndFatigueArtKeysComplete() {
        for characterClass in [CharacterClass.bard, .archmage, .gladiator, .oracle,
                               .wanderArtist, .alchemist, .monk, .ranger] {
            XCTAssertNotNil(library.classArt(characterClass))
        }
        XCTAssertEqual(library.fatigueArtKeys.keys.sorted(),
                       ["drowsy", "fresh", "leaning", "sleeping", "tired"])
        XCTAssertEqual(library.monsterArtKeys.keys.sorted(),
                       ["cinder_bat", "goblin", "mushroom", "rock_crab",
                        "rust_puppet", "salamander", "sapling", "skeleton",
                        "slime", "static_orb", "thunder_fledgling", "water_wisp"])
    }

    func testSharedIsValid() {
        XCTAssertTrue(library.isValid)
    }

    func testCodableRoundTrip() throws {
        let data = try JSONEncoder().encode(library)
        let decoded = try JSONDecoder().decode(ContentLibrary.self, from: data)
        XCTAssertEqual(decoded, library)
    }
}
