import SwiftUI

/// 设置与恢复（执行文档 5.3-4）
struct SettingsView: View {
    @AppStorage(SharedStore.Keys.onboardingComplete, store: SharedStore.defaults)
    private var onboardingComplete = true

    var body: some View {
        NavigationStack {
            List {
                Section("权限与监控") {
                    Text("重新授权 / 重建监控入口（Phase 2 接入完整恢复流程）")
                        .foregroundStyle(.secondary)
                }
                Section("数据") {
                    Text("账本与快照保存在本机共享容器；无服务器、无账号、无广告。")
                        .foregroundStyle(.secondary)
                }
                Section("版本") {
                    Text("屏之岛 0.1.0 (1) — MVP 引导版")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("设置")
        }
    }
}
