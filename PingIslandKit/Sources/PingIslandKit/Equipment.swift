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

    public var totalValue: Int { affixes.reduce(0) { $0 + $1.value } }

    public init(id: Int, slot: EquipmentSlot, rarity: Rarity, affixes: [Affix],
                isEquipped: Bool, acquiredAt: Date? = nil, origin: String? = nil) {
        self.id = id
        self.slot = slot
        self.rarity = rarity
        self.affixes = affixes
        self.isEquipped = isEquipped
        self.acquiredAt = acquiredAt
        self.origin = origin
    }

    private enum CodingKeys: String, CodingKey {
        case id, slot, rarity, affixes, isEquipped, acquiredAt, origin
    }

    /// 旧版本存档无 acquiredAt/origin 键：按 nil 兼容解码，其余字段照原要求
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        slot = try c.decode(EquipmentSlot.self, forKey: .slot)
        rarity = try c.decode(Rarity.self, forKey: .rarity)
        affixes = try c.decode([Affix].self, forKey: .affixes)
        isEquipped = try c.decode(Bool.self, forKey: .isEquipped)
        acquiredAt = try c.decodeIfPresent(Date.self, forKey: .acquiredAt)
        origin = try c.decodeIfPresent(String.self, forKey: .origin)
    }
}

public enum EquipmentRules {
    /// 生成一件装备。同一 rng 序列结果确定；重试不重抽由调用方按稳定事件身份保证。
    public static func generate(id: Int, rarity: Rarity,
                                rng: inout some RandomSource) -> EquipmentItem {
        let spec = RulesConfig.equipmentTable[rarity]!
        let slot = EquipmentSlot.allCases[rng.nextInt(upperBound: EquipmentSlot.allCases.count)]

        // 基础词条：从 CON/INT/DEX 不重复抽取
        var basePool = RulesConfig.basePackAttributes
        var affixes: [Affix] = []
        for _ in 0..<spec.base {
            let idx = rng.nextInt(upperBound: basePool.count)
            affixes.append(Affix(attribute: basePool.remove(at: idx), value: spec.value))
        }
        // 高级词条：从 LUK/WIS/CHA 不重复抽取
        var advPool = RulesConfig.oraclePackAttributes
        for _ in 0..<spec.advanced {
            let idx = rng.nextInt(upperBound: advPool.count)
            affixes.append(Affix(attribute: advPool.remove(at: idx), value: spec.value))
        }
        return EquipmentItem(id: id, slot: slot, rarity: rarity, affixes: affixes, isEquipped: false)
    }

    /// 自动择优：只与同部位当前装备比较。
    /// 等阶更高优先 → 等阶相同则词条数值总和高者优先 → 完全相同保留旧装备。
    /// - 返回：是否应换上新装备
    public static func shouldEquip(newItem: EquipmentItem, current: EquipmentItem?) -> Bool {
        guard let current else { return true }
        if newItem.slot != current.slot { return true } // 不同部位各自独立比较
        if newItem.rarity != current.rarity { return newItem.rarity > current.rarity }
        if newItem.totalValue != current.totalValue { return newItem.totalValue > current.totalValue }
        return false // 完全相同保留旧装备
    }
}
