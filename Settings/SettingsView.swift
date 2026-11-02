import FamilyControls
import PingIslandKit
import SwiftUI

/// 设置与恢复（执行文档 5.3-4 / 13.2 / 13.3）
struct SettingsView: View {
    @AppStorage(SharedStore.Keys.onboardingComplete, store: SharedStore.defaults)
    private var onboardingComplete = true
    @State private var rebuildMessage = ""

    var body: some View {
        NavigationStack {
            List {
                Section("权限与监控") {
                    Button("重新授权并重建监控") { rebuildMonitoring() }
                    if !rebuildMessage.isEmpty {
                        Text(rebuildMessage).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("数据与隐私") {
                    Text("账本、分组与快照仅保存在本机共享容器，核心结算不联网、不上传屏幕使用信息；只保存成长所需的最小里程碑、分组、角色结果与事件记录。")
                    Text("删除方式：卸载 App 即清除全部本地数据。首版无第三方广告与统计 SDK。")
                }
                Section("版本") {
                    Text("屏之岛 0.1.0 (1) — MVP 引导版")
                        .foregroundStyle(.secondary)
                }
                Section("内部测试") {
                    // Release IPA（CI 产物）也需要此面板做真机验证；模拟源账本独立隔离，不影响真实数据
                    NavigationLink("调试面板（含模拟数据）") {
                        DebugPanelView()
                    }
                }
            }
            .navigationTitle("设置")
        }
    }

    /// 恢复入口（执行文档 13.3）：重新请求授权并按已保存分组重建监控。
    private func rebuildMonitoring() {
        RecoveryService.rebuildMonitoring { rebuildMessage = $0 }
    }
}
