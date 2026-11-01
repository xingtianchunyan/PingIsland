/// 技能收藏账本（执行文档 9.6）：同一模板＋同一稀有度为同一收藏项，
/// 重复获得升等级（上限 Lv5），Lv5 后再重复按稀有度转化为属性点数。
import Foundation

public struct SkillCollectionItem: Equatable, Codable, Sendable, Identifiable {
    /// 周模板（1=周一 … 7=周日）
    public var weekday: Int
    /// 主动/被动
    public var isActive: Bool
    public var rarity: Rarity
    /// 1...5
    public var level: Int
    public var id: String { "w\(weekday).\(isActive ? "a" : "p").\(rarity.rawValue)" }
}

public enum SkillCollectionOutcome: Equatable, Sendable {
    case newItem(SkillCollectionItem)
    case leveledUp(SkillCollectionItem)
    /// Lv5 后重复：转化为 (点数, 属性池)
    case converted(points: Int, pool: [Attribute])
}

public struct SkillCollection: Equatable, Codable, Sendable {
    public private(set) var items: [SkillCollectionItem]

    public init(items: [SkillCollectionItem] = []) {
        self.items = items
    }

    /// 收藏项身份：模板（星期+主被动）＋稀有度
    private func identity(of draw: SkillDraw) -> String {
        SkillCollectionItem(weekday: draw.weekday, isActive: draw.isActive,
                            rarity: draw.rarity, level: 1).id
    }

    /// 收入一次抽选结果。
    @discardableResult
    public mutating func add(_ draw: SkillDraw) -> SkillCollectionOutcome {
        let identity = identity(of: draw)
        if let index = items.firstIndex(where: { $0.id == identity }) {
            if items[index].level < 5 {
                items[index].level += 1
                return .leveledUp(items[index])
            }
            return .converted(points: SkillRules.duplicateConversionPoints(rarity: draw.rarity),
                              pool: SkillRules.duplicateConversionPool(rarity: draw.rarity))
        }
        let item = SkillCollectionItem(weekday: draw.weekday, isActive: draw.isActive,
                                       rarity: draw.rarity, level: 1)
        items.append(item)
        return .newItem(item)
    }
}
