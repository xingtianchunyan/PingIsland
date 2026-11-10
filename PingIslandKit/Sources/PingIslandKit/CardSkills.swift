/// 卡面技能 / 技能连结 / 图鉴（下一步开发引导 Phase A，决策 D1-D4 按默认）。
/// 全部为展示层纯函数：不改胜负概率、不改成长公式、不加数值战斗（红线 1）；
/// 无随机，展示读取不抽签（红线 2）。
import Foundation

// MARK: - 元素（D1：五行相克环 + 雷催化剂）

public enum SkillElement: String, CaseIterable, Codable, Sendable {
    case wood = "木"
    case earth = "土"
    case water = "水"
    case fire = "火"
    case metal = "金"
    case thunder = "雷"

    /// 中文标签 → 元素（内容库 element 字段用中文）
    public init?(label: String) {
        self.init(rawValue: label)
    }
}

public enum ElementRules {
    /// 五行相克环（D1 默认：木→土→水→火→金→木，箭头 = 前者克制后者）
    private static let counterRing: [(SkillElement, SkillElement)] = [
        (.wood, .earth), (.earth, .water), (.water, .fire),
        (.fire, .metal), (.metal, .wood),
    ]

    /// 五行相生环（D4 相生链用：木→火→土→金→水→木，箭头 = 前者滋生后者）
    private static let generateRing: [(SkillElement, SkillElement)] = [
        (.wood, .fire), (.fire, .earth), (.earth, .metal),
        (.metal, .water), (.water, .wood),
    ]

    /// attacker 是否克制 defender（雷不参与克制）
    public static func beats(_ attacker: SkillElement, _ defender: SkillElement) -> Bool {
        counterRing.contains { $0 == (attacker, defender) }
    }

    /// 相生链：from 的元素能否滋生 to 的元素（木生火、火生土……）
    public static func generates(_ from: SkillElement, _ to: SkillElement) -> Bool {
        generateRing.contains { $0 == (from, to) }
    }

    /// 雷是催化剂：与任一非雷元素成链（展示层"万能克制"标记，不参与相克环）
    public static func isCatalyst(_ element: SkillElement) -> Bool {
        element == .thunder
    }
}

// MARK: - 卡面技能选取（展示层，遇怪取克制，不足补齐 D3）

/// 卡面展示用技能条目（快照字段，纯数据）
public struct CardSkill: Equatable, Codable, Sendable, Identifiable {
    /// 内容模板键（如 wood.active）
    public var templateID: String
    /// 展示名（按稀有度变体）
    public var name: String
    /// 图标 imageset 键（可空，空则用元素符号）
    public var iconKey: String?
    /// 元素中文标签
    public var element: String
    /// 是否克制当前遭遇怪的元素
    public var isCounter: Bool
    public var rarity: Int
    public var level: Int
    public var id: String { "\(templateID).\(rarity)" }
}

public enum CardSkillRules {
    /// 选取卡面 3 技能：
    /// ① 优先取克制 monsterElement 的已获技能（同元素按稀有度降序、再按等级降序）；
    ///    雷为催化剂，视为万能克制，排在元素克制之后；
    /// ② 不足 3 个按 D3 补齐：其余已获技能按稀有度降序填充；
    /// ③ 一个都没有返回空集（卡面显示"修行中"）。
    /// 纯确定性排序，无随机；只影响展示，严禁影响胜负 50/50（红线）。
    public static func select(owned: [SkillCollectionItem],
                              countered monsterElement: SkillElement?) -> [CardSkill] {
        let lib = ContentLibrary.shared
        var entries: [(item: SkillCollectionItem, card: CardSkill)] = []
        for item in owned {
            guard let template = lib?.skill(weekday: item.weekday,
                                            kind: item.isActive ? .active : .passive)
            else { continue }
            let element = SkillElement(label: template.element) ?? .wood
            let isCounter = monsterElement.map { m in
                ElementRules.isCatalyst(element) || ElementRules.beats(element, m)
            } ?? false
            let displayName = lib?.variant(weekday: item.weekday, kind: item.isActive ? .active : .passive,
                                           rarity: item.rarity)?.name ?? template.name
            entries.append((item, CardSkill(
                templateID: template.templateID, name: displayName,
                iconKey: template.iconKey, element: template.element,
                isCounter: isCounter, rarity: item.rarity.rawValue, level: item.level)))
        }
        // 排序键：克制优先 → 稀有度降序 → 等级降序 → 模板键（稳定）
        func sortKey(_ pair: (item: SkillCollectionItem, card: CardSkill)) -> (Int, Int, Int, String) {
            (pair.card.isCounter ? 0 : 1,
             -pair.card.rarity,
             -pair.card.level,
             pair.card.templateID)
        }
        let counters = entries.filter { $0.card.isCounter }.sorted { sortKey($0) < sortKey($1) }
        let others = entries.filter { !$0.card.isCounter }.sorted { sortKey($0) < sortKey($1) }
        return (counters + others).prefix(3).map(\.card)
    }
}

