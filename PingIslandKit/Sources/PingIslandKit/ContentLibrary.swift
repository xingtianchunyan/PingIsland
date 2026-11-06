/// 内容库（特质/技能模板 + 美术资产键映射）。
/// 单一实现来源：`Content/ContentLibrary.json`。
/// 规则数值仍以 `SkillRules` / `RulesConfig` 为准；本库只做内容与展示定义。
import Foundation

/// 技能种类：主动（只影响演出）/ 被动（六项固定加成）
public enum SkillKind: String, Codable, Sendable {
    case active
    case passive
}

/// 一个内容模板（12 个：6 元素 × 主动/被动），每个模板 6 个稀有度变体。
public struct SkillTemplate: Codable, Equatable, Sendable, Identifiable {
    public var templateID: String
    /// 周模板归属：1=周一 … 6=周六/周日（周六、周日同为雷，归一化到 6，与 SkillRules 一致）
    public var weekday: Int
    public var element: String
    public var kind: SkillKind
    public var name: String
    /// 被动模板对应的属性（主动为 nil）
    public var attribute: Attribute?
    /// 资产目录中的图标名（Assets.xcassets imageset 名）
    public var iconKey: String?
    /// 主动演出的姿态关键帧名
    public var poseKey: String?
    /// 六个稀有度变体（rarity 1...6 全覆盖）
    public var variants: [SkillVariant]

    public var id: String { templateID }
}

/// 单个稀有度变体：名称与描述文案。数值由规则层推导，不在此重复。
public struct SkillVariant: Codable, Equatable, Sendable {
    public var rarity: Rarity
    public var name: String
    public var desc: String
}

/// 装备外观层级 → 图标键
public enum AppearanceTier: String, CaseIterable, Codable, Sendable {
    case cloth, leather, iron, mech
}

public struct ContentLibrary: Codable, Equatable, Sendable {
    public struct EquipmentIcons: Codable, Equatable, Sendable {
        public var cloth: String
        public var leather: String
        public var iron: String
        public var mech: String

        public func key(for tier: AppearanceTier) -> String {
            switch tier {
            case .cloth: return cloth
            case .leather: return leather
            case .iron: return iron
            case .mech: return mech
            }
        }
    }

    public var version: Int
    public var skills: [SkillTemplate]
    /// 装备图标键：slot（内部 key）→ 外观层级
    public var equipmentIconKeys: [String: EquipmentIcons]
    /// 职业立绘键：CharacterClass raw key → imageset 名
    public var classArtKeys: [String: String]
    /// 疲劳关键帧键（对应 Fatigue 阶段）
    public var fatigueArtKeys: [String: String]
    public var nightSleepArtKey: String
    public var monsterArtKeys: [String: String]
    public var appIconKey: String

    // MARK: - 查找

    /// 按星期 + 种类取当日模板（与 SkillRules.template(forWeekday:) 对应）。
    /// 周日（7）与周六同为雷，归一化到 6 再查——JSON 只存 12 模板，周日收藏项也能命中。
    public func skill(weekday: Int, kind: SkillKind) -> SkillTemplate? {
        let normalized = (weekday == 7) ? 6 : weekday
        return skills.first { $0.weekday == normalized && $0.kind == kind }
    }

    public func skill(templateID: String) -> SkillTemplate? {
        skills.first { $0.templateID == templateID }
    }

    /// 收藏项（星期+种类+稀有度）的展示变体
    public func variant(weekday: Int, kind: SkillKind, rarity: Rarity) -> SkillVariant? {
        skill(weekday: weekday, kind: kind)?.variants.first { $0.rarity == rarity }
    }

    public func equipmentIcon(slot: EquipmentSlot, tier: AppearanceTier) -> String? {
        let slotKey: String
        switch slot {
        case .head: slotKey = "head"
        case .body: slotKey = "body"
        case .legs: slotKey = "legs"
        case .feet: slotKey = "feet"
        }
        return equipmentIconKeys[slotKey]?.key(for: tier)
    }

