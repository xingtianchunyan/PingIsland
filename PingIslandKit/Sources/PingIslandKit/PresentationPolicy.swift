import Foundation

/// 展示优先级（执行文档 11.4）：同一批普通事件合并，不连续弹多个提示。
/// 数值越小越优先。纯函数判定，Windows XCTest 可全量验证。
public enum DisplayPriority: Int, Codable, Sendable, Comparable, CaseIterable {
    case confirmedAnomalySleep = 0 // 已确认异常休眠（恢复层标记）
    case nightRest = 1             // 夜间休眠姿态
    case milestone = 2             // 神谕／职业觉醒／新收藏
    case recentEncounter = 3       // 最近遭遇或技能
    case dailyLife = 4             // 修行生活姿态

    public static func < (lhs: DisplayPriority, rhs: DisplayPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// 优先级判定输入：全部可由结算增量与系统状态推导，无平台依赖
public struct PresentationInput: Equatable, Sendable {
    /// 最近一批已结算增量（无新结算时为 nil）
    public var latestDelta: SettlementDelta?
    /// 恢复层已确认的异常休眠标记
    public var hasAnomalySleep: Bool
    /// 当前本地时间是否处于夜间段
    public var isNight: Bool

    public init(latestDelta: SettlementDelta? = nil,
                hasAnomalySleep: Bool = false, isNight: Bool = false) {
        self.latestDelta = latestDelta
        self.hasAnomalySleep = hasAnomalySleep
        self.isNight = isNight
    }
}

public enum PresentationPolicy {
    /// 夜间段默认 23:00~次日 07:00（展示口径，可按真机反馈调整）
    public static let nightStartHour = 23
    public static let nightEndHour = 7

    public static func isNight(_ date: Date, calendar: Calendar = Calendar.current) -> Bool {
        let hour = calendar.component(.hour, from: date)
        return hour >= nightStartHour || hour < nightEndHour
    }

    public static func resolve(_ input: PresentationInput) -> DisplayPriority {
        if input.hasAnomalySleep { return .confirmedAnomalySleep }
        if input.isNight { return .nightRest }
        if let d = input.latestDelta {
            if d.oracleIssued || d.classChanged != nil || !d.milestoneGrants.isEmpty {
                return .milestone
            }
            if d.diaries.contains(where: { $0.entryType == .monsterWin || $0.entryType == .monsterLose }) {
                return .recentEncounter
            }
        }
        return .dailyLife
    }

    /// 优先级对应的展示文案（nil = 用日常最近事件即可）
    public static func banner(for priority: DisplayPriority, input: PresentationInput) -> String? {
        switch priority {
        case .confirmedAnomalySleep:
            return "岛民进入异常休眠，等待恢复同步"
        case .nightRest:
            return "夜间休眠中"
        case .milestone:
            guard let d = input.latestDelta else { return "新的里程碑" }
            if d.classChanged != nil { return "职业觉醒：\(d.classChanged!.rawValue)" }
            if d.oracleIssued { return "神谕赐予属性" }
            return "探索获得新收藏"
        case .recentEncounter:
            return "刚刚经历一场遭遇"
        case .dailyLife:
            return nil
        }
    }
}
