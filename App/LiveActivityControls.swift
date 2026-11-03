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
        // 权限预检：被拒时给出确切设置路径，不再静默失败
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            message = "系统未允许实时活动：设置→屏之岛→实时活动 打开；另检查 设置→面容ID与密码→锁定时允许访问→实时活动。"
            return
        }
        // 11.3：同一时刻只保留一个活动。
        // 注意：结束旧活动与创建新活动必须在同一异步序列里——若用独立 Task 先结束后创建，
        // 结束任务可能在新活动创建之后才执行，把刚创建的活动一起杀掉。
        Task {
            for activity in Activity<PingIslandActivityAttributes>.activities {
                await activity.end(dismissalPolicy: .immediate)
            }
            let snapshot = SnapshotIO.load() ?? DisplaySnapshot()
            let attributes = PingIslandActivityAttributes(characterTitle: "岛上居民")
            let state = PingIslandActivityAttributes.ContentState(
                level: snapshot.level, className: snapshot.className, recentEvent: snapshot.recentEvent)
            do {
                _ = try Activity.request(attributes: attributes,
                                         contentState: state, pushType: nil)
                let count = Activity<PingIslandActivityAttributes>.activities.count
                message = "已启动，存活活动 \(count) 个。注意：App 在前台时灵动岛不显示本活动，退回桌面或锁屏可见。"
            } catch {
                message = "启动失败：\(error.localizedDescription)"
            }
        }
    }

    private func endAll() {
        Task {
            // .immediate：立即从灵动岛/锁屏移除；.default 会保留到系统超时（锁屏残留的根因）
            for activity in Activity<PingIslandActivityAttributes>.activities {
                await activity.end(dismissalPolicy: .immediate)
            }
            let remaining = Activity<PingIslandActivityAttributes>.activities.count
            message = remaining == 0 ? "已结束" : "仍有 \(remaining) 个活动未能结束"
        }
    }
}
