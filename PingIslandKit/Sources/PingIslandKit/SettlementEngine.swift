import Foundation

/// 已确认使用事件（执行文档 6.2/7.4）。
/// stableEventID 全局唯一且稳定：重复投递、重试、恢复后重放都靠它去重，绝不重复发奖。
public struct UsageEvent: Equatable, Codable, Sendable {
    public var stableEventID: String
    public var group: TrainingGroup
    /// 该组当日累计已确认分钟（系统阈值事件口径，非精确使用分钟）
    public var thresholdMinutes: Int
    public var localDate: String
    public var confirmedAt: Date

    public init(stableEventID: String, group: TrainingGroup,
                thresholdMinutes: Int, localDate: String, confirmedAt: Date) {
        self.stableEventID = stableEventID
        self.group = group
        self.thresholdMinutes = thresholdMinutes
        self.localDate = localDate
        self.confirmedAt = confirmedAt
    }
}

public struct SettlementDelta: Equatable, Sendable {
    public var growthMilliApplied: Int64
    public var newMinutes: Int
    public var levelAfter: Int64
    public var explorations: [ExplorationReward]
    public var diaries: [DiaryRecord]
    public var classChanged: CharacterClass?
    public var oracleIssued: Bool
    /// 本批有效分钟的技能抽选（每分钟一次，执行文档 9.6）
    public var skillDraws: [SkillDraw]

    public static let zero = SettlementDelta(growthMilliApplied: 0, newMinutes: 0,
                                             levelAfter: 1, explorations: [], diaries: [],
                                             classChanged: nil, oracleIssued: false,
                                             skillDraws: [])
}

public enum SettlementOutcome: Equatable, Sendable {
    case duplicate            // 同一 stableEventID 重投：状态不变
    case settled(SettlementDelta)
}

/// 结算引擎（执行文档 Phase 1）：唯一结算入口。
/// 展示层只读状态；本引擎不依赖任何平台 API，可在 Windows XCTest 全量验证。
public struct SettlementEngine: Equatable, Codable, Sendable {
    public private(set) var growth = GrowthAccumulator()
    public private(set) var baseAttributes: [Attribute: Int]
    public private(set) var equipment: [EquipmentItem] = []
    public private(set) var equipped: [EquipmentSlot: EquipmentItem] = [:]
    public private(set) var diary: [DiaryRecord] = []
    public private(set) var processedEventIDs: Set<String> = []
    public private(set) var segments: [String: GameDaySegment] = [:]
    public private(set) var classState: CharacterClass?

    private var characterSeed: UInt64
    private var appliedThreshold: [String: [TrainingGroup: Int]] = [:]
    private var observationMinutes: [TrainingGroup: Int] = [:]
    private var observationDays: Set<String> = []
    /// 技能收藏（9.6：由有效分钟抽选累积；升级满级后转化点数）
    public private(set) var skillCollection = SkillCollection()
    /// 按日聚合的成长数据（日记页"屏幕使用时间"周视图用；旧存档缺省为空表）
    public private(set) var dayStats: [String: DayStats] = [:]

    private enum CodingKeys: String, CodingKey {
        case growth, baseAttributes, equipment, equipped, diary, processedEventIDs
        case segments, classState, characterSeed, appliedThreshold
        case observationMinutes, observationDays, skillCollection, dayStats
    }

