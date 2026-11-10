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
    /// 调试专用（仅模拟事件使用）：直接指定当日骰点，跳过运气掷骰；
    /// 生产 DeviceActivity 事件必须为 nil。取值钳制到 [1, 20]。
    public var diceOverride: Int?

    public init(stableEventID: String, group: TrainingGroup,
                thresholdMinutes: Int, localDate: String, confirmedAt: Date,
                diceOverride: Int? = nil) {
        self.stableEventID = stableEventID
        self.group = group
        self.thresholdMinutes = thresholdMinutes
        self.localDate = localDate
        self.confirmedAt = confirmedAt
        self.diceOverride = diceOverride
    }

    private enum CodingKeys: String, CodingKey {
        case stableEventID, group, thresholdMinutes, localDate, confirmedAt, diceOverride
    }

    /// 旧版本账本日志无 diceOverride 键：按 nil 兼容解码
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        stableEventID = try c.decode(String.self, forKey: .stableEventID)
        group = try c.decode(TrainingGroup.self, forKey: .group)
        thresholdMinutes = try c.decode(Int.self, forKey: .thresholdMinutes)
        localDate = try c.decode(String.self, forKey: .localDate)
        confirmedAt = try c.decode(Date.self, forKey: .confirmedAt)
        diceOverride = try c.decodeIfPresent(Int.self, forKey: .diceOverride)
    }
}

public struct SettlementDelta: Equatable, Sendable {
    public var growthMilliApplied: Int64
    public var newMinutes: Int
    public var levelAfter: Int64
    /// 本事件结算出的半小时活动结果（真机反馈第十九批规则 v2；原 explorations 字段由本字段取代）
    public var milestoneGrants: [MilestoneGrant]
    public var diaries: [DiaryRecord]
    public var classChanged: CharacterClass?
    public var oracleIssued: Bool
    /// 本批有效分钟的技能抽选（每分钟一次，执行文档 9.6）
    public var skillDraws: [SkillDraw]

