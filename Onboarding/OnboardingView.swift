import FamilyControls
import PingIslandKit
import SwiftUI

/// 首次设置流程（执行文档 5.1/5.2）：
/// 欢迎与能力边界 → 请求授权 → 依次选择八个修行组的 App（token 查重）→
/// 注册监控 → 初始化角色 → 完成。授权失败允许查看说明，不生成虚构成长。
struct OnboardingView: View {
    let onComplete: () -> Void

    @State private var step = 0
    @State private var selections: [TrainingGroup: FamilyActivitySelection] = [:]
    @State private var errorText = ""

    private var groups: [TrainingGroup] { GroupSelection.orderedGroups }
    private var currentGroup: TrainingGroup? {
        step >= 1 && step <= groups.count ? groups[step - 1] : nil
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if step == 0 {
                    welcome
                } else if step <= groups.count, let group = currentGroup {
                    groupPage(group)
                } else {
                    confirmPage
                }
            }
            .padding()
            .navigationTitle("屏之岛")
        }
    }

    // MARK: 步骤 0：欢迎与能力边界

    private var welcome: some View {
        VStack(spacing: 16) {
            Text("🏝️").font(.system(size: 64))
            Text("欢迎来到屏之岛")
                .font(.title)
            Text("你正常使用手机，岛上的角色会依据**已确认的使用里程碑**自动成长。无需每日领取，无需手动操作。\n\n接下来请为八个修行组各选择一些 App；同一个 App 只能属于一个组。\n\n（自签/侧载环境下屏幕使用时间授权可能不可用，可先跳过进入应用，稍后在设置页重新授权。）")
                .font(.body)
                .foregroundStyle(.secondary)
            Button("开始选择") { step = 1 }
                .buttonStyle(.borderedProminent)
            Button("暂不授权，先进入应用") { enterWithoutAuthorization() }
                .buttonStyle(.bordered)
                .font(.callout)
        }
    }

    // MARK: 步骤 1~8：逐组选择

    private func groupPage(_ group: TrainingGroup) -> some View {
        let binding = Binding<FamilyActivitySelection>(
            get: { selections[group] ?? FamilyActivitySelection() },
            set: { newValue in
                // 一个 token 只属一个组：自动移除被其他组占用的选择（14.3 重复选择被阻止）
                selections[group] = GroupSelection.sanitized(newValue, for: group, existing: selections)
            })

        let authorized = AuthorizationCenter.shared.authorizationStatus == .approved
        return VStack(spacing: 12) {
            VStack(spacing: 4) {
                Text("第 \(step) / \(groups.count) 组")
                    .font(.caption).foregroundStyle(.secondary)
                Text(group.rawValue).font(.title2)
                Text("情境倾向：\(group.inclination.rawValue) · 对应职业：\(group.correspondingClass.rawValue)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if authorized {
                FamilyActivityPicker(selection: binding)
            } else {
                // 未授权（自签环境常见）：无法列出具体 App，直接跳过即可
                Text("尚未获得屏幕使用时间授权，无法列出 App。\n可依次跳过，进入应用后可在设置页重新授权。")
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Spacer()
            }
            HStack {
                Button("上一组") { step -= 1 }.disabled(step == 1)
                Spacer()
                Button(step == groups.count ? "查看汇总" : "下一组") { step += 1 }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: 汇总与完成

    private var confirmPage: some View {
        VStack(spacing: 16) {
            Text("修行组汇总").font(.title2)
            List {
                let total = selections.values.reduce(0) {
                    $0 + $1.applicationTokens.count + $1.categoryTokens.count + $1.webDomainTokens.count
                }
                if total == 0 {
                    Text("尚未选择任何 App。进入后将处于无监控模式，可在设置页的调试面板用模拟数据体验全部功能。")
                        .font(.callout).foregroundStyle(.secondary)
                }
                ForEach(Array(selections.keys), id: \.self) { group in
                    let s = selections[group] ?? FamilyActivitySelection()
                    let count = s.applicationTokens.count + s.categoryTokens.count
                        + s.webDomainTokens.count
                    if count > 0 {
                        Text("\(group.rawValue)：\(count) 项")
                    }
                }
            }
            .listStyle(.plain)
            if !errorText.isEmpty {
                Text(errorText).foregroundStyle(.red).font(.caption)
                Button("暂不授权，进入应用（稍后可重新授权）") { enterWithoutAuthorization() }
                    .font(.callout)
            }
            Button("完成设置") { finish() }
                .buttonStyle(.borderedProminent)
        }
    }

    private func finish() {
        AuthorizationCenter.shared.requestAuthorization { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    persistAndRegister()
                case .failure(let error):
                    // 授权失败：允许跳过进入应用（自签环境帮助程序通信失败属已知限制），不生成虚构成长
                    errorText = "授权未完成：\(error.localizedDescription)。可稍后在设置中重新授权。"
                }
            }
        }
    }

    /// 降级进入（执行文档 13.3 精神）：无授权 = 无监控无真实成长；
    /// 保存分组与角色种子，跳过监控注册，之后可用调试面板的模拟数据体验。
    private func enterWithoutAuthorization() {
        persistAndRegister(skipMonitoring: true)
    }

    private func persistAndRegister(skipMonitoring: Bool = false) {
        // 保存分组（version 递增，供归属与重建使用）
        var state = GroupSelection.State()
        for (group, s) in selections {
            let count = s.applicationTokens.count + s.categoryTokens.count + s.webDomainTokens.count
            if count > 0 { state.selections[group.rawValue] = s }
        }
        GroupSelection.save(state)

        // 角色种子：首建后不变，保证随机结果可重建
        if SharedStore.defaults?.object(forKey: "characterSeed.v1") == nil {
            SharedStore.defaults?.set(Int(Date().timeIntervalSince1970) & 0x7fffffff,
                                      forKey: "characterSeed.v1")
        }

        // 注册监控（每组独立活动与事件）；跳过授权时不注册，稍后可在设置页重建
        if !skipMonitoring {
            MonitoringRegistrar.register(selections: selections)
        }
        SnapshotIO.save(DisplaySnapshot())
        onComplete()
    }
}
