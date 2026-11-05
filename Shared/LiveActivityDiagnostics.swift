import Foundation

/// Live Activity 启动/结束诊断（第十五次真机反馈定位用）。
/// 每次操作的结果与确切错误写入共享容器（App Group），调试面板"运行状态"直接可见——
/// 真机失败不再只能靠用户口头转述。仅记录操作结果，不含任何个人数据。
public enum LiveActivityDiagnostics {
    public static let key = "liveActivity.diagnostics.v1"
    private static let limit = 10

    public static func record(_ line: String) {
        guard let defaults = SharedStore.defaults else { return }
        var lines = defaults.stringArray(forKey: key) ?? []
        lines.append("\(timestamp()) \(line)")
        if lines.count > limit { lines.removeFirst(lines.count - limit) }
        defaults.set(lines, forKey: key)
    }

    public static func recentLines() -> [String] {
        SharedStore.defaults?.stringArray(forKey: key) ?? []
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm:ss"
        return formatter.string(from: Date())
    }
}
