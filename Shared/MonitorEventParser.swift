import Foundation
import PingIslandKit

/// 监控事件名解析（执行文档 7.2：每组独立、稳定、可持久化的事件标识）。
/// 格式：pingisland.g<组序>.t<分钟>；兼容旧格式 pingisland.threshold.<分钟>（归“其他”组）。
public enum MonitorEventParser {
    public static func parse(_ raw: String) -> (group: TrainingGroup, minutes: Int)? {
        let parts = raw.split(separator: ".", omittingEmptySubsequences: false)
            .map(String.init)
        // 新格式：["pingisland", "g3", "t60"]
        if parts.count == 3, parts[0] == "pingisland",
           parts[1].hasPrefix("g"), let groupIndex = Int(parts[1].dropFirst()),
           parts[2].hasPrefix("t"), let minutes = Int(parts[2].dropFirst()),
           groupIndex >= 0, groupIndex < TrainingGroup.allCases.count {
            return (TrainingGroup.allCases[groupIndex], minutes)
        }
        // 旧格式：["pingisland", "threshold", "60"]
        if parts.count == 3, parts[0] == "pingisland",
           parts[1] == "threshold", let minutes = Int(parts[2]) {
            return (.other, minutes)
        }
        return nil
    }

    /// 事件名生成（注册与解析共用，保证归属一致）
    public static func name(group: TrainingGroup, minutes: Int) -> String {
        let idx = TrainingGroup.allCases.firstIndex(of: group) ?? 0
        return "pingisland.g\(idx).t\(minutes)"
    }
}
