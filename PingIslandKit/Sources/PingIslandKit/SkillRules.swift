/// 六行与效果模板（执行文档 9.6）：MVP 共 12 个模板，每模板六种稀有度变体。
/// 主动技能只影响演出；被动首版只实现六项固定加成。
public enum SkillRules {
    /// 某日模板：六行 / 主动名 / 被动名 / 被动属性
    public struct DayTemplate: Equatable, Sendable {
        public var element: String
        public var activeName: String
        public var passiveName: String
        public var passiveAttribute: Attribute
    }

    /// weekday：1=周一 … 7=周日（周六、周日同为雷）
    public static func template(forWeekday weekday: Int) -> DayTemplate {
        switch weekday {
        case 1: return DayTemplate(element: "木", activeName: "藤蔓挥舞",
                                   passiveName: "林地体魄", passiveAttribute: .con)
        case 2: return DayTemplate(element: "火", activeName: "火球闪现",
                                   passiveName: "火焰学识", passiveAttribute: .int)
        case 3: return DayTemplate(element: "土", activeName: "岩盾升起",
                                   passiveName: "稳健步伐", passiveAttribute: .dex)
        case 4: return DayTemplate(element: "金", activeName: "金刃掠过",
                                   passiveName: "寻宝直觉", passiveAttribute: .luk)
        case 5: return DayTemplate(element: "水", activeName: "冰晶涟漪",
                                   passiveName: "静水明悟", passiveAttribute: .wis)
        default: return DayTemplate(element: "雷", activeName: "连锁电弧",
                                    passiveName: "风暴感召", passiveAttribute: .cha)
        }
    }

    /// 等级倍率（Lv1~Lv5）
    public static let levelMultipliers: [Double] = [1.0, 1.3, 1.5, 1.65, 1.8]

    /// 被动数值：Lv1 ＝稀有度序号，再乘等级倍率（四舍五入）
    public static func passiveValue(rarity: Rarity, level: Int) -> Int {
        let clamped = min(max(level, 1), levelMultipliers.count)
        let value = Double(rarity.rawValue) * levelMultipliers[clamped - 1]
        return Int(value.rounded())
    }

    /// Lv5 后重复：白/绿/蓝 → 1/2/3 点随机 CON/INT/DEX；紫/橙/红 → 4/5/6 点随机 LUK/WIS/CHA
    public static func duplicateConversionPoints(rarity: Rarity) -> Int {
        rarity.rawValue
    }

    public static func duplicateConversionPool(rarity: Rarity) -> [Attribute] {
        switch rarity {
        case .white, .green, .blue:
            return [.con, .int, .dex]
        case .purple, .orange, .red:
            return [.luk, .wis, .cha]
        }
    }
}