    public func classArt(_ characterClass: CharacterClass) -> String? {
        let key: String
        switch characterClass {
        case .bard: key = "bard"
        case .archmage: key = "archmage"
        case .gladiator: key = "gladiator"
        case .oracle: key = "oracle"
        case .wanderArtist: key = "wanderArtist"
        case .alchemist: key = "alchemist"
        case .monk: key = "monk"
        case .ranger: key = "ranger"
        }
        return classArtKeys[key]
    }

    // MARK: - 加载

    /// JSON 在源码树中的位置（SwiftPM 目标内相对本文件）。
    /// Windows 工具链的 SwiftPM 资源处理不可用（实测 6.4.2 报 WindowsError 4551），
    /// 因此资源不经 SwiftPM bundle，按三级回退定位：
    /// 1) App 主 bundle（iOS：经 project.yml 把 JSON 打包进 App 资源）；
    /// 2) 源码树相对路径（SwiftPM on Windows/macOS 测试均可命中）。
    private static var sourceTreeJSON: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()          // Sources/PingIslandKit/
            .appendingPathComponent("Content/ContentLibrary.json")
    }

    /// 加载内容库 JSON 并做结构校验；文件缺失或校验失败返回 nil（调用方可降级为占位 SF Symbol）。
    public static func load() -> ContentLibrary? {
        let url = Bundle.main.url(forResource: "ContentLibrary", withExtension: "json") ?? sourceTreeJSON
        guard let data = try? Data(contentsOf: url),
              let library = try? JSONDecoder().decode(ContentLibrary.self, from: data) else { return nil }
        return library.isValid ? library : nil
    }

    /// 共享单例（内容只读；加载失败为 nil，UI 层负责降级）。
    public static let shared: ContentLibrary? = load()

    // MARK: - 校验（与测试共享同一实现）

    /// 结构完整性：12 模板、每模板 6 变体覆盖全部稀有度、名称与 SkillRules 一致、
    /// 模板 ID 唯一、被动模板属性非空、图标键非空、全部键值无重复 imageset 名。
    public var isValid: Bool {
        guard skills.count == 12 else { return false }
        guard Set(skills.map(\.templateID)).count == 12 else { return false }
        for template in skills {
            guard (1...7).contains(template.weekday) else { return false }
            guard Set(template.variants.map(\.rarity)) == Set(Rarity.allCases) else { return false }
            guard template.variants.allSatisfy({ !$0.name.isEmpty && !$0.desc.isEmpty }) else { return false }
            let day = SkillRules.template(forWeekday: template.weekday)
            let expectedName = template.kind == .active ? day.activeName : day.passiveName
            guard template.name == expectedName else { return false }
            if template.kind == .passive {
                guard let attr = template.attribute, attr == day.passiveAttribute else { return false }
            } else {
                guard template.attribute == nil else { return false }
            }
            guard let icon = template.iconKey, !icon.isEmpty else { return false }
            if template.kind == .active, template.poseKey == nil { return false }
        }
        // 装备 4 部位 × 4 外观
        guard equipmentIconKeys.count == 4 else { return false }
        for slot in ["head", "body", "legs", "feet"] {
            guard equipmentIconKeys[slot] != nil else { return false }
        }
        guard classArtKeys.count == 8, fatigueArtKeys.count == 5 else { return false }
        // imageset 键不重复
        var keys: Set<String> = []
        for s in skills { if s.iconKey != nil { keys.insert(s.iconKey!) } }
        for e in equipmentIconKeys.values { keys.insert(e.cloth); keys.insert(e.leather); keys.insert(e.iron); keys.insert(e.mech) }
        keys.formUnion(classArtKeys.values)
        keys.formUnion(fatigueArtKeys.values)
        keys.insert(nightSleepArtKey)
        keys.formUnion(monsterArtKeys.values)
        guard !keys.contains("") else { return false }
        return true
    }
}
