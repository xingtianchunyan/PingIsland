/// 半小时活动结算（真机反馈第二十批规则 v3，单一实现来源）。
///
/// 每满 30 分钟结算一次活动：
/// - 经验加成 = 30 × 骰点 / 10（= 3 × 骰点 XP；每分钟本体成长由引擎按职业体系结算）
/// - 属性 / 装备 / 特质·技能按骰点四档决定（见 resolve 注释），骰 20 额外必得一件高级装备
import Foundation

/// 一次半小时活动的结算结果。
public struct MilestoneGrant: Equatable, Sendable {
    /// 本里程碑经验加成（XP；= 3 × 骰点）
    public var experienceXP: Int
    /// 属性点奖励（基础 CON/INT/DEX 或高级 LUK/WIS/CHA → 点数；无则空）
    public var attributePoints: [Attribute: Int]
    /// 主结果：装备
    public var mainEquipment: EquipmentItem?
    /// 主结果：特质/技能
    public var mainSkill: SkillDraw?
    /// 骰 20 的必得额外装备（其它骰点为 nil）
    public var extraEquipment: EquipmentItem?

    /// 全部新装备（主结果装备 + 额外装备）
    public var allEquipment: [EquipmentItem] {
        [mainEquipment, extraEquipment].compactMap { $0 }
    }
}

public enum MilestoneRules {
    /// 经验加成公式：30 × 骰点 / 10（整除，3 × 骰点 XP）
    public static func experienceBonus(dice: Int) -> Int {
        30 * dice / 10
    }

    /// 按骰点分档结算一次活动。同一 rng 序列结果确定（重试不重抽由调用方按稳定事件身份保证）。
    ///
    /// 分档（行天第二十批规格 v3）：
    /// - 骰点 < 10：装备概率 = 骰点/10（白/绿，白色率 = (10−骰点)/10）；否则基础属性 1~3 点（60/30/10%，CON/INT/DEX）
    /// - 骰点 = 10：50% 装备（白/绿/蓝 60/30/10%），50% 基础属性 1~3 点（60/30/10%）
    /// - 10 < 骰点 < 20：40% 基础属性 3~5 点（60/30/10%）；30% 全六阶装备（40/30/20/8/1.99/0.01%）；
    ///   20% 高级属性 1~3 点（60/30/10%，LUK/WIS/CHA）；10% 白/绿/蓝特质·技能（60/30/10%）
    /// - 骰点 = 20：40% 高级属性 3~5 点（60/30/10%）；30% 装备、30% 特质·技能（均紫/橙/红 80/19/1%）；
    ///   无论主结果是什么，都 100% 额外获得一件紫/橙/红装备（80/19/1%）
    public static func resolve(dice: Int, weekday: Int, equipmentID: inout Int,
                               appearance: String = "布甲",
                               rng: inout some RandomSource) -> MilestoneGrant {
        var grant = MilestoneGrant(experienceXP: experienceBonus(dice: dice),
                                   attributePoints: [:])

        func makeEquipment(_ rarity: Rarity) -> EquipmentItem {
            equipmentID += 1
            return EquipmentRules.generate(id: equipmentID, rarity: rarity,
                                           appearance: appearance, rng: &rng)
        }

        func makeSkill(_ rarity: Rarity) -> SkillDraw {
            let template = SkillRules.template(forWeekday: weekday)
            let isActive = rng.nextInt(upperBound: 2) == 0
            return SkillDraw(
                template: template, rarity: rarity, isActive: isActive,
                passiveValue: isActive ? 0 : SkillRules.passiveValue(rarity: rarity, level: 1),
                weekday: weekday)
        }

        func rollRarity(_ table: [(rarity: Rarity, probability: Double)]) -> Rarity {
            let roll = Double(rng.nextInt(upperBound: 1_000_000)) / 1_000_000.0
            var cumulative = 0.0
            for entry in table {
                cumulative += entry.probability
                if roll < cumulative { return entry.rarity }
            }
            return table.last!.rarity
        }

        /// 60/30/10% 分布roll点数（1-based 档位表）
        func rollPoints(_ table: [(points: Int, probability: Double)]) -> Int {
            let roll = Double(rng.nextInt(upperBound: 1_000_000)) / 1_000_000.0
            var cumulative = 0.0
            for entry in table {
                cumulative += entry.probability
                if roll < cumulative { return entry.points }
            }
            return table.last!.points
        }

        /// 等概率抽一个属性
        func pickAttribute(_ pool: [Attribute]) -> Attribute {
            pool[rng.nextInt(upperBound: pool.count)]
        }

        /// 基础属性包（CON/INT/DEX）
        func grantBaseAttribute(points: Int) {
            grant.attributePoints[pickAttribute(RulesConfig.basePackAttributes)] = points
        }

        /// 高级属性包（LUK/WIS/CHA）
        func grantAdvancedAttribute(points: Int) {
            grant.attributePoints[pickAttribute(RulesConfig.oraclePackAttributes)] = points
        }

        func roll01() -> Double {
            Double(rng.nextInt(upperBound: 1_000_000)) / 1_000_000.0
        }

        if dice < 10 {
            if roll01() < Double(dice) / 10.0 {
                let rarity: Rarity = roll01() < (10.0 - Double(dice)) / 10.0 ? .white : .green
                grant.mainEquipment = makeEquipment(rarity)
            } else {
                grantBaseAttribute(points: rollPoints([
                    (1, 0.60), (2, 0.30), (3, 0.10),
                ]))
            }
        } else if dice == 10 {
            if roll01() < 0.50 {
                grant.mainEquipment = makeEquipment(rollRarity([
                    (.white, 0.60), (.green, 0.30), (.blue, 0.10),
                ]))
            } else {
                grantBaseAttribute(points: rollPoints([
                    (1, 0.60), (2, 0.30), (3, 0.10),
                ]))
            }
        } else if dice < 20 {
            let roll = roll01()
            if roll < 0.40 {
                grantBaseAttribute(points: rollPoints([
                    (3, 0.60), (4, 0.30), (5, 0.10),
                ]))
            } else if roll < 0.70 {
                grant.mainEquipment = makeEquipment(rollRarity([
                    (.white, 0.40), (.green, 0.30), (.blue, 0.20),
                    (.purple, 0.08), (.orange, 0.0199), (.red, 0.0001),
                ]))
            } else if roll < 0.90 {
                grantAdvancedAttribute(points: rollPoints([
                    (1, 0.60), (2, 0.30), (3, 0.10),
                ]))
            } else {
                grant.mainSkill = makeSkill(rollRarity([
                    (.white, 0.60), (.green, 0.30), (.blue, 0.10),
                ]))
            }
        } else {
            // 骰 20：高级属性 40% / 装备 30% / 特质·技能 30%，紫/橙/红池
            let roll = roll01()
            if roll < 0.40 {
                grantAdvancedAttribute(points: rollPoints([
                    (3, 0.60), (4, 0.30), (5, 0.10),
                ]))
            } else if roll < 0.70 {
                grant.mainEquipment = makeEquipment(rollRarity([
                    (.purple, 0.80), (.orange, 0.19), (.red, 0.01),
                ]))
            } else {
                grant.mainSkill = makeSkill(rollRarity([
                    (.purple, 0.80), (.orange, 0.19), (.red, 0.01),
                ]))
            }
            // 额外装备必得（紫/橙/红池）——独立日记记录，不占主结果
            grant.extraEquipment = makeEquipment(rollRarity([
                (.purple, 0.80), (.orange, 0.19), (.red, 0.01),
            ]))
        }
        return grant
    }

