/// 单次探索的原子顺序与魅力追加（执行文档 9.2/9.3）。
/// 展示与结算分离：本模块只做纯规则计算，副作用（账本写入）由调用方在事务内统一提交。

public struct ExplorationReward: Equatable, Codable, Sendable {
    public var kind: RewardKind
    public var rarity: Rarity
    public var equipment: [EquipmentItem] // 0~2 件
    public var attributePoints: [Attribute: Int]
    /// 魅力追加是否触发（原奖励非装备时最多 1 件；原奖励是装备时最多共 2 件）
    public var charmExtraTriggered: Bool
}

public enum ExplorationRules {
    /// 魅力追加概率 = min(1, max(0, 探索开始时的最终魅力) / 10000)，每次探索最多 1 件
    public static func charmExtraChance(finalCharm: Int) -> Double {
        min(1, max(0, Double(finalCharm)) / Double(RulesConfig().charmDivisor))
    }

    /// 执行一次探索的全部抽奖（冻结快照由调用方在进入前完成）。
    /// - dice: 当日骰点
    /// - finalCharm: 探索开始时的最终魅力（快照）
    /// - equipmentIDGenerator: 装备 id 分配闭包，由账本保证唯一
    public static func resolve(dice: Int, finalCharm: Int,
                               equipmentID: inout Int,
                               rng: inout some RandomSource) -> ExplorationReward {
        let kind = rollExplorationRewardKind(dice: dice, rng: &rng)
        var reward = ExplorationReward(kind: kind, rarity: .white,
                                       equipment: [], attributePoints: [:],
                                       charmExtraTriggered: false)

        switch kind {
        case .attributePack:
            reward.rarity = rollExplorationRarity(dice: dice, rng: &rng)
            let amount = rng.nextInt(lowerBound: 1, upperBound: 3)
            let attr = RulesConfig.basePackAttributes[rng.nextInt(upperBound: RulesConfig.basePackAttributes.count)]
            reward.attributePoints[attr] = amount
            // 骰点 20 的高级属性包
            if dice >= 20 {
                let hi = rng.nextInt(lowerBound: 5, upperBound: 10)
                let hiAttr = RulesConfig.oraclePackAttributes[rng.nextInt(upperBound: RulesConfig.oraclePackAttributes.count)]
                reward.attributePoints[hiAttr, default: 0] += hi
            }
        case .equipment:
            reward.rarity = rollExplorationRarity(dice: dice, rng: &rng)
            equipmentID += 1
            reward.equipment.append(EquipmentRules.generate(id: equipmentID, rarity: reward.rarity, rng: &rng))
        case .activeSkill, .passiveSkill:
            // 技能从当日六行池抽取模板；模板表在内容阶段接入，此处只定稀有度
            reward.rarity = rollExplorationRarity(dice: dice, rng: &rng)
        }

        // 魅力追加（最多 1 件；新装备不提高本次追加概率；追加不再触发追加）
        let chance = charmExtraChance(finalCharm: finalCharm)
        let roll = Double(rng.nextInt(upperBound: 1_000_000)) / 1_000_000.0
        if roll < chance {
            equipmentID += 1
            let extraRarity = rollExplorationRarity(dice: dice, rng: &rng)
            reward.equipment.append(EquipmentRules.generate(id: equipmentID, rarity: extraRarity, rng: &rng))
            reward.charmExtraTriggered = true
        }
        return reward
    }
}
