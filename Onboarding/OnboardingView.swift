import DeviceActivity
import FamilyControls
import SwiftUI

/// 首次设置流程（执行文档 5.1）：
/// 欢迎与能力边界 → 请求授权 → 选择修行组 App → 注册监控 → 完成
struct OnboardingView: View {
    let onComplete: () -> Void

    @State private var selection = FamilyActivitySelection()
    @State private var step = 0
    @State private var authStatus = AuthorizationCenter.shared.authorizationStatus
    @State private var errorText = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if step == 0 {
                    welcome
                } else {
                    picker
                }
            }
            .padding()
            .navigationTitle("屏之岛")
        }
    }

    private var welcome: some View {
        VStack(spacing: 16) {
            Text("🏝️").font(.system(size: 64))
            Text("欢迎来到屏之岛")
                .font(.title)
            Text("你正常使用手机，岛上的角色会依据**已确认的使用里程碑**自动成长。无需每日领取，无需手动操作。\n\n本应用只记录系统能够确认的里程碑，不推断你的真实行为。")
                .font(.body)
                .foregroundStyle(.secondary)
            Button("下一步：授权与选择") { step = 1 }
                .buttonStyle(.borderedProminent)
        }
    }

    private var picker: some View {
        VStack(spacing: 12) {
            Text("选择想纳入修行的 App（可多选）")
                .font(.headline)
            FamilyActivityPicker(selection: $selection)
            if !errorText.isEmpty {
                Text(errorText).foregroundStyle(.red).font(.caption)
            }
            Button("完成设置") { finish() }
                .buttonStyle(.borderedProminent)
                .disabled(selection.applicationTokens.isEmpty && selection.categoryTokens.isEmpty)
        }
    }

    private func finish() {
        // 1. 请求 Family Controls 授权
        AuthorizationCenter.shared.requestAuthorization { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    persistSelectionAndRegister()
                case .failure(let error):
                    // 授权失败：允许查看说明，不生成虚构成长（执行文档 5.1）
                    errorText = "授权未完成：\(error.localizedDescription)。可稍后在设置中重新授权。"
                }
            }
        }
    }

    private func persistSelectionAndRegister() {
        // 2. 保存选择（Phase 2 接入训练组映射与 token 去重）
        let version = (SharedStore.defaults?.integer(forKey: SharedStore.Keys.selectionVersion) ?? 0) + 1
        SharedStore.defaults?.set(version, forKey: SharedStore.Keys.selectionVersion)
        // 3. 注册监控（DeviceActivity）
        MonitoringRegistrar.register(selection: selection)
        // 4. 初始化展示快照
        SnapshotIO.save(DisplaySnapshot())
        onComplete()
    }
}
