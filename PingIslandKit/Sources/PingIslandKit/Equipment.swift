import Foundation

/// 装备生成与自动择优（执行文档 9.4）。

public struct Affix: Equatable, Codable, Sendable {
    public var attribute: Attribute
    public var value: Int
}

public struct EquipmentItem: Equatable, Codable, Sendable, Identifiable {
    public var id: Int
    public var slot: EquipmentSlot
    public var rarity: Rarity
    /// 词条：基础词条取自 CON/INT/DEX 不重复；高级词条取自 LUK/WIS/CHA 不重复
    public var affixes: [Affix]
    /// 是否当前装备（自动择优结果）
    public var isEquipped: Bool
    /// 获得时间（首次入账时记录，展示"从何时获得"）
    public var acquiredAt: Date?
    /// 获得原因（如"探索获得"，展示"因何事获得"）
    public var origin: String?
    /// 外观类型覆盖（布甲/皮甲/铁甲/机甲；nil = 按最终 WIS 推导，调试注入用）
    public var appearanceOverride: String?
    /// 生成时定型的外观类型（第二十一批：外观决定数值倍率，随装备入库；
    /// 旧存档无此键 → nil，展示回退 appearanceOverride / 最终 WIS 推导）
    public var appearance: String?

    public var totalValue: Int { affixes.reduce(0) { $0 + $1.value } }

    public init(id: Int, slot: EquipmentSlot, rarity: Rarity, affixes: [Affix],
                isEquipped: Bool, acquiredAt: Date? = nil, origin: String? = nil,
                appearanceOverride: String? = nil, appearance: String? = nil) {
        self.id = id
        self.slot = slot
        self.rarity = rarity
        self.affixes = affixes
        self.isEquipped = isEquipped
        self.acquiredAt = acquiredAt
        self.origin = origin
        self.appearanceOverride = appearanceOverride
        self.appearance = appearance
    }

    private enum CodingKeys: String, CodingKey {
        case id, slot, rarity, affixes, isEquipped, acquiredAt, origin, appearanceOverride
        case appearance
    }

    /// 旧版本存档无 acquiredAt/origin/appearanceOverride 键：按 nil 兼容解码，其余字段照原要求
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        slot = try c.decode(EquipmentSlot.self, forKey: .slot)
        rarity = try c.decode(Rarity.self, forKey: .rarity)
        affixes = try c.decode([Affix].self, forKey: .affixes)
        isEquipped = try c.decode(Bool.self, forKey: .isEquipped)
        acquiredAt = try c.decodeIfPresent(Date.self, forKey: .acquiredAt)
        origin = try c.decodeIfPresent(String.self, forKey: .origin)
        appearanceOverride = try c.decodeIfPresent(String.self, forKey: .appearanceOverride)
        appearance = try c.decodeIfPresent(String.self, forKey: .appearance)
    }
}

public enum EquipmentRules {
    /// 生成一件装备。同一 rng 序列结果确定；重试不重抽由调用方按稳定事件身份保证。
    /// 外观默认布甲（倍率 1，行为同旧版）；调用方传入按 WIS 推导的外观则词条数值按外观倍率放大。
    public static func generate(id: Int, rarity: Rarity,
                                rng: inout some RandomSource) -> EquipmentItem {
        let slot = EquipmentSlot.allCases[rng.nextInt(upperBound: EquipmentSlot.allCases.count)]
        return generate(id: id, slot: slot, rarity: rarity, rng: &rng)
    }

    /// 指定部位生成（第二十批调试注入用）：词条仍按品质表从固定池不重复抽取
    public static func generate(id: Int, slot: EquipmentSlot, rarity: Rarity,
                                rng: inout some RandomSource) -> EquipmentItem {
        generate(id: id, slot: slot, rarity: rarity, appearance: "布甲", rng: &rng)
    }

    /// 指定部位与外观生成（第二十一批）：词条数值 = 品质表基础值 × 外观倍率
    /// （布×1 / 皮×4 / 铁×16 / 机×64），外观随装备入库
    public static func generate(id: Int, slot: EquipmentSlot, rarity: Rarity,
                                appearance: String,
                                rng: inout some RandomSource) -> EquipmentItem {
        let spec = RulesConfig.equipmentTable[rarity]!
        let value = spec.value * EquipmentAppearance.valueMultiplier(type: appearance)

        // 基础词条：从 CON/INT/DEX 不重复抽取
        var basePool = RulesConfig.basePackAttributes
        var affixes: [Affix] = []
        for _ in 0..<spec.base {
            let idx = rng.nextInt(upperBound: basePool.count)
            affixes.append(Affix(attribute: basePool.remove(at: idx), value: value))
        }
        // 高级词条：从 LUK/WIS/CHA 不重复抽取
        var advPool = RulesConfig.oraclePackAttributes
        for _ in 0..<spec.advanced {
            let idx = rng.nextInt(upperBound: advPool.count)
            affixes.append(Affix(attribute: advPool.remove(at: idx), value: value))
        }
        return EquipmentItem(id: id, slot: slot, rarity: rarity, affixes: affixes,
                             isEquipped: false, appearance: appearance)
    }

    /// 自动择优 v2（真机反馈第二十一批）：
    /// ① 高稀有度优先（红色极难获得，不轻易被低阶覆盖）；
    /// ② 同稀有度比数值总值，高者胜；
    /// ③ 跨稀有度仅当新装备外观档位更高（皮/铁/机甲）且数值 ≥ 当前 ×2 时才允许低阶覆盖高阶
    ///    （例：数值翻倍的蓝色铁甲可以顶替紫色布甲）。
    /// - 返回：是否应换上新装备
    public static func shouldEquip(newItem: EquipmentItem, current: EquipmentItem?) -> Bool {
        guard let current else { return true }
        if newItem.slot != current.slot { return true } // 不同部位各自独立比较
        if newItem.rarity != current.rarity {
            if newItem.rarity > current.rarity { return true }
            let newTier = EquipmentAppearance.tierRank(
                type: newItem.appearanceOverride ?? newItem.appearance ?? "布甲")
            let curTier = EquipmentAppearance.tierRank(
                type: current.appearanceOverride ?? current.appearance ?? "布甲")
            return newTier > curTier && newItem.totalValue >= current.totalValue * 2
        }
        if newItem.totalValue != current.totalValue { return newItem.totalValue > current.totalValue }
        return false // 完全相同保留旧装备
    }
}