// MARK: - 技能连结推导（D4 四档，纯函数无随机）

public enum SkillLinkTier: Int, Codable, Sendable, CaseIterable {
    case elementResonance = 1   // 元素共鸣：同元素 ≥2
    case generatingChain        // 相生链：两元素构成相生对
    case tripleResonance        // 三连大共鸣：同元素 ≥3 或三步相生链
    case rarityGlow             // 稀有度亮度：同模板跨 ≥2 稀有度
}

/// 一条连结：成员（模板键）+ 档位 + 展示文案
public struct SkillLink: Equatable, Codable, Sendable, Identifiable {
    public var memberTemplateIDs: [String]
    public var tier: SkillLinkTier
    public var text: String
    public var id: String { memberTemplateIDs.sorted().joined(separator: "+") + ".\(tier.rawValue)" }
}

public enum SkillLinkRules {
    /// 由已获收藏推导全部连结（D4 四档；档位可共存，UI 按最高档发光）
    public static func derive(owned: [SkillCollectionItem]) -> [SkillLink] {
        let lib = ContentLibrary.shared
        struct Info { var templateID: String; var element: SkillElement; var rarity: Int; var weekday: Int; var isActive: Bool }
        var infos: [Info] = []
        for item in owned {
            guard let template = lib?.skill(weekday: item.weekday,
                                            kind: item.isActive ? .active : .passive)
            else { continue }
            infos.append(Info(templateID: template.templateID,
                              element: SkillElement(label: template.element) ?? .wood,
                              rarity: item.rarity.rawValue,
                              weekday: item.weekday, isActive: item.isActive))
        }
        var links: [SkillLink] = []

        // ① 元素共鸣 / ③ 三连大共鸣：按元素分组
        let byElement = Dictionary(grouping: infos, by: \.element)
        for (element, members) in byElement where members.count >= 2 {
            let ids = members.map(\.templateID)
            if members.count >= 3 {
                links.append(SkillLink(memberTemplateIDs: ids, tier: .tripleResonance,
                                       text: "\(element.rawValue)×\(members.count) 大共鸣"))
                continue
            }
            links.append(SkillLink(memberTemplateIDs: ids, tier: .elementResonance,
                                   text: "\(element.rawValue) 元素共鸣"))
        }

        // ② 相生链：成对构成相生关系（去重：元素对只记一条）
        var seenPairs: Set<String> = []
        for a in infos {
            for b in infos where a.templateID != b.templateID {
                guard ElementRules.generates(a.element, b.element) else { continue }
                let pairKey = [a.element.rawValue, b.element.rawValue].sorted().joined()
                guard seenPairs.insert(pairKey).inserted else { continue }
                links.append(SkillLink(memberTemplateIDs: [a.templateID, b.templateID],
                                       tier: .generatingChain,
                                       text: "\(a.element.rawValue)生\(b.element.rawValue) 相生链"))
            }
        }

        // ④ 稀有度亮度：同模板（星期+主被动）跨 ≥2 稀有度，亮度按最高稀有度
        let byTemplate = Dictionary(grouping: infos) {
            "\($0.weekday).\($0.isActive ? "a" : "p")"
        }
        for (_, members) in byTemplate where Set(members.map(\.rarity)).count >= 2 {
            let maxRarity = members.map(\.rarity).max() ?? 1
            let ids = members.map(\.templateID)
            links.append(SkillLink(memberTemplateIDs: ids, tier: .rarityGlow,
                                   text: "稀有度亮度 ×\(maxRarity)"))
        }
        return links
    }
}

// MARK: - 图鉴聚合（Phase A-5：日记 textKey → 怪物遭遇/胜数）

public struct BestiaryEntry: Equatable, Codable, Sendable, Identifiable {
    public var monster: Monster
    public var encounters: Int
    public var wins: Int
    public var id: String { monster.rawValue }
}

public enum BestiaryRules {
    /// 聚合日记为图鉴（展示层只读；遭遇 = win+lose 条目数）
    public static func aggregate(diary: [DiaryRecord]) -> [BestiaryEntry] {
        var table: [Monster: (encounters: Int, wins: Int)] = [:]
        for entry in diary where entry.entryType == .monsterWin
            || entry.entryType == .monsterLose {
            guard let monster = monster(in: entry.textKey) else { continue }
            var row = table[monster] ?? (0, 0)
            row.encounters += 1
            if entry.entryType == .monsterWin { row.wins += 1 }
            table[monster] = row
        }
        return Monster.allCases.compactMap { monster in
            guard let row = table[monster] else { return nil }
            return BestiaryEntry(monster: monster, encounters: row.encounters, wins: row.wins)
        }
    }

    /// 解析 "encounter.<怪物名>.win/lose"（与 DiaryText.display 同一解析口径）
    private static func monster(in textKey: String) -> Monster? {
        guard textKey.hasPrefix("encounter.") else { return nil }
        let body = String(textKey.dropFirst("encounter.".count))
        let parts = body.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2 else { return nil }
        return Monster(rawValue: parts[0])
    }
}
