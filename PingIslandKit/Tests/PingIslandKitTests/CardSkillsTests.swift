import XCTest
@testable import PingIslandKit

/// 第二十一批 Phase A（下一步开发引导 D1-D4 默认决策）：
/// 元素相克/相生、卡面技能选取（展示层纯确定性）、技能连结推导、图鉴聚合。
/// 红线：全部只影响展示，严禁影响胜负 50/50 与结算数值。
final class CardSkillsTests: XCTestCase {

    // MARK: - 元素规则（D1）

    func testCounterRing() {
        XCTAssertTrue(ElementRules.beats(.wood, .earth))   // 木克土
        XCTAssertTrue(ElementRules.beats(.earth, .water))  // 土克水
        XCTAssertTrue(ElementRules.beats(.water, .fire))   // 水克火
        XCTAssertTrue(ElementRules.beats(.fire, .metal))   // 火克金
        XCTAssertTrue(ElementRules.beats(.metal, .wood))   // 金克木
        XCTAssertFalse(ElementRules.beats(.earth, .wood))  // 不可逆
        XCTAssertFalse(ElementRules.beats(.thunder, .fire)) // 雷不参与克制
        XCTAssertFalse(ElementRules.beats(.fire, .thunder))
    }

    func testGenerateRing() {
        XCTAssertTrue(ElementRules.generates(.wood, .fire))   // 木生火
        XCTAssertTrue(ElementRules.generates(.fire, .earth))  // 火生土
        XCTAssertTrue(ElementRules.generates(.earth, .metal)) // 土生金
        XCTAssertTrue(ElementRules.generates(.metal, .water)) // 金生水
        XCTAssertTrue(ElementRules.generates(.water, .wood))  // 水生木
        XCTAssertFalse(ElementRules.generates(.fire, .wood))  // 不可逆
    }

    func testThunderIsCatalyst() {
        XCTAssertTrue(ElementRules.isCatalyst(.thunder))
        XCTAssertFalse(ElementRules.isCatalyst(.wood))
    }

    // MARK: - 卡面技能选取（展示层）

    func testSelectEmptyReturnsEmpty() {
        XCTAssertTrue(CardSkillRules.select(owned: [], countered: .fire).isEmpty)
    }