    /// 旧版本 state JSON 没有 skillCollection 键：解码时按空收藏兼容，其余字段照原要求
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        growth = try c.decode(GrowthAccumulator.self, forKey: .growth)
        baseAttributes = try c.decode([Attribute: Int].self, forKey: .baseAttributes)
        equipment = try c.decode([EquipmentItem].self, forKey: .equipment)
        equipped = try c.decode([EquipmentSlot: EquipmentItem].self, forKey: .equipped)
        diary = try c.decode([DiaryRecord].self, forKey: .diary)
        processedEventIDs = try c.decode(Set<String>.self, forKey: .processedEventIDs)
        segments = try c.decode([String: GameDaySegment].self, forKey: .segments)
        classState = try c.decodeIfPresent(CharacterClass.self, forKey: .classState)
        characterSeed = try c.decode(UInt64.self, forKey: .characterSeed)
        appliedThreshold = try c.decode([String: [TrainingGroup: Int]].self, forKey: .appliedThreshold)
        observationMinutes = try c.decode([TrainingGroup: Int].self, forKey: .observationMinutes)
        observationDays = try c.decode(Set<String>.self, forKey: .observationDays)
        skillCollection = try c.decodeIfPresent(SkillCollection.self, forKey: .skillCollection)
            ?? SkillCollection()
        dayStats = try c.decodeIfPresent([String: DayStats].self, forKey: .dayStats) ?? [:]
    }

    public var level: Int64 { growth.level }

    /// 某日已入账的确认分钟合计（疲劳展示等只读用途）
    public func confirmedMinutes(on localDate: String) -> Int {
        appliedThreshold[localDate]?.reduce(0) { $0 + $1.value } ?? 0
    }

    /// 以修行组选择初始化：随机分配 10 点初始属性（种子固定，可重建）
    public init(groups: [TrainingGroup], characterSeed: UInt64 = 1) {
        var rng = SeededRandom(seed: characterSeed)
        self.baseAttributes = rollInitialAttributes(groups: groups, rng: &rng)
        self.characterSeed = characterSeed
    }

    /// 处理单个已确认事件：归属 → 去重 → 补差额 → 成长 → 探索 → 职业观察 → 日记，全部确定性
    @discardableResult
    public mutating func process(_ event: UsageEvent) -> SettlementOutcome {
        // 1. 幂等：同一事件身份只结算一次
        guard !processedEventIDs.contains(event.stableEventID) else { return .duplicate }
        processedEventIDs.insert(event.stableEventID)

        var delta = SettlementDelta.zero
        delta.levelAfter = growth.level

        // 2. 归属：只补尚未入账的累计量；低阈值晚到不倒退
        let applied = appliedThreshold[event.localDate]?[event.group] ?? 0
        let newMinutes = max(0, event.thresholdMinutes - applied)
        if newMinutes > 0 {
            appliedThreshold[event.localDate, default: [:]][event.group] = event.thresholdMinutes
        }

        // 3. 当日骰子（首次结算建立；同日不重抽；运气快照取当前最终 LUK）
        var segment = segments[event.localDate]
            ?? GameDaySegment(segmentID: Int64(segments.count + 1),
                              localDate: event.localDate, timeZoneID: "local")
        var diceRng = SeededRandom(seed: diceSeed(for: event.localDate))
        let luckSnapshot = finalAttributes()[.luk, default: 1]
        let dice = segment.ensureDice(luckSnapshot: luckSnapshot, rng: &diceRng).value

        // 4. 骰点 20：建段时立即发放一次神谕奖励（每日一次），日记明确记录大成功
        if dice >= 20 {
            var oracleRng = SeededRandom(seed: fnv1a64("oracle|\(event.localDate)"))
            if segment.tryIssueOracleReward() {
                let amount = oracleRng.nextInt(lowerBound: 5, upperBound: 10)
                let attr = RulesConfig.oraclePackAttributes[
                    oracleRng.nextInt(upperBound: RulesConfig.oraclePackAttributes.count)]
                baseAttributes[attr, default: 0] += amount
                delta.oracleIssued = true
                delta.diaries.append(DiaryRecord(
                    recordedAt: event.confirmedAt, group: event.group,
                    entryType: .oracleBoon, textKey: "oracle.boon",
                    rewardSummary: "神谕奖励 +\(amount) \(attr.rawValue)"))
            }
        }

        // 5. 线性成长
        if newMinutes > 0 {
            let factor: GrowthFactor
            if let cls = classState {
                factor = (cls == .ranger) ? .ranger : .matched
            } else {
                factor = .neutral
            }
            let appliedMilli = growth.settle(minutes: newMinutes, dice: dice, factor: factor)
            delta.growthMilliApplied = appliedMilli
            delta.newMinutes = newMinutes
            // 规则 v1.1：基础智慧 = 初始智慧 +（等级 − 1），每升 1 级 +1 智慧；
            // 按等级增量补（100 XP 一级，跨段余量不进位）
            let newLevel = growth.level
            let oldLevel = 1 + (growth.totalMilli - appliedMilli) / 100_000
            baseAttributes[.wis, default: 0] += Int(newLevel - oldLevel)
            // 按日聚合（周视图）：同日多事件累加，等级增量按本段前后差计
            var ds = dayStats[event.localDate] ?? DayStats()
            ds.minutes += newMinutes
            ds.growthMilli += appliedMilli
            ds.levelGained += Int(newLevel - oldLevel)
            dayStats[event.localDate] = ds
        }

        // 5.5 技能抽选：每个有效分钟一次逻辑抽选（9.6），按（种子、骰点、分钟序号、星期）确定性
        if newMinutes > 0 {
            let weekday = SkillDrawRules.weekday(forLocalDate: event.localDate)
            for i in 0..<newMinutes {
                let draw = SkillDrawRules.draw(
                    characterSeed: characterSeed, dice: dice,
                    minuteIndex: applied + i + 1, weekday: weekday)
                skillCollection.add(draw)
                delta.skillDraws.append(draw)
            }
        }

        // 6. 探索：每满 30 分钟一次，每组每日最多 5 次；一次跨多个里程碑按序补算
        let milestoneCount = event.thresholdMinutes / RulesConfig().explorationThresholdMinutes
        let previousMilestones = applied / RulesConfig().explorationThresholdMinutes
        let due = max(0, min(milestoneCount, RulesConfig().maxExplorationsPerGroupPerDay)
                        - previousMilestones)
        var equipmentID = equipment.count
        for _ in 0..<due {
            guard segment.tryConsumeExploration(for: event.group) else { break }
            var exploreRng = SeededRandom(seed: fnv1a64(
                "explore|\(event.stableEventID)|\(segment.explorationsUsedByGroup[event.group] ?? 0)"))
            let charm = finalAttributes()[.cha, default: 0]
            let reward = ExplorationRules.resolve(dice: dice, finalCharm: charm,
                                                  equipmentID: &equipmentID, rng: &exploreRng)
            apply(reward, recordedAt: event.confirmedAt,
                  origin: "探索获得·\(event.thresholdMinutes) 分钟里程碑")
            delta.explorations.append(reward)

            var encRng = SeededRandom(seed: fnv1a64("encounter|\(event.stableEventID)"))
            let encounter = EncounterRules.resolve(rng: &encRng)
            delta.diaries.append(EncounterRules.makeDiary(
                recordedAt: event.confirmedAt, group: event.group,
                encounter: encounter, rewardSummary: summarize(reward)))
        }

        // 7. 职业观察（定型后不追溯、不重判）
        observationMinutes[event.group, default: 0] += newMinutes
        observationDays.insert(event.localDate)
        if classState == nil, observationDays.count >= ClassAwakening.minObservationDays {
            let inputs = observationMinutes.map {
                ClassAwakening.ObservationInput(group: $0.key, confirmedMinutes: $0.value)
            }
            if case .awakened(let cls) = ClassAwakening.judge(
                daysObserved: observationDays.count, inputs: inputs) {
                classState = cls
                delta.classChanged = cls
            }
        }

        segments[event.localDate] = segment
        diary.append(contentsOf: delta.diaries)
        delta.levelAfter = growth.level
        return .settled(delta)
    }

    /// 批量处理 = 逐条处理的简单循环：保证批量与逐条结果一致（执行文档 14.1-7）
    @discardableResult
    public mutating func process(_ events: [UsageEvent]) -> [SettlementOutcome] {
        events.map { process($0) }
    }

    // MARK: - 派生状态

    public func finalAttributes() -> [Attribute: Int] {
        var equipFlat = [Attribute: Int]()
        for item in equipped.values {
            for affix in item.affixes {
                equipFlat[affix.attribute, default: 0] += affix.value
            }
        }
        return PingIslandKit.finalAttributes(input: PanelInput(
            baseValues: baseAttributes, equipmentFlat: equipFlat))
    }

    // MARK: - 内部

    private mutating func apply(_ reward: ExplorationReward, recordedAt: Date, origin: String) {
        for (attr, points) in reward.attributePoints {
            baseAttributes[attr, default: 0] += points
        }
        for var item in reward.equipment {
            item.acquiredAt = recordedAt
            item.origin = origin
            if let current = equipped[item.slot],
               !EquipmentRules.shouldEquip(newItem: item, current: current) {
                item.isEquipped = false
                equipment.append(item) // 未穿上的新装备仍入收藏
                continue
            }
            item.isEquipped = true
            // 换上新装备时，撤掉旧藏品的"装备中"标记，否则收藏页同部位出现多个装备中
            if let old = equipped[item.slot],
               let idx = equipment.firstIndex(where: { $0.id == old.id }) {
                equipment[idx].isEquipped = false
            }
            equipped[item.slot] = item
            equipment.append(item)
        }
    }

    private func summarize(_ reward: ExplorationReward) -> String {
        var parts: [String] = []
        if !reward.attributePoints.isEmpty {
            let desc = reward.attributePoints
                .sorted { $0.key.rawValue < $1.key.rawValue }
                .map { "+\($0.value) \($0.key.rawValue)" }
                .joined(separator: "、")
            parts.append("属性 \(desc)")
        }
        if !reward.equipment.isEmpty {
            parts.append("装备 ×\(reward.equipment.count)")
        }
        if reward.kind == .activeSkill || reward.kind == .passiveSkill {
            parts.append("技能/特质（模板 Phase 4 接入）")
        }
        return parts.isEmpty ? "无奖励" : parts.joined(separator: "，")
    }

    private func diceSeed(for localDate: String) -> UInt64 {
        fnv1a64("dice|\(localDate)") &+ characterSeed
    }
}

/// FNV-1a 64：稳定事件身份 → 确定性随机种子（重试不重抽的关键）
public func fnv1a64(_ string: String) -> UInt64 {
    var hash: UInt64 = 0xcbf29ce484222325
    for byte in string.utf8 {
        hash ^= UInt64(byte)
        hash = hash &* 0x100000001b3
    }
    return hash
}