    /// 主结果的人类可读摘要（日记 rewardSummary 用）。
    public static func describe(_ grant: MilestoneGrant) -> String {
        var parts: [String] = []
        if grant.experienceXP > 0 { parts.append("经验 +\(grant.experienceXP)") }
        if !grant.attributePoints.isEmpty {
            for (attr, points) in grant.attributePoints.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
                parts.append("属性 +\(points) \(attr.rawValue)")
            }
        }
        if let item = grant.mainEquipment {
            parts.append("装备·\(rarityName(item.rarity))\(item.slot.rawValue)（评 \(item.totalValue)）")
        }
        if let skill = grant.mainSkill {
            let name = skill.isActive ? skill.template.activeName : skill.template.passiveName
            // 主动 = 技能，被动 = 特质（行天第二十一批口径）
            parts.append("\(skill.isActive ? "技能" : "特质")·\(name)（\(rarityName(skill.rarity))）")
        }
        return parts.isEmpty ? "平稳的半小时" : parts.joined(separator: "，")
    }

    /// 骰 20 额外装备的日记摘要（nil = 本活动无额外装备）。
    public static func describeExtra(_ grant: MilestoneGrant) -> String? {
        guard let item = grant.extraEquipment else { return nil }
        return "额外装备·\(rarityName(item.rarity))\(item.slot.rawValue)（评 \(item.totalValue)）"
    }

    private static func rarityName(_ rarity: Rarity) -> String {
        switch rarity {
        case .white: return "白"
        case .green: return "绿"
        case .blue: return "蓝"
        case .purple: return "紫"
        case .orange: return "橙"
        case .red: return "红"
        }
    }
}
