import FamilyControls
import Foundation

/// 八修行组选择（执行文档 5.2）。
/// 一个 App token 只能属于一个组；分组是用户自定的游戏映射，不推断真实用途；
/// 不展示、不上传真实 App 名称与 token（仅以 token 集合存储在共享容器）。
public enum GroupSelection {
    /// 页面顺序（与文档 5.2 表格一致）
    public static let orderedGroups: [TrainingGroup] = [
        .social, .productivity, .games, .reading,
        .entertainment, .shopping, .health, .other,
    ]

    public struct State: Codable, Equatable {
        public var version: Int = 1
        /// 仅持久化非空组
        public var selections: [String: FamilyActivitySelection] = [:]

        public init() {}

        public func selection(for group: TrainingGroup) -> FamilyActivitySelection {
            selections[group.rawValue] ?? FamilyActivitySelection()
        }

        public var nonEmptyGroups: [TrainingGroup] {
            GroupSelection.orderedGroups.filter {
                let s = selection(for: $0)
                return !s.applicationTokens.isEmpty || !s.categoryTokens.isEmpty
                    || !s.webDomainTokens.isEmpty
            }
        }
    }

    private static let key = "groupSelection.v1"

    public static func load() -> State {
        guard let data = SharedStore.defaults?.data(forKey: key),
              let state = try? JSONDecoder().decode(State.self, from: data)
        else { return State() }
        return state
    }

    public static func save(_ state: State) {
        var s = state
        s.version += 1
        if let data = try? JSONEncoder().encode(s) {
            SharedStore.defaults?.set(data, forKey: key)
        }
        SharedStore.defaults?.set(s.version, forKey: SharedStore.Keys.selectionVersion)
    }

    /// 清洗某组的新选择：移除已被其他组占用的 token（一个 token 只属一个组，14.3：重复选择被阻止）
    public static func sanitized(_ incoming: FamilyActivitySelection,
                                 for group: TrainingGroup,
                                 existing: [TrainingGroup: FamilyActivitySelection])
        -> FamilyActivitySelection {
        var takenApps = Set<ApplicationToken>()
        var takenCategories = Set<ActivityCategoryToken>()
        var takenDomains = Set<WebDomainToken>()
        for (g, s) in existing where g != group {
            takenApps.formUnion(s.applicationTokens)
            takenCategories.formUnion(s.categoryTokens)
            takenDomains.formUnion(s.webDomainTokens)
        }
        var result = incoming
        result.applicationTokens = deduplicate(incoming.applicationTokens, excluding: [takenApps])
        result.categoryTokens = deduplicate(incoming.categoryTokens, excluding: [takenCategories])
        result.webDomainTokens = deduplicate(incoming.webDomainTokens, excluding: [takenDomains])
        return result
    }

    /// 通用去重：从 incoming 中移除已被占用的元素（一个元素只属一个组，14.3）。
    /// 独立成泛型函数以便用任意 Hashable 类型做确定性单元测试（真实 token 无法脱离系统选择器构造）。
    public static func deduplicate<S: Hashable>(_ incoming: Set<S>, excluding taken: [Set<S>]) -> Set<S> {
        var result = incoming
        for t in taken { result.subtract(t) }
        return result
    }
}
