import ActivityKit
import SwiftUI

/// Live Activity 便捷控制（执行文档 11.3：首开可创建一次）
struct LiveActivityControls: View {
    @State private var message = ""

    var body: some View {
        VStack(spacing: 8) {
            Button("开启灵动岛 / 锁屏实时活动") { start() }
            Button("结束实时活动") { endAll() }
                .foregroundStyle(.secondary)
            if !message.isEmpty {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
    }

    private func start() {
        let snapshot = SnapshotIO.load() ?? DisplaySnapshot()
        let attributes = PingIslandActivityAttributes(characterTitle: "岛上居民")
        let state = PingIslandActivityAttributes.ContentState(
            level: snapshot.level, className: snapshot.className, recentEvent: snapshot.recentEvent)
        do {
            _ = try Activity.request(attributes: attributes,
                                     contentState: state, pushType: nil)
            message = "已启动（系统允许时展示）"
        } catch {
            message = "启动失败：\(error.localizedDescription)"
        }
    }

    private func endAll() {
        Task {
            for activity in Activity<PingIslandActivityAttributes>.activities {
                await activity.end(dismissalPolicy: .default)
            }
        }
        message = "已结束"
    }
}
