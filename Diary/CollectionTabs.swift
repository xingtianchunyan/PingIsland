import PingIslandKit
import SwiftUI

/// 收藏页"特质/技能"标签（Phase B）：12 模板（6 元素 × 主/被动）× 6 稀有度收集墙。
/// 读 ContentLibrary 名称/描述 + 快照收藏进度；成链技能加链线发光标记（D4）。
struct SkillCollectionWall: View {
    let snapshot: DisplaySnapshot

    /// 已获收藏索引："weekday.a/p.rarity" → (level, rarity)
    /// （不用 uniqueKeysWithValues：防御重复项直接崩溃；后写覆盖先写）
    private var ownedIndex: [String: DisplaySnapshot.SkillDetail] {
        var map: [String: DisplaySnapshot.SkillDetail] = [:]
        for detail in snapshot.skills ?? [] {
            map["w\(detail.weekday).\(detail.isActive ? "a" : "p").\(detail.rarity)"] = detail
        }
        return map
    }

    /// 模板是否参与连结 → 最高档位
    private var linkTier: [String: SkillLinkTier] {
        var map: [String: SkillLinkTier] = [:]
        for link in snapshot.skillLinks ?? [] {
            for id in link.memberTemplateIDs {
                if let existing = map[id], existing.rawValue >= link.tier.rawValue { continue }
                map[id] = link.tier
            }
        }
        return map
    }