    public static let zero = SettlementDelta(growthMilliApplied: 0, newMinutes: 0,
                                             levelAfter: 1, milestoneGrants: [], diaries: [],
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
    /// 每升 1 级成长的千分位累计（规则 v3.1：职业系数 × 1 点/级，跨段保留余量；旧存档缺省 0）
    private var wisLevelMilli: Int64 = 0
    /// 已入账的等级智慧点数（wisLevelMilli/1000 的快照，避免重复入账）
    private var wisLevelApplied: Int = 0

    private enum CodingKeys: String, CodingKey {
        case growth, baseAttributes, equipment, equipped, diary, processedEventIDs
        case segments, classState, characterSeed, appliedThreshold
        case observationMinutes, observationDays, skillCollection, dayStats
        case wisLevelMilli, wisLevelApplied
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
        wisLevelMilli = try c.decodeIfPresent(Int64.self, forKey: .wisLevelMilli) ?? 0
        wisLevelApplied = try c.decodeIfPresent(Int.self, forKey: .wisLevelApplied) ?? 0
    }

    public var level: Int64 { growth.level }

    /// 调试面板展示用：职业觉醒观察进度（已观察天数 / 需要天数 / 各组分钟）
    public var awakeningProgress: (days: Int, requiredDays: Int, minutes: [TrainingGroup: Int]) {
        (observationDays.count, ClassAwakening.minObservationDays, observationMinutes)
    }

    /// 某日已入账的确认分钟合计（疲劳展示等只读用途）
    public func confirmedMinutes(on localDate: String) -> Int {
        appliedThreshold[localDate]?.reduce(0) { $0 + $1.value } ?? 0
    }

    /// 预览某日骰点（不写入状态；当日首次结算前展示层显示用）。
    /// 与结算路径同一骰子种子与运气快照口径，确保预览值 = 结算值。
    public func previewDice(for localDate: String) -> Int {
        var rng = SeededRandom(seed: diceSeed(for: localDate))
        var segment = segments[localDate]
            ?? GameDaySegment(segmentID: Int64(segments.count + 1),
                              localDate: localDate, timeZoneID: "local")
        return segment.ensureDice(luckSnapshot: finalAttributes()[.luk, default: 1],
                                  rng: &rng).value
    }

    /// 新的一天开始（真机反馈第十九批）：建立当日骰点；骰 20 时发放每日一次的神谕奖励。
    /// 换日即触发、不占活动结算次数；幂等（同日重复调用零开销）。
    /// 展示/调试层在换日时直接调用本方法；事件结算路径也会调用。
    @discardableResult
    public mutating func startDay(_ localDate: String, recordedAt: Date = Date()) -> Bool {
        var segment = segments[localDate]
            ?? GameDaySegment(segmentID: Int64(segments.count + 1),
                              localDate: localDate, timeZoneID: "local")
        var diceRng = SeededRandom(seed: diceSeed(for: localDate))
        let dice = segment.ensureDice(luckSnapshot: finalAttributes()[.luk, default: 1],
                                      rng: &diceRng).value
        var issued = false
        if dice >= 20 && segment.tryIssueOracleReward() {
            var oracleRng = SeededRandom(seed: fnv1a64("oracle|\(localDate)"))
            let amount = oracleRng.nextInt(lowerBound: 5, upperBound: 10)
            let attr = RulesConfig.oraclePackAttributes[
                oracleRng.nextInt(upperBound: RulesConfig.oraclePackAttributes.count)]
            baseAttributes[attr, default: 0] += amount
            diary.append(DiaryRecord(
                recordedAt: recordedAt, group: .other,
                entryType: .oracleBoon, textKey: "oracle.boon",
                rewardSummary: "神谕奖励 +\(amount) \(attr.rawValue)"))
            issued = true
        }
        segments[localDate] = segment
        return issued
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
        // 调试专用：模拟事件可指定骰点（钳制 [1,20]），生产事件恒为 nil 走正常掷骰
        if let override = event.diceOverride {
            segment.dice = DailyDice(value: min(20, max(1, override)))
            segments[event.localDate] = segment
        }
        // 4. 一天开始：建立骰点 + 骰 20 发放每日一次的神谕（换日即触发，不占活动结算次数）
        delta.oracleIssued = startDay(event.localDate, recordedAt: event.confirmedAt)
        // startDay 已把骰点/神谕标记写回 segments；此处必须重读——
        // 若沿用第 3 步的旧副本，文末写回会覆盖掉骰点（nil）与神谕标记（重复发放）
        segment = segments[event.localDate] ?? segment
        let dice = segment.dice?.value ?? 10

        // 5. 每分钟经验已移除（真机反馈第二十一批）：经验只来自半小时活动结算，
        //    升级不再容易；职业系数作用于活动 XP（见第 6 步）与每级成长（见第 7 步）
        var dayMilli: Int64 = 0

        // 6. 每满 30 分钟一次活动结算（规则 v3）：经验加成 30×骰点/10 × 职业系数 +
        //    按骰点四档得属性 / 装备 / 特质·技能（骰 20 额外必得一件高级装备）
        let activityFactor: GrowthFactor
        if let cls = classState {
            activityFactor = (cls == .ranger) ? .ranger : .matched
        } else {
            activityFactor = .neutral
        }
        let milestoneCount = event.thresholdMinutes / RulesConfig().explorationThresholdMinutes
        let previousMilestones = applied / RulesConfig().explorationThresholdMinutes
        let due = max(0, min(milestoneCount, RulesConfig().maxExplorationsPerGroupPerDay)
                        - previousMilestones)
        var equipmentID = equipment.count
        let weekday = SkillDrawRules.weekday(forLocalDate: event.localDate)
        for index in 0..<due {
            guard segment.tryConsumeExploration(for: event.group) else { break }
            var milestoneRng = SeededRandom(seed: fnv1a64(
                "milestone|\(event.stableEventID)|\(previousMilestones + index + 1)"))
            // 外观按生成时刻最终 WIS 定型（与展示推导一致），词条数值随之乘外观倍率
            let appearance = EquipmentAppearance.appearanceType(
                finalWisdom: finalAttributes()[.wis, default: 0])
            let grant = MilestoneRules.resolve(dice: dice, weekday: weekday,
                                               equipmentID: &equipmentID,
                                               appearance: appearance, rng: &milestoneRng)
            apply(equipment: grant.allEquipment, recordedAt: event.confirmedAt,
                  origin: "修行活动·\(event.thresholdMinutes) 分钟里程碑")
            if let skill = grant.mainSkill { skillCollection.add(skill) }
            // 活动属性奖励入账（基础 CON/INT/DEX 或高级 LUK/WIS/CHA）
            for (attr, points) in grant.attributePoints {
                baseAttributes[attr, default: 0] += points
            }
            // 活动经验入账（3×骰点 XP × 职业系数；settle(dice:10) = XP×1000 milli）
            dayMilli += growth.settle(minutes: grant.experienceXP, dice: 10,
                                      factor: activityFactor)
            delta.milestoneGrants.append(grant)
            delta.diaries.append(DiaryRecord(
                recordedAt: event.confirmedAt, group: event.group,
                entryType: .milestone, textKey: "milestone.grant",
                rewardSummary: MilestoneRules.describe(grant)))
            // 骰 20 额外装备独立成条（真机反馈第十九批：主结果与额外装备各一条日记）
            if let extraSummary = MilestoneRules.describeExtra(grant) {
                delta.diaries.append(DiaryRecord(
                    recordedAt: event.confirmedAt, group: event.group,
                    entryType: .milestone, textKey: "milestone.extra",
                    rewardSummary: extraSummary))
            }
        }

        // 7. 等级推进：100 XP/级；每升 1 级成长（规则 v3.1）= 1 点基础智慧 × 职业系数，
        // 千分位定点累计（matched 每级 +1.10、ranger 每级 +1.03、neutral 每级 +1.00，余量跨段保留）
        if dayMilli > 0 {
            delta.growthMilliApplied = dayMilli
            delta.newMinutes = newMinutes
            let newLevel = growth.level
            let oldLevel = 1 + (growth.totalMilli - dayMilli) / 100_000
            if newLevel > oldLevel {
                let wisFactor: GrowthFactor
                if let cls = classState {
                    wisFactor = (cls == .ranger) ? .ranger : .matched
                } else {
                    wisFactor = .neutral
                }
                wisLevelMilli += (newLevel - oldLevel) * 1000 * Int64(wisFactor.numerator)
                    / Int64(wisFactor.denominator)
                let wisApplied = Int(wisLevelMilli / 1000)
                baseAttributes[.wis, default: 0] += wisApplied - wisLevelApplied
                wisLevelApplied = wisApplied
            }
            // 按日聚合（周视图）：同日多事件累加，等级增量按本段前后差计
            var ds = dayStats[event.localDate] ?? DayStats()
            ds.minutes += newMinutes
            ds.growthMilli += dayMilli
            ds.levelGained += Int(newLevel - oldLevel)
            dayStats[event.localDate] = ds
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

    // MARK: - 调试注入（真机反馈第二十批）

    /// 手动注入一件装备（指定部位/品质，外观可固定覆盖），走自动择优与收藏账本
    public mutating func debugInjectEquipment(slot: EquipmentSlot, rarity: Rarity,
                                              appearance: String?, recordedAt: Date) {
        var rng = SeededRandom(seed: fnv1a64("debug-equipment|\(equipment.count)|\(slot.rawValue)|\(rarity.rawValue)|\(appearance ?? "auto")"))
        // 外观：指定则用指定，否则按当前最终 WIS 推导（与真实掉落一致，倍率随之生效）
        let resolved = appearance ?? EquipmentAppearance.appearanceType(
            finalWisdom: finalAttributes()[.wis, default: 0])
        let item = EquipmentRules.generate(id: equipment.count + 1, slot: slot,
                                           rarity: rarity, appearance: resolved,
                                           rng: &rng)
        apply(equipment: [item], recordedAt: recordedAt, origin: "调试注入")
    }

    /// 手动注入一个特质/技能（指定品质与主/被动，模板取当周日行）
    public mutating func debugInjectSkill(rarity: Rarity, isActive: Bool, weekday: Int) {
        let template = SkillRules.template(forWeekday: weekday)
        skillCollection.add(SkillDraw(
            template: template, rarity: rarity, isActive: isActive,
            passiveValue: isActive ? 0 : SkillRules.passiveValue(rarity: rarity, level: 1),
            weekday: weekday))
    }

    /// 指定某日骰点（覆盖现有值，钳制 [1,20]）；配合 startDay 可在换日即发神谕
    public mutating func debugSetDice(_ value: Int, for localDate: String) {
        var segment = segments[localDate]
            ?? GameDaySegment(segmentID: Int64(segments.count + 1),
                              localDate: localDate, timeZoneID: "local")
        segment.dice = DailyDice(value: min(20, max(1, value)))
        segments[localDate] = segment
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

    /// 新装备入账：与同部位当前装备择优，未穿上的仍入收藏（执行文档 9.4）
    private mutating func apply(equipment newItems: [EquipmentItem],
                                recordedAt: Date, origin: String) {
        for var item in newItems {
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
