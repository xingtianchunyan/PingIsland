import ActivityKit
import FamilyControls
import Foundation
import PingIslandKit
import SwiftUI
import WidgetKit

/// 调试面板（执行文档 13.1）。自测期间全构建可见（Release IPA 是真机验证载体）；
/// 模拟事件经 SimulatedUsageSource 进入独立账本，不与生产 DeviceActivity 账本混写。
struct DebugPanelView: View {
    @State private var simGroup: TrainingGroup = .games
    @State private var simMinutes = 30
    @State private var simResult = ""
    @State private var statusLines: [String] = []
    @State private var recentEvents: [String] = []
    @State private var highWaterMark = 0
    @State private var message = ""
    @State private var anomalySleepOn = false

    var body: some View {
        List {
            Section("运行状态") {
                ForEach(statusLines, id: \.self) { Text($0).font(.caption) }
            }
            Section("最近已处理事件（高水位 \(highWaterMark)）") {
                if recentEvents.isEmpty {
                    Text("暂无").foregroundStyle(.secondary)
                } else {
                    ForEach(recentEvents, id: \.self) { Text($0).font(.caption2) }
                }
            }
            Section {
                HStack {
                    Text("模拟数据")
                        .font(.caption).bold()
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.red.opacity(0.15), in: Capsule())
                        .foregroundStyle(.red)
                    Spacer()
                }
                Picker("修行组", selection: $simGroup) {
                    ForEach(GroupSelection.orderedGroups, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Stepper("阈值分钟：\(simMinutes)", value: $simMinutes, in: 5...480, step: 5)
                Button("注入模拟事件并结算") { injectSimulated() }
                if !simResult.isEmpty {
                    Text(simResult).font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("测试刷新") {
                Button("触发 Widget 时间线刷新") {
                    WidgetCenter.shared.reloadAllTimelines()
                    message = "已请求刷新 Widget"
                }
                Button("推送 Live Activity 测试更新") { pushLiveActivity() }
                if !message.isEmpty {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("诊断") {
                Button(anomalySleepOn ? "清除异常休眠标记" : "标记异常休眠（测 11.4 最高优先级）") {
                    anomalySleepOn.toggle()
                    SharedStore.defaults?.set(anomalySleepOn, forKey: SharedStore.Keys.anomalySleep)
                }
                ShareLink(item: diagnosticReport()) {
                    Text("导出脱敏诊断日志")
                }
                Button("重置模拟数据", role: .destructive) {
                    SimulatedUsageSource.reset(base: SettlementCoordinator.store().directory.deletingLastPathComponent())
                    simResult = "模拟账本已清空"
                }
            }
        }
        .navigationTitle("调试面板")
        .onAppear {
            anomalySleepOn = SharedStore.defaults?.bool(forKey: SharedStore.Keys.anomalySleep) ?? false
            refresh()
        }
    }

    // MARK: - 状态与事件

    private func refresh() {
        var lines: [String] = []
        lines.append("授权：\(authStatusText)")
        lines.append("App Group：\(SharedStore.appGroup)")
        lines.append("账本格式：JSON v1（状态+日志，原子写）")
        if let at = SharedStore.defaults?.object(forKey: SharedStore.Keys.monitorRegisteredAt) as? Date {
            lines.append("监控注册：\(at)")
        } else {
            lines.append("监控注册：未注册或注册失败")
        }
        lines.append("分组版本：\(SharedStore.defaults?.integer(forKey: SharedStore.Keys.selectionVersion) ?? 0)")
        let simBase = SettlementCoordinator.store().directory.deletingLastPathComponent()
        lines.append("生产账本：\(SettlementCoordinator.store().directory.path)")
        lines.append("模拟账本：\(SimulatedUsageSource.store(base: simBase).directory.path)")
        statusLines = lines

        let store = SettlementCoordinator.store()
        if let data = try? store.loadJournal(),
           let events = try? JSONDecoder().decode([UsageEvent].self, from: data) {
            highWaterMark = events.count
            recentEvents = events.suffix(20).reversed().map {
                "\($0.localDate) \($0.group.rawValue) \($0.thresholdMinutes)min — \($0.stableEventID)"
            }
        } else {
            highWaterMark = 0
            recentEvents = []
        }
    }

    private var authStatusText: String {
        switch AuthorizationCenter.shared.authorizationStatus {
        case .notDetermined: return "未请求"
        case .denied: return "已拒绝"
        case .approved: return "已授权"
        @unknown default: return "未知"
        }
    }

    // MARK: - 模拟数据（独立账本）

    private func injectSimulated() {
        let base = SettlementCoordinator.store().directory.deletingLastPathComponent()
        do {
            let service = try SettlementService(store: SimulatedUsageSource.store(base: base),
                                                groups: Array(TrainingGroup.allCases),
                                                characterSeed: SimulatedUsageSource.seed)
            let now = Date()
            let event = SimulatedUsageSource.makeEvent(
                group: simGroup, thresholdMinutes: simMinutes,
                localDate: dateString(now), confirmedAt: now,
                sequence: SimulatedUsageSource.eventCount(base: base) + 1)
            let outcome = service.process(event)
            simResult = "【模拟数据】结算=\(outcome) 等级=\(service.engine.level) "
                + "日记=\(service.engine.diary.count) 条 高水位=\(SimulatedUsageSource.eventCount(base: base))"
        } catch {
            simResult = "模拟结算失败：\(error.localizedDescription)"
        }
    }

    // MARK: - Live Activity 测试更新

    private func pushLiveActivity() {
        let snapshot = SnapshotIO.load() ?? DisplaySnapshot()
        let state = PingIslandActivityAttributes.ContentState(
            level: snapshot.level, className: snapshot.className, recentEvent: snapshot.recentEvent)
        let activities = Activity<PingIslandActivityAttributes>.activities
        guard !activities.isEmpty else {
            message = "无存活活动：请在角色页先开启实时活动"
            return
        }
        for activity in activities {
            Task { await activity.update(using: state) }
        }
        message = "已推送更新到 \(activities.count) 个活动"
    }

    // MARK: - 脱敏诊断报告（不含 token / 真实 App 名称）

    private func diagnosticReport() -> String {
        var lines: [String] = []
        lines.append("# 屏之岛诊断日志（脱敏）")
        lines.append("时间：\(Date())")
        lines.append(contentsOf: statusLines)
        lines.append("高水位：\(highWaterMark)")
        lines.append("--- 最近事件（脱敏 ID）---")
        lines.append(contentsOf: recentEvents)
        if let monitorLog = SharedStore.defaults?.stringArray(forKey: "monitor.log.v1") {
            lines.append("--- 监控日志 ---")
            lines.append(contentsOf: monitorLog)
        }
        if let registerLog = SharedStore.defaults?.stringArray(forKey: "monitor.register.v1") {
            lines.append("--- 注册日志 ---")
            lines.append(contentsOf: registerLog)
        }
        if let snapshot = SnapshotIO.load() {
            lines.append("--- 快照 v\(snapshot.snapshotVersion) ---")
            lines.append("等级 \(snapshot.level) · \(snapshot.className) · 疲劳档 \(snapshot.fatigueStage)")
        }
        return lines.joined(separator: "\n")
    }

    private func dateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }
}