    private var templates: [SkillTemplate] {
        (ContentLibrary.shared?.skills ?? [])
            .sorted { ($0.weekday, $0.kind.rawValue) < ($1.weekday, $1.kind.rawValue) }
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: 8)], spacing: 10) {
            ForEach(templates) { template in
                SkillTemplateCell(template: template,
                                  owned: ownedIndex,
                                  tier: linkTier[template.templateID])
            }
        }
        if let links = snapshot.skillLinks, !links.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("技能连结").font(.headline)
                ForEach(links) { link in
                    HStack(spacing: 6) {
                        Image(systemName: "link")
                            .foregroundStyle(tierColor(link.tier))
                        Text(link.text).font(.caption)
                        Spacer()
                        Text("D\(link.tier.rawValue)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 14))
        } else {
            Text("还没有技能连结：多收集同元素、成相生关系的技能试试。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func tierColor(_ tier: SkillLinkTier) -> Color {
        switch tier {
        case .elementResonance: return .teal
        case .generatingChain: return .green
        case .tripleResonance: return .purple
        case .rarityGlow: return .orange
        }
    }
}

/// 单个模板格：元素符号 + 名称；6 稀有度小格横向排列显示收集进度
private struct SkillTemplateCell: View {
    let template: SkillTemplate
    let owned: [String: DisplaySnapshot.SkillDetail]
    let tier: SkillLinkTier?

    private var elementColor: Color {
        switch SkillElement(label: template.element) {
        case .wood: return .green
        case .fire: return .red
        case .earth: return .brown
        case .metal: return .yellow
        case .water: return .blue
        case .thunder: return .purple
        default: return .secondary
        }
    }

    private var collected: Int {
        (1...6).filter { owned["w\(template.weekday).\(template.kind == .active ? "a" : "p").\($0)"] != nil }.count
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(elementColor.opacity(0.15))
                if let key = template.iconKey {
                    Image(key)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(6)
                } else {
                    Text(template.element)
                        .font(.title3.bold())
                        .foregroundStyle(elementColor)
                }
                if let tier {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(tierGlowColor(tier), lineWidth: 2)
                }
            }
            .frame(height: 52)
            Text(template.name)
                .font(.caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            // 6 稀有度进度点（白→红）
            HStack(spacing: 3) {
                ForEach(1...6, id: \.self) { rarity in
                    let cell = owned["w\(template.weekday).\(template.kind == .active ? "a" : "p").\(rarity)"]
                    Circle()
                        .fill(cell == nil ? Color.secondary.opacity(0.2) : rarityColor(rarity))
                        .frame(width: 7, height: 7)
                        .overlay(
                            Text("\(cell?.level ?? 0)")
                                .font(.system(size: 5, weight: .bold))
                                .foregroundStyle(.white)
                                .opacity(cell == nil ? 0 : 1)
                        )
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(template.element)·\(template.name)，已收集 \(collected)/6")
    }

    private func rarityColor(_ rarity: Int) -> Color {
        switch Rarity(rawValue: rarity) {
        case .green: return .green
        case .blue: return .blue
        case .purple: return .purple
        case .orange: return .orange
        case .red: return .red
        default: return Color(white: 0.35)
        }
    }

    private func tierGlowColor(_ tier: SkillLinkTier) -> Color {
        switch tier {
        case .elementResonance: return .teal
        case .generatingChain: return .green
        case .tripleResonance: return .purple
        case .rarityGlow: return .orange
        }
    }
}

/// 收藏页"图鉴"标签（Phase B）：12 怪物全 roster；
/// 遇见的显示立绘 + 遭遇/胜数，未遇见显示剪影 + "尚未遇见"。
struct BestiaryGrid: View {
    let snapshot: DisplaySnapshot

    private var metIndex: [String: BestiaryEntry] {
        Dictionary(uniqueKeysWithValues: (snapshot.bestiary ?? []).map { ($0.monster.rawValue, $0) })
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                  spacing: 12) {
            ForEach(Monster.allCases, id: \.rawValue) { monster in
                BestiaryCell(monster: monster, entry: metIndex[monster.rawValue])
            }
        }
        Text("遭遇与胜负只与当日骰点运势相关，与属性、装备、技能稀有度无关。")
            .font(.caption2).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BestiaryCell: View {
    let monster: Monster
    let entry: BestiaryEntry?

    private var artName: String? {
        ContentLibrary.shared?.monsterArtKeys[monster.artKey]
    }

    private var elementColor: Color {
        switch monster.element {
        case .wood: return .green
        case .fire: return .red
        case .earth: return .brown
        case .metal: return .yellow
        case .water: return .blue
        case .thunder: return .purple
        }
    }

    private var accessibilityText: String {
        guard let entry else { return "尚未遇见的怪物，\(monster.element.rawValue)属性" }
        return "\(monster.rawValue)，\(monster.element.rawValue)属性，遭遇\(entry.encounters)次，胜\(entry.wins)次"
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(elementColor.opacity(entry == nil ? 0.05 : 0.12))
                if let entry, let artName {
                    Image(artName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(6)
                } else {
                    // 未遇见：剪影 + 问号
                    Image(systemName: "questionmark")
                        .font(.title.bold())
                        .foregroundStyle(.secondary.opacity(0.5))
                }
            }
            .frame(height: 88)
            Text(entry == nil ? "尚未遇见" : monster.rawValue)
                .font(.caption)
                .foregroundStyle(entry == nil ? .secondary : .primary)
            if let entry {
                Text("遭遇 \(entry.encounters) · 胜 \(entry.wins)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                Text(monster.element.rawValue)
                    .font(.caption2)
                    .foregroundStyle(elementColor)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }
}

/// 卡面 3 技能行（Phase B-1：角色卡左列；成链技能按最高档发光，克制技带标记）
struct CardSkillRows: View {
    let skills: [CardSkill]
    let links: [SkillLink]

    private var glowTier: [String: SkillLinkTier] {
        var map: [String: SkillLinkTier] = [:]
        for link in links {
            for id in link.memberTemplateIDs {
                if let existing = map[id], existing.rawValue >= link.tier.rawValue { continue }
                map[id] = link.tier
            }
        }
        return map
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if skills.isEmpty {
                Text("修行中")
                    .font(.caption.italic())
                    .foregroundStyle(.white.opacity(0.7))
            } else {
                ForEach(skills) { skill in
                    HStack(spacing: 5) {
                        if let key = skill.iconKey {
                            Image(key)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 16, height: 16)
                        } else {
                            Text(skill.element)
                                .font(.caption2.bold())
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        Text(skill.name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        if skill.isCounter {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.yellow)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.black.opacity(0.35))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(glowColor(glowTier[skill.templateID]),
                                            lineWidth: glowTier[skill.templateID] == nil ? 0 : 1.5)
                            )
                    )
                }
            }
        }
    }

    private func glowColor(_ tier: SkillLinkTier?) -> Color {
        guard let tier else { return .clear }
        switch tier {
        case .elementResonance: return .teal
        case .generatingChain: return .green
        case .tripleResonance: return .purple
        case .rarityGlow: return .orange
        }
    }
}
