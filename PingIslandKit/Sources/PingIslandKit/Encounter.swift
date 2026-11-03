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
    case oracleBoon // 骰点 20 神谕大成功（每日一次）
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
                               textKey: "dailylife.\(rng.nextInt(upperBound: DailyLifePool.texts.count))")
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

public extension Monster {
    var winText: String { "战胜了\(rawValue)" }
    var loseText: String { "被\(rawValue)击退" }
}

/// 日常生活片段池（执行文档 9.7：70% 日常）
public enum DailyLifePool {
    public static let texts: [String] = [
        "在沙滩上散步",
        "给篝火添了把柴",
        "收集了一枚贝壳",
        "练习了新的姿势",
        "晒了会儿太阳",
        "整理了一下背包",
    ]
}

/// 日记 textKey → 展示文案（执行文档 9.7；文案单一来源，UI 不拼 key）
public enum DiaryText {
    /// 未知键原样返回，便于排查而不崩溃
    public static func display(_ key: String) -> String {
        if key.hasPrefix("encounter.") {
            let body = String(key.dropFirst("encounter.".count))
            let parts = body.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            if parts.count == 2, let monster = Monster(rawValue: parts[0]) {
                return parts[1] == "win" ? monster.winText : monster.loseText
            }
        }
        if key == "oracle.boon" {
            return "☀️ 神谕降临"
        }
        if key.hasPrefix("dailylife.") {
            let index = Int(key.dropFirst("dailylife.".count)) ?? -1
            if DailyLifePool.texts.indices.contains(index) {
                return DailyLifePool.texts[index]
            }
        }
        return key
    }
}
