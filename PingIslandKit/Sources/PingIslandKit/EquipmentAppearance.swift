/// 装备外观（执行文档 9.5 + 真机反馈第二十一批修订）：
/// 外观类型决定词条数值倍率（布×1 / 皮×4 / 铁×16 / 机×64，每一档×4），
/// 生成时按最终 WIS 定型并随装备入库；不重复生成装备。
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

    /// 外观类型 → 词条数值倍率（行天第二十一批：布为基础值，皮×4、铁×16、机甲×64）
    public static func valueMultiplier(type: String) -> Int {
        switch type {
        case "机甲": return 64
        case "铁甲": return 16
        case "皮甲": return 4
        default: return 1 // 布甲
        }
    }

    /// 外观类型 → 档位序（换装比较用：机甲 > 铁甲 > 皮甲 > 布甲）
    public static func tierRank(type: String) -> Int {
        switch type {
        case "机甲": return 3
        case "铁甲": return 2
        case "皮甲": return 1
        default: return 0 // 布甲
        }
    }
}
