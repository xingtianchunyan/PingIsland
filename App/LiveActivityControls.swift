import ActivityKit
import SwiftUI

/// Live Activity 便捷控制（执行文档 11.3：首开可创建一次）
struct LiveActivityControls: View {
    @State private var message = ""
    /// 防重入（第十五次真机修复）：结束/创建活动是一个异步序列，执行期间禁用按钮。
    /// 连续点击会产生互相残杀的并发任务——后一个 Task 的"结束全部"会把前一个 Task
    /// 刚创建的活动一并杀掉，表现为灵动岛/锁屏内容快速闪烁、活动净存活为零、
    /// 锁屏来不及弹出"始终允许实时活动"授权卡。
    @State private var busy = false

    var body: some View {
        VStack(spacing: 8) {
            Button("开启灵动岛 / 锁屏实时活动") { start() }
                .disabled(busy)
            Button("结束实时活动") { endAll() }
                .foregroundStyle(.secondary)
                .disabled(busy)
            if !message.isEmpty {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
    }

    private func start() {
        guard !busy else { return }
        // 权限预检：被拒时给出确切设置路径，不再静默失败
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            message = "系统未允许实时活动：设置→屏之岛→实时活动 打开；另检查 设置→面容ID与密码→锁定时允许访问→实时活动。"
            LiveActivityDiagnostics.record("开启：预检被拒（areActivitiesEnabled=false）")
            return
        }
        busy = true
        // 11.3：同一时刻只保留一个活动。
        // 注意：结束旧活动与创建新活动必须在同一异步序列里——若用独立 Task 先结束后创建，
        // 结束任务可能在新活动创建之后才执行，把刚创建的活动一起杀掉。
        Task {
            defer { busy = false }
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
                LiveActivityDiagnostics.record("开启：成功，存活 \(count) 个")
            } catch {
                message = "启动失败：\(error.localizedDescription)"
                LiveActivityDiagnostics.record("开启：失败 \(String(describing: type(of: error))):\(error.localizedDescription)")
            }
        }
    }

    private func endAll() {
        guard !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            // .immediate：立即从灵动岛/锁屏移除；.default 会保留到系统超时（锁屏残留的根因）
            for activity in Activity<PingIslandActivityAttributes>.activities {
                await activity.end(dismissalPolicy: .immediate)
            }
            let remaining = Activity<PingIslandActivityAttributes>.activities.count
            message = remaining == 0 ? "已结束" : "仍有 \(remaining) 个活动未能结束"
            LiveActivityDiagnostics.record("结束：剩余 \(remaining) 个")
        }
    }
}
