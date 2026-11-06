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
    @State private var simDayOffset = 0
    /// 连注冲刺：连续 N 个模拟日、每天 480 分钟（快速拉高等级/触发高骰点条件）
    @State private var streakDays = 3
    /// 调试指定骰点（nil = 按运气正常掷骰）
    @State private var diceOverrideOn = false
    @State private var diceOverrideValue = 20
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
                Stepper("阈值分钟：\(simMinutes)", value: $simMinutes, in: 30...480, step: 30)
                // 快捷档位（第十八批）：常用阈值一键设置
                HStack(spacing: 8) {
                    ForEach([30, 60, 120, 240, 480], id: \.self) { value in
                        Button("\(value)") { simMinutes = value }
                            .font(.caption)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(simMinutes == value ? .red.opacity(0.25) : Color(.secondarySystemGroupedBackground),
                                        in: Capsule())
                            .foregroundStyle(simMinutes == value ? .red : .secondary)
                    }
                }
                Toggle("指定骰点（调试）", isOn: $diceOverrideOn)
                if diceOverrideOn {
                    Stepper("骰点：\(diceOverrideValue)", value: $diceOverrideValue, in: 1...20)
                    Text("覆盖当日骰点：技能抽选门槛 ≥10；20 = 每分钟必掉且触发神谕")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Button("注入模拟事件并结算") {
                    injectSimulated(dayOffset: simDayOffset, minutes: simMinutes)
                }
                // 连注冲刺（第十八批）：一次把连续 N 个模拟日各注入 480 分钟，快速触达高等级/闪卡档位
                HStack {
                    Stepper("连注天数：\(streakDays)", value: $streakDays, in: 1...7)
                }
                Button("连注冲刺（每天 480 分钟，等级飙升）") {
                    var summaries: [String] = []
                    for i in 0..<streakDays {
                        summaries.append(injectSimulated(dayOffset: simDayOffset + i,
                                                         minutes: 480, quiet: true))
                    }
                    simResult = summaries.joined(separator: "\n") + "\n已同步展示快照"
                    refresh()
                }
                Button("模拟过一天（不注入事件，仅切换日期）") {
                    simDayOffset += 1
                    SharedStore.defaults?.set(simDayOffset, forKey: SharedStore.Keys.simDayOffset)
                    // 仅切换日期：按新日期重骰并刷新展示，不产生任何结算
                    resyncDisplay(note: "已过天到 \(simDate(dayOffset: simDayOffset))（未注入事件）")
                }
                if simDayOffset > 0 {
                    Text("模拟日期：今天 +\(simDayOffset) 天（每日新骰点）")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                if !simResult.isEmpty {
                    Text(simResult).font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("测试刷新") {
                Button("刷新展示（重新同步快照/三个页面）") {
                    resyncDisplay(note: "已重新同步展示快照")
                }
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
                    simDayOffset = 0
                    SharedStore.defaults?.set(0, forKey: SharedStore.Keys.simDayOffset)
                    // 用全新引擎同步展示：等级/属性/装备/特质/骰点一并归零
                    let fresh = SettlementEngine(groups: Array(TrainingGroup.allCases),
                                                 characterSeed: SimulatedUsageSource.seed)
                    SettlementCoordinator.syncDisplayFromSimulated(fresh)
                    WidgetCenter.shared.reloadAllTimelines()
                    simResult = "模拟账本已清空，展示已重置"
                    refresh()
                }
            }
        }
        .navigationTitle("调试面板")
        .onAppear {
            anomalySleepOn = SharedStore.defaults?.bool(forKey: SharedStore.Keys.anomalySleep) ?? false
            simDayOffset = SharedStore.defaults?.integer(forKey: SharedStore.Keys.simDayOffset) ?? 0
            refresh()
        }
    }

    // MARK: - 状态与事件

    private func refresh() {
        var lines: [String] = []
        lines.append("授权：\(authStatusText)")
        lines.append("App Group：\(SharedStore.appGroup)")
        if let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: SharedStore.appGroup) {
            lines.append("共享容器：可用（\(container.path)）")
        } else {
            lines.append("共享容器：不可用（签名未授权 App Group——小组件将无法同步）")
        }
        if let snapshot = SnapshotIO.load() {
            lines.append("快照：v\(snapshot.snapshotVersion) 等级 \(snapshot.level)")
        } else {
            lines.append("快照：不可读（尚未保存过）")
        }
        lines.append("账本格式：JSON v1（状态+日志，原子写）")
        if let at = SharedStore.defaults?.object(forKey: SharedStore.Keys.monitorRegisteredAt) as? Date {
            lines.append("监控注册：\(at)")
        } else {
            lines.append("监控注册：未注册或注册失败")
        }
        // Live Activity 诊断（第十五批修复）：设置页每次开启/结束的结果与错误落在此处
        let laDiag = LiveActivityDiagnostics.recentLines()
        if laDiag.isEmpty {
            lines.append("灵动岛诊断：暂无记录（在设置页开启实时活动后可见）")
        } else {
            for entry in laDiag.suffix(3) {
                lines.append("灵动岛：\(entry)")
            }
        }
        lines.append("分组版本：\(SharedStore.defaults?.integer(forKey: SharedStore.Keys.selectionVersion) ?? 0)")
        let simBase = SettlementCoordinator.store().directory.deletingLastPathComponent()
        lines.append("生产账本：\(SettlementCoordinator.store().directory.path)")
        lines.append("模拟账本：\(SimulatedUsageSource.store(base: simBase).directory.path)")
        lines.append("模拟高水位：\(SimulatedUsageSource.eventCount(base: simBase)) 条事件")
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

    /// 当前模拟账本重建出的引擎（无新结算；过天/刷新/展示同步用）
    private func currentSimEngine() -> SettlementEngine? {
        let base = SettlementCoordinator.store().directory.deletingLastPathComponent()
        guard let service = try? SettlementService(store: SimulatedUsageSource.store(base: base),
                                                 groups: Array(TrainingGroup.allCases),
                                                 characterSeed: SimulatedUsageSource.seed)
        else { return nil }
        return service.engine
    }

    /// 重同步展示链路（快照 → Widget / Live Activity），不产生结算
    private func resyncDisplay(note: String) {
        guard let engine = currentSimEngine() else {
            simResult = "重同步失败：模拟账本不可读"
            return
        }
        SettlementCoordinator.syncDisplayFromSimulated(engine)
        WidgetCenter.shared.reloadAllTimelines()
        simResult = note
        refresh()
    }

    /// 注入一个模拟事件并结算；返回结果摘要（quiet = 连注冲刺用：不写 simResult、不 refresh）
    @discardableResult
    private func injectSimulated(dayOffset: Int = 0, minutes: Int? = nil,
                                 quiet: Bool = false) -> String {
        let minutes = minutes ?? simMinutes
        let base = SettlementCoordinator.store().directory.deletingLastPathComponent()
        do {
            let service = try SettlementService(store: SimulatedUsageSource.store(base: base),
                                                groups: Array(TrainingGroup.allCases),
                                                characterSeed: SimulatedUsageSource.seed)
            // 结算时间取模拟日期的当前时刻：日记/装备获得时间与"今天"分区过滤保持一致。
            // 第十八批修复：此前误传真实 now，过天后（dayOffset>0）新获得装备永不落入"今日获得"。
            let cal = Calendar(identifier: .gregorian)
            let now = Date()
            let simDay = cal.date(byAdding: .day, value: dayOffset, to: now) ?? now
            let time = cal.dateComponents([.hour, .minute, .second], from: now)
            let confirmedAt = cal.date(bySettingHour: time.hour ?? 12,
                                       minute: time.minute ?? 0,
                                       second: time.second ?? 0,
                                       of: simDay) ?? simDay
            let localDate = simDate(dayOffset: dayOffset)
            let event = SimulatedUsageSource.makeEvent(
                group: simGroup, thresholdMinutes: minutes,
                localDate: localDate, confirmedAt: confirmedAt,
                sequence: SimulatedUsageSource.eventCount(base: base) + 1,
                diceOverride: diceOverrideOn ? diceOverrideValue : nil)
            let outcome = service.process(event)
            let dice = service.engine.segments[localDate]?.dice?.value ?? 0
            let newMinutes = (outcome == .duplicate) ? 0
                : ({ if case .settled(let d) = outcome { return d.newMinutes }; return 0 }())
            var text = "【模拟数据】日期 \(localDate) · 新增入账 \(newMinutes) 分钟 · 骰点 \(dice)\n"
                + "结算=\(outcome) 等级=\(service.engine.level) "
                + "日记=\(service.engine.diary.count) 条 高水位=\(SimulatedUsageSource.eventCount(base: base))"
            if case .settled(let delta) = outcome {
                let newEquipment = delta.explorations.reduce(0) { $0 + $1.equipment.count }
                if delta.explorations.count > 0 {
                    text += "\n探索 \(delta.explorations.count) 次，新装备 \(newEquipment) 件"
                }
                if delta.newMinutes == 0 {
                    text += "\n该事件无新增入账分钟（同组同日该阈值已入账，补差不倒退）。调高阈值或过天再注入。"
                }
            }
            // 同步到展示链路：快照 → Widget / Live Activity，角色页/日记页立即可见
            SettlementCoordinator.syncDisplayFromSimulated(service.engine)
            WidgetCenter.shared.reloadAllTimelines()
            if !quiet {
                text += "\n已同步展示快照并请求 Widget 刷新（当前 Widget 显示为模拟数据）"
                simResult = text
                refresh()
            }
            return text
        } catch {
            let text = "模拟结算失败：\(error.localizedDescription)"
            if !quiet { simResult = text; refresh() }
            return text
        }
    }

    /// 模拟日期：今天 + dayOffset 天（yyyy-MM-dd），用于跨天测试每日骰子
    private func simDate(dayOffset: Int) -> String {
        let day = Calendar(identifier: .gregorian)
            .date(byAdding: .day, value: dayOffset, to: Date()) ?? Date()
        return dateString(day)
    }

    // MARK: - Live Activity 测试更新

    private func pushLiveActivity() {
        let snapshot = SnapshotIO.load() ?? DisplaySnapshot()
        let state = PingIslandActivityAttributes.ContentState(
            level: snapshot.level, className: snapshot.className, recentEvent: snapshot.recentEvent)
        let activities = Activity<PingIslandActivityAttributes>.activities
        guard !activities.isEmpty else {
            message = "无存活活动：请在设置页先开启实时活动"
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
