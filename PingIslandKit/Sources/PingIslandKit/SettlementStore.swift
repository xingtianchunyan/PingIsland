import Foundation

/// 结算持久化协议（执行文档 4.2/13.3）。
/// 首版用 JSON 文件 + 原子替换；未来可平移到 SQLite/GRDB 事务实现，接口不变。
public protocol SettlementStore: Sendable {
    func loadState() throws -> Data?
    func saveState(_ data: Data) throws
    func loadJournal() throws -> Data?
    func saveJournal(_ data: Data) throws
}

/// 基于目录的 JSON 存储：状态与事件日志各一个文件，写临时文件后原子替换，
/// 任何时刻不存在半套写入（执行文档 13.3：数据库写入中断禁止半套奖励入账）。
public struct JSONFileSettlementStore: SettlementStore {
    public let directory: URL
    private let stateName = "settlement-state.v1.json"
    private let journalName = "settlement-journal.v1.json"

    public init(directory: URL) {
        self.directory = directory
    }

    public func loadState() throws -> Data? {
        try read(named: stateName)
    }

    public func saveState(_ data: Data) throws {
        try write(data, named: stateName)
    }

    public func loadJournal() throws -> Data? {
        try read(named: journalName)
    }

    public func saveJournal(_ data: Data) throws {
        try write(data, named: journalName)
    }

    private func url(named: String) -> URL {
        directory.appendingPathComponent(named)
    }

    private func read(named: String) throws -> Data? {
        let u = url(named: named)
        guard FileManager.default.fileExists(atPath: u.path) else { return nil }
        return try Data(contentsOf: u)
    }

    private func write(_ data: Data, named: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // .atomic：先写临时文件再重命名，任何时刻无半套文件
        try data.write(to: url(named: named), options: .atomic)
    }
}

/// 结算服务：唯一对外入口。崩溃恢复语义 = 事件先落日志、再结算、后存状态；
/// 恢复时重放日志中未处理事件（低阈值晚到不倒退，重复事件判重），保证恰好一次生效。
public final class SettlementService {
    public private(set) var engine: SettlementEngine
    private let store: any SettlementStore
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(store: any SettlementStore, groups: [TrainingGroup],
                characterSeed: UInt64 = 1) throws {
        self.store = store
        if let data = try store.loadState(),
           let saved = try? decoder.decode(SettlementEngine.self, from: data) {
            self.engine = saved
        } else {
            self.engine = SettlementEngine(groups: groups, characterSeed: characterSeed)
        }
        // 恢复：重放日志（已入账的全判重，中断的补入账）
        if let journalData = try store.loadJournal(),
           let events = try? decoder.decode([UsageEvent].self, from: journalData) {
            engine.process(events)
        }
    }

    @discardableResult
    public func process(_ event: UsageEvent) -> SettlementOutcome {
        // 1. 事件先落日志（至少一次）
        var journal = (try? loadJournal()) ?? []
        journal.append(event)
        try? store.saveJournal(encoder.encode(journal))
        // 2. 结算（幂等）
        let outcome = engine.process(event)
        // 3. 保存状态（原子；此处失败可由恢复流程补齐）
        try? store.saveState(encoder.encode(engine))
        return outcome
    }

    @discardableResult
    public func process(_ events: [UsageEvent]) -> [SettlementOutcome] {
        events.map { process($0) }
    }

    /// 新的一天开始（真机反馈第十九批）：建立当日骰点 + 骰 20 发放每日一次神谕。
    /// 调试"模拟过一天"等换日入口使用；事件结算路径内部也会调用（幂等）。
    @discardableResult
    public func startDay(_ localDate: String, recordedAt: Date = Date()) -> Bool {
        let issued = engine.startDay(localDate, recordedAt: recordedAt)
        try? store.saveState(encoder.encode(engine))
        return issued
    }

    // MARK: - 调试注入（第二十批：手动设置装备/技能/指定骰点）

    /// 手动注入一件装备（指定部位/品质，外观可固定），走自动择优与收藏账本
    public func debugInjectEquipment(slot: EquipmentSlot, rarity: Rarity,
                                     appearance: String?, recordedAt: Date) {
        engine.debugInjectEquipment(slot: slot, rarity: rarity,
                                    appearance: appearance, recordedAt: recordedAt)
        try? store.saveState(encoder.encode(engine))
    }

    /// 手动注入一个特质/技能（指定品质与主/被动）
    public func debugInjectSkill(rarity: Rarity, isActive: Bool, weekday: Int) {
        engine.debugInjectSkill(rarity: rarity, isActive: isActive, weekday: weekday)
        try? store.saveState(encoder.encode(engine))
    }

    /// 指定某日骰点（覆盖现有值）；配合 startDay 可在过天即发神谕
    public func debugSetDice(_ value: Int, for localDate: String) {
        engine.debugSetDice(value, for: localDate)
        try? store.saveState(encoder.encode(engine))
    }

    private func loadJournal() throws -> [UsageEvent]? {
        guard let data = try store.loadJournal() else { return nil }
        return try decoder.decode([UsageEvent].self, from: data)
    }
}
