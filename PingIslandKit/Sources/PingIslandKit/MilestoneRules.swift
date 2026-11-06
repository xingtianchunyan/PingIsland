/// 半小时活动结算（真机反馈第十九批规则 v2，单一实现来源）。
///
/// 每满 30 分钟结算一次活动：
/// - 经验加成 = 30 × 骰点 / 10（= 3 × 骰点 XP；每分钟本体成长固定 1 XP，由引擎结算）
/// - 装备 / 特质·技能按骰点分档决定（见 resolve 注释），骰 20 额外必得一件高级装备
import Foundation

/// 一次半小时活动的结算结果。
public struct MilestoneGrant: Equatable, Sendable {
    /// 本里程碑经验加成（XP；= 3 × 骰点）
    public var experienceXP: Int
    /// 主结果：装备（骰 20 且主结果判为装备时为第二件之前的那件）
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
    /// 分档（行天第十九批规格）：
    /// - 骰点 < 10：只有白/绿装备；获得概率 = 骰点/10；获得时白色概率 = (10−骰点)/10，其余为绿色
    /// - 骰点 = 10：必得白/绿/蓝装备，概率 60% / 30% / 10%
    /// - 10 < 骰点 < 20：70% 得全六阶装备（40/30/20/8/1.99/0.01%），
    ///   30% 得白/绿/蓝特质·技能（60/30/10%）
    /// - 骰点 = 20：装备与特质·技能各 50%，池为紫/橙/红（80/19/1%）；
    ///   无论主结果是什么，都 100% 额外获得一件紫/橙/红装备（80/19/1%）
    public static func resolve(dice: Int, weekday: Int, equipmentID: inout Int,
                               rng: inout some RandomSource) -> MilestoneGrant {
        var grant = MilestoneGrant(experienceXP: experienceBonus(dice: dice))

        func makeEquipment(_ rarity: Rarity) -> EquipmentItem {
            equipmentID += 1
            return EquipmentRules.generate(id: equipmentID, rarity: rarity, rng: &rng)
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

        if dice < 10 {
            let d = Double(dice)
            if Double(rng.nextInt(upperBound: 1_000_000)) / 1_000_000.0 < d / 10.0 {
                let rarity: Rarity = Double(rng.nextInt(upperBound: 1_000_000)) / 1_000_000.0
                    < (10.0 - d) / 10.0 ? .white : .green
                grant.mainEquipment = makeEquipment(rarity)
            }
        } else if dice == 10 {
            grant.mainEquipment = makeEquipment(rollRarity([
                (.white, 0.60), (.green, 0.30), (.blue, 0.10),
            ]))
        } else if dice < 20 {
            let roll = Double(rng.nextInt(upperBound: 1_000_000)) / 1_000_000.0
            if roll < 0.70 {
                grant.mainEquipment = makeEquipment(rollRarity([
                    (.white, 0.40), (.green, 0.30), (.blue, 0.20),
                    (.purple, 0.08), (.orange, 0.0199), (.red, 0.0001),
                ]))
            } else {
                grant.mainSkill = makeSkill(rollRarity([
                    (.white, 0.60), (.green, 0.30), (.blue, 0.10),
                ]))
            }
        } else {
            // 骰 20：主结果装备/技能各 50%，紫/橙/红池
            let mainIsEquipment = rng.nextInt(upperBound: 2) == 0
            let rarity = rollRarity([
                (.purple, 0.80), (.orange, 0.19), (.red, 0.01),
            ])
            if mainIsEquipment {
                grant.mainEquipment = makeEquipment(rarity)
            } else {
                grant.mainSkill = makeSkill(rarity)
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
        if let item = grant.mainEquipment {
            parts.append("装备·\(rarityName(item.rarity))\(item.slot.rawValue)（评 \(item.totalValue)）")
        }
        if let skill = grant.mainSkill {
            let name = skill.isActive ? skill.template.activeName : skill.template.passiveName
            parts.append("\(skill.isActive ? "特质" : "技能")·\(name)（\(rarityName(skill.rarity))）")
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