    func testSelectPrefersCounterEvenAtLowerRarity() {
        guard let lib = ContentLibrary.load() else { return XCTFail("内容库应可加载") }
        // 库中找一对模板：attacker 元素克制 defender 元素
        var pair: (attacker: SkillTemplate, defender: SkillTemplate)?
        outer: for a in lib.skills {
            guard let ea = SkillElement(label: a.element), ea != .thunder else { continue }
            for b in lib.skills where a.templateID != b.templateID {
                guard let eb = SkillElement(label: b.element) else { continue }
                if ElementRules.beats(ea, eb) { pair = (a, b); break outer }
            }
        }
        guard let pair else { return XCTFail("库中应存在相克模板对") }
        let owned = [
            SkillCollectionItem(weekday: pair.defender.weekday,
                                isActive: pair.defender.kind == .active,
                                rarity: .red, level: 5),
            SkillCollectionItem(weekday: pair.attacker.weekday,
                                isActive: pair.attacker.kind == .active,
                                rarity: .white, level: 1),
        ]
        let result = CardSkillRules.select(
            owned: owned, countered: SkillElement(label: pair.defender.element))
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result[0].isCounter) // 白装克制技也排最前
        XCTAssertEqual(result[0].templateID, pair.attacker.templateID)
        XCTAssertEqual(result[1].templateID, pair.defender.templateID)
        XCTAssertFalse(result[1].isCounter)
    }

    func testSelectFillsByRarityDescAndCapsAtThree() {
        guard let lib = ContentLibrary.load() else { return XCTFail("内容库应可加载") }
        var owned: [SkillCollectionItem] = lib.skills.prefix(5).map {
            SkillCollectionItem(weekday: $0.weekday, isActive: $0.kind == .active,
                                rarity: .white, level: 1)
        }
        owned[3].rarity = .red
        owned[4].rarity = .purple
        let result = CardSkillRules.select(owned: owned, countered: nil)
        XCTAssertEqual(result.count, 3) // 最多 3 个
        XCTAssertEqual(result[0].rarity, Rarity.red.rawValue)
        XCTAssertEqual(result[1].rarity, Rarity.purple.rawValue)
        // 无克制对象时无人带克制标记
        XCTAssertTrue(result.allSatisfy { !$0.isCounter })
    }

    // MARK: - 技能连结推导（D4）

    private func item(_ t: SkillTemplate, rarity: Rarity, level: Int = 1) -> SkillCollectionItem {
        SkillCollectionItem(weekday: t.weekday, isActive: t.kind == .active,
                            rarity: rarity, level: level)
    }

    func testDeriveEmptyHasNoLinks() {
        XCTAssertTrue(SkillLinkRules.derive(owned: []).isEmpty)
    }

    func testDeriveElementResonancePair() {
        guard let lib = ContentLibrary.load() else { return XCTFail("内容库应可加载") }
        // 同一元素的两个模板（主动+被动同周）各收 1 个稀有度 → 恰好一条元素共鸣
        let sameElement = Dictionary(grouping: lib.skills, by: { $0.element })
            .values.first { $0.count >= 2 }
        guard let pair = sameElement else { return XCTFail("库中应有同元素模板对") }
        let links = SkillLinkRules.derive(owned: [item(pair[0], rarity: .white),
                                                  item(pair[1], rarity: .green)])
        XCTAssertEqual(links.filter { $0.tier == .elementResonance }.count, 1)
    }

    func testDeriveTripleResonanceSameTemplateThreeRarities() {
        guard let lib = ContentLibrary.load() else { return XCTFail("内容库应可加载") }
        let t = lib.skills[0]
        let owned = [item(t, rarity: .white), item(t, rarity: .blue), item(t, rarity: .red)]
        let links = SkillLinkRules.derive(owned: owned)
        XCTAssertTrue(links.contains { $0.tier == .tripleResonance })
    }

    func testDeriveGeneratingChainDeduped() {
        guard let lib = ContentLibrary.load() else { return XCTFail("内容库应可加载") }
        guard let wood = lib.skills.first(where: { $0.element == "木" }),
              let fire = lib.skills.first(where: { $0.element == "火" })
        else { return XCTFail("库中应有木/火模板") }
        // 木生火：两个木模板 + 一个火模板 → 元素对去重后只记一条相生链
        let wood2 = lib.skills.filter { $0.element == "木" }
        var owned = wood2.map { item($0, rarity: .white) }
        owned.append(item(fire, rarity: .white))
        let links = SkillLinkRules.derive(owned: owned)
        XCTAssertEqual(links.filter { $0.tier == .generatingChain }.count, 1)
    }

    func testDeriveRarityGlowAcrossRarities() {
        guard let lib = ContentLibrary.load() else { return XCTFail("内容库应可加载") }
        let t = lib.skills[0]
        let links = SkillLinkRules.derive(owned: [item(t, rarity: .green),
                                                  item(t, rarity: .orange)])
        let glow = links.filter { $0.tier == .rarityGlow }
        XCTAssertEqual(glow.count, 1)
        XCTAssertEqual(glow[0].memberTemplateIDs.count, 2)
    }

    // MARK: - 图鉴聚合（Phase A-5）

    func testAggregateEncountersAndWins() {
        let day = Date(timeIntervalSince1970: 1_762_000_000)
        func mk(_ type: DiaryEntryType, _ key: String) -> DiaryRecord {
            DiaryRecord(recordedAt: day, group: .games, entryType: type,
                        textKey: key, rewardSummary: "")
        }
        let diary = [
            mk(.monsterWin, "encounter.小骷髅.win"),
            mk(.monsterLose, "encounter.小骷髅.lose"),
            mk(.monsterWin, "encounter.哥布林.win"),
            mk(.dailyLife, "dailylife.0"),
            mk(.oracleBoon, "oracle.boon"),
        ]
        let entries = BestiaryRules.aggregate(diary: diary)
        XCTAssertEqual(entries.count, 2) // 只统计遭遇过的
        let skel = entries.first { $0.monster == .skeleton }
        XCTAssertEqual(skel?.encounters, 2)
        XCTAssertEqual(skel?.wins, 1)
        let goblin = entries.first { $0.monster == .goblin }
        XCTAssertEqual(goblin?.wins, 1)
    }

    func testMonsterElementsAssigned() {
        XCTAssertEqual(Monster.skeleton.element, .earth)
        XCTAssertEqual(Monster.goblin.element, .metal)
        XCTAssertEqual(Monster.slime.element, .water)
        XCTAssertEqual(Monster.sapling.element, .wood)
        XCTAssertEqual(Monster.salamander.element, .fire)
        XCTAssertEqual(Monster.staticOrb.element, .thunder)
    }
}
