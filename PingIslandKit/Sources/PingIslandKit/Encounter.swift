/// 遭遇与日记（执行文档 9.7）：每次探索生成生活片段。
/// 30% 怪物遭遇（胜负各 50%，与属性/装备/骰点/技能稀有度无关），70% 日常生活。
/// 失败不扣成长、装备或属性。日记记录结算时间与来源，不伪装成真实行为时间。

import Foundation

public enum Monster: String, CaseIterable, Codable, Sendable {
    case skeleton = "小骷髅"
    case goblin = "哥布林"
    case slime = "史莱姆"
}

public enum DiaryEntryType: String, Codable, Sendable {
    case monsterWin
    case monsterLose
    case dailyLife
}

public struct EncounterResult: Equatable, Sendable {
    public var entryType: DiaryEntryType
    public var textKey: String
    public init(entryType: DiaryEntryType, textKey: String) {
        self.entryType = entryType
        self.textKey = textKey
    }
}

public struct DiaryRecord: Equatable, Codable, Sendable {
    public var recordedAt: Date
    public var group: TrainingGroup
    public var entryType: DiaryEntryType
    public var textKey: String
    public var rewardSummary: String
}

public enum EncounterRules {
    public static let monsterChancePercent = 30

    public static func resolve(rng: inout some RandomSource) -> EncounterResult {
        if rng.nextInt(upperBound: 100) < monsterChancePercent {
            let monster = Monster.allCases[rng.nextInt(upperBound: Monster.allCases.count)]
            let won = rng.nextInt(upperBound: 2) == 0
            return EncounterResult(
                entryType: won ? .monsterWin : .monsterLose,
                textKey: won ? "encounter.\(monster.rawValue).win" : "encounter.\(monster.rawValue).lose")
        }
        return EncounterResult(entryType: .dailyLife,
                               textKey: "dailylife.\(rng.nextInt(upperBound: 6))")
    }

    /// 生成日记记录；recordedAt 为结算时刻（调用方传入）
    public static func makeDiary(recordedAt: Date, group: TrainingGroup,
                                 encounter: EncounterResult,
                                 rewardSummary: String) -> DiaryRecord {
        DiaryRecord(recordedAt: recordedAt, group: group,
                    entryType: encounter.entryType, textKey: encounter.textKey,
                    rewardSummary: rewardSummary)
    }
}
