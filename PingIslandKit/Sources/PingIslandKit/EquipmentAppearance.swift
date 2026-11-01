/// 装备外观（执行文档 9.5）：外观阶段只影响展示，不改词条和稀有度，不重复生成装备。
public enum EquipmentAppearance {
    /// 外观等级 = 1 + floor(最终智慧 / 50)
    public static func appearanceTier(finalWisdom: Int) -> Int {
        1 + max(0, finalWisdom) / 50
    }

    /// 外观等级 → 类型（1~50 布甲；51~150 皮甲；151~300 铁甲；301+ 机甲）
    public static func appearanceType(tier: Int) -> String {
        switch tier {
        case ...50: return "布甲"
        case 51...150: return "皮甲"
        case 151...300: return "铁甲"
        default: return "机甲"
        }
    }

    /// 便捷合成：最终智慧 → 外观类型
    public static func appearanceType(finalWisdom: Int) -> String {
        appearanceType(tier: appearanceTier(finalWisdom: finalWisdom))
    }
}
