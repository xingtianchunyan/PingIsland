import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// 实验日志（执行文档 12.3：性能、能耗和生命周期记录）。
/// 纯内存 + 导出文本，不接入主 App 账本。
struct LabLog: Equatable {
    private(set) var lines: [String] = []
    private let limit = 200

    mutating func append(_ line: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        lines.append("[\(stamp)] \(line)")
        if lines.count > limit { lines.removeFirst(lines.count - limit) }
    }

    var exportText: String { lines.joined(separator: "\n") }

    /// 粗略能耗迹象：记录当前内存占用（12.3-7 的性能与能耗观察项之一）
    mutating func appendMemorySnapshot() {
        #if canImport(UIKit)
        let bytes = ProcessInfo.processInfo.physicalMemory
        append("memory.physical=\(bytes / 1024 / 1024)MB")
        #else
        append("memory.snapshot.unavailable")
        #endif
    }
}
