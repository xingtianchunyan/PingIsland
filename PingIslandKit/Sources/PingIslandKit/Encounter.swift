/// 遭遇与日记（执行文档 9.7）：每次探索生成生活片段。
/// 30% 怪物遭遇（胜负各 50%，与属性/装备/骰点/技能稀有度无关），70% 日常生活。
/// 失败不扣成长、装备或属性。日记记录结算时间与来源，不伪装成真实行为时间。

import Foundation

/// 图鉴怪物全 roster（12 只；D2 元素分配按默认决策）。
/// 遭遇结算仍只用 encounterPool 前三只（9.7 概率与 golden 输出不变，红线）。
public enum Monster: String, CaseIterable, Codable, Sendable {
    case skeleton = "小骷髅"          // D2：土
    case goblin = "哥布林"            // D2：金
    case slime = "史莱姆"             // D2：水
    case sapling = "树苗精"           // 木
    case mushroom = "蘑菇怪"          // 木
    case salamander = "火蜥蜴"        // 火
    case cinderBat = "火花蝠"         // 火
    case rockCrab = "岩壳蟹"          // 土
    case rustPuppet = "锈铁傀儡"      // 金
    case waterWisp = "小水灵"         // 水
    case staticOrb = "静电球"         // 雷
    case thunderFledgling = "雷雀"    // 雷

    /// 遭遇结算使用的怪物池（保持 9.7 的 30%/50-50 分布与 golden 确定性不变）
    public static let encounterPool: [Monster] = [.skeleton, .goblin, .slime]

    /// 内容库美术键（monsterArtKeys 的键）
    public var artKey: String {
        switch self {
        case .skeleton: return "skeleton"
        case .goblin: return "goblin"
        case .slime: return "slime"
        case .sapling: return "sapling"
        case .mushroom: return "mushroom"
        case .salamander: return "salamander"
        case .cinderBat: return "cinder_bat"
        case .rockCrab: return "rock_crab"
        case .rustPuppet: return "rust_puppet"
        case .waterWisp: return "water_wisp"
        case .staticOrb: return "static_orb"
        case .thunderFledgling: return "thunder_fledgling"
        }
    }

    /// 元素（D2 + 扩展九只的自然归属；雷为催化剂）
    public var element: SkillElement {
        switch self {
        case .skeleton, .rockCrab: return .earth
        case .goblin, .rustPuppet: return .metal
        case .slime, .waterWisp: return .water
        case .sapling, .mushroom: return .wood
        case .salamander, .cinderBat: return .fire
        case .staticOrb, .thunderFledgling: return .thunder
        }
    }
}

public enum DiaryEntryType: String, Codable, Sendable {
    case monsterWin
    case monsterLose
    case dailyLife
    case oracleBoon // 骰点 20 神谕大成功（每日一次）
    case milestone  // 每满 30 分钟的活动结算（真机反馈第十九批规则 v2）
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
            let monster = Monster.encounterPool[
                rng.nextInt(upperBound: Monster.encounterPool.count)]
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
        if key == "milestone.grant" {
            return "🌊 半小时修行结算"
        }
        if key == "milestone.extra" {
            return "✨ 命运的馈赠"
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
