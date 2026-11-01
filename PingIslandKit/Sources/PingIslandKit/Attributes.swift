/// 初始属性（执行文档 8.2）：六项各 1 点共 6 点，剩余 4 点按倾向权重逐点随机分配，总计 10 点。

/// 计算各属性的随机分配权重。
/// - 每个非空修行组为其倾向属性贡献 +2 权重，基础权重 1；
/// - “其他”组倾向平均：不叠加单一属性（其权重按其他组处理）；
/// - 无有效选择（空数组）时六项等权。
public func initialAttributeWeights(groups: [TrainingGroup]) -> [Attribute: Int] {
    var weights = [Attribute: Int]()
    for attr in Attribute.allCases { weights[attr] = 1 }
    for group in groups where !groups.isEmpty {
        if group == .other { continue } // “其他”倾向平均到六项：基础权重即等权
        weights[group.inclination, default: 1] += 2
    }
    return weights
}

/// 逐点随机分配 4 点；返回六项总值恰好 10 点（每项 ≥ 1）
public func rollInitialAttributes(groups: [TrainingGroup],
                                  rng: inout some RandomSource) -> [Attribute: Int] {
    let weights = initialAttributeWeights(groups: groups)
    var result = [Attribute: Int]()
    for attr in Attribute.allCases { result[attr] = 1 }
    let attrs = Attribute.allCases
    for _ in 0..<4 {
        let w = attrs.map { weights[$0, default: 1] }
        let picked = attrs[rng.pickWeighted(w)]
        result[picked, default: 1] += 1
    }
    return result
}

/// 面板属性推导（执行文档 8.4，纯函数，不写回永久底值）：
/// 最终属性 = floor((底值 + 装备固定 + 被动固定) × (1 + 被动百分比之和))
public struct PanelInput: Equatable, Sendable {
    public var baseValues: [Attribute: Int]
    public var equipmentFlat: [Attribute: Int]
    public var passiveFlat: [Attribute: Int]
    /// 被动百分比之和，定点 0.1（如 15 = +15%）
    public var passivePercentTenthsSum: Int

    public init(baseValues: [Attribute: Int] = [:],
                equipmentFlat: [Attribute: Int] = [:],
                passiveFlat: [Attribute: Int] = [:],
                passivePercentTenthsSum: Int = 0) {
        self.baseValues = baseValues
        self.equipmentFlat = equipmentFlat
        self.passiveFlat = passiveFlat
        self.passivePercentTenthsSum = passivePercentTenthsSum
    }
}

public func finalAttributes(input: PanelInput) -> [Attribute: Int] {
    var out = [Attribute: Int]()
    for attr in Attribute.allCases {
        let sum = input.baseValues[attr, default: 0]
            + input.equipmentFlat[attr, default: 0]
            + input.passiveFlat[attr, default: 0]
        let scaled = sum * (100 + input.passivePercentTenthsSum)
        out[attr] = max(0, scaled / 100)
    }
    return out
}

/// 装备外观等级（执行文档 9.5）：1 + floor(最终智慧 / 50)
public enum ArmorAppearance: String, Sendable {
    case cloth = "布甲"
    case leather = "皮甲"
    case iron = "铁甲"
    case mech = "机甲"

    public static func forWisdom(_ wisdom: Int) -> ArmorAppearance {
        let level = 1 + wisdom / 50
        switch level {
        case 1...50: return .cloth
        case 51...150: return .leather
        case 151...300: return .iron
        default: return .mech
        }
    }
}
