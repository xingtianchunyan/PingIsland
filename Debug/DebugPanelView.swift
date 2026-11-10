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
    /// 第十九批：默认 7 天，对齐职业觉醒最小观察天数（ClassAwakening.minObservationDays）
    @State private var streakDays = 7
    /// 调试指定骰点（nil = 按运气正常掷骰）
    @State private var diceOverrideOn = false
    @State private var diceOverrideValue = 20
    /// 触发条件开关（第十九批：开了直接满足、关了恢复规则判定）
    @State private var forceGoldRain = false
    @State private var foilOverride = 0
    /// 手动注入：装备（部位/外观/品质）与技能（星期模板/主被动/品质）
    /// 卡牌特效实验台（holo-card v2：实时覆盖角色页卡牌特效组合）
    @ObservedObject private var lab = HoloEffectLab.shared
    @State private var injectSlot: EquipmentSlot = .head
    @State private var injectAppearance = "自动（按 WIS）"
    @State private var injectRarity: Rarity = .purple
    @State private var injectSkillRarity: Rarity = .blue
    @State private var injectWeekday = 1
    @State private var injectActive = true
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
                Picker("阈值分钟", selection: $simMinutes) {
                    ForEach([30, 60, 120, 240, 480], id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("指定骰点（调试）", isOn: $diceOverrideOn)
                if diceOverrideOn {
                    Stepper("骰点：\(diceOverrideValue)", value: $diceOverrideValue, in: 1...20)
                    Text("覆盖当日骰点：<10 仅白/绿装备；=10 必得白绿蓝；10~19 六阶装备或特质技能；20 高级双赏 + 神谕")
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
                    // 第二十一批：连注后"今天"推进到最后注入日，此前各周随之变为上周/更早，
                    // 日记周表与单日记录在测试中可正确滚动
                    simDayOffset += max(0, streakDays - 1)
                    SharedStore.defaults?.set(simDayOffset, forKey: SharedStore.Keys.simDayOffset)
                    simResult = summaries.joined(separator: "\n") + "\n已同步展示快照（今天推进到 +\(simDayOffset) 天）"
                    refresh()
                }
                Button("模拟过一天（新骰点 + 换日神谕）") {
                    simDayOffset += 1
                    SharedStore.defaults?.set(simDayOffset, forKey: SharedStore.Keys.simDayOffset)
                    // 第二十批：过天 = 真实场景的换日——指定骰点开启时先把新日期骰点锁定，再发神谕（骰 20 时）
                    let newDate = simDate(dayOffset: simDayOffset)
                    let base = SettlementCoordinator.store().directory.deletingLastPathComponent()
                    if let service = try? SettlementService(store: SimulatedUsageSource.store(base: base),
                                                          groups: Array(TrainingGroup.allCases),
                                                          characterSeed: SimulatedUsageSource.seed) {
                        if diceOverrideOn {
                            service.debugSetDice(diceOverrideValue, for: newDate)
                        }
                        // 第二十一批：神谕记录的落点取模拟日期当天（此前误用真实 now，
                        // 日记分组把神谕固定塞进现实时间那一天）
                        let oracle = service.startDay(newDate, recordedAt: simDateTime(newDate))
                        SettlementCoordinator.syncDisplayFromSimulated(service.engine)
                        resyncDisplay(note: "已过天到 \(newDate)（\(oracle ? "神谕已发放" : "无神谕")）")
                    } else {
                        resyncDisplay(note: "已过天到 \(newDate)（账本不可读，仅切日期）")
                    }
                }
                if simDayOffset > 0 {
                    Text("模拟日期：今天 +\(simDayOffset) 天（每日新骰点；过天即发当日神谕）")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                if !simResult.isEmpty {
                    Text(simResult).font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("手动注入（直接入账模拟账本）") {
                Picker("装备部位", selection: $injectSlot) {
                    ForEach(EquipmentSlot.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Picker("外观", selection: $injectAppearance) {
                    ForEach(["自动（按 WIS）", "布甲", "皮甲", "铁甲", "机甲"], id: \.self) {
                        Text($0).tag($0)
                    }
                }
                Picker("品质", selection: $injectRarity) {
                    ForEach(Rarity.allCases, id: \.self) { r in
                        Text(rarityLabel(r)).tag(r)
                    }
                }
                Button("注入装备") { injectEquipment() }
                Picker("技能模板", selection: $injectWeekday) {
                    ForEach(1...7, id: \.self) { Text("周\(["一","二","三","四","五","六","日"][$0-1])·\(SkillRules.template(forWeekday: $0).element)").tag($0) }
                }
                Picker("类型", selection: $injectActive) {
                    Text("主动（技能）").tag(true)
                    Text("被动（特质）").tag(false)
                }
                .pickerStyle(.segmented)
                Picker("技能品质", selection: $injectSkillRarity) {
                    ForEach(Rarity.allCases, id: \.self) { r in
                        Text(rarityLabel(r)).tag(r)
                    }
                }
                Button("注入特质/技能") { injectSkill() }
                Text("特质/技能库已实装：掉落按当周日行模板产出（六行元素轮转），注入即入收藏")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Section("触发条件开关（第十九批：开了直接满足，关了恢复规则判定）") {
                Toggle("金雨预览（无视 LUK≥900 门槛）", isOn: $forceGoldRain)
                    .onChange(of: forceGoldRain) { _, on in
                        SharedStore.defaults?.set(on, forKey: SharedStore.Keys.debugForceGoldRain)
                    }
                Picker("闪卡档位预览", selection: $foilOverride) {
                    Text("自动（按规则）").tag(0)
                    Text("普通").tag(1)
                    Text("银边").tag(2)
                    Text("金边").tag(3)
                    Text("全彩").tag(4)
                }
                .onChange(of: foilOverride) { _, value in
                    SharedStore.defaults?.set(value, forKey: SharedStore.Keys.debugFoilOverride)
                }
                Text("角色卡与装备卡即时生效；仅供预览特效，不影响结算数据")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            // 第二十一批：holo-card v2 特效实验台（在闪卡档位预览之上做细粒度组合）
            Section("卡牌特效实验台（holo v2：角色页实时生效）") {
                Toggle("启用实验组合（关闭=按闪卡档位默认）", isOn: $lab.enabled)
                if lab.enabled {
                    Picker("折射纹路", selection: $lab.pattern) {
                        ForEach(RefractionPattern.allCases) { Text($0.rawValue).tag($0) }
                    }
                    ForEach(GlossFinish.allCases) { finish in
                        Toggle(finish.rawValue, isOn: glossBinding(finish))
                    }
                    Picker("金属色调", selection: $lab.tint) {
                        ForEach(MetallicTint.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Toggle("纹路覆盖整卡（关=仅边框描边）", isOn: $lab.fullFace)
                    Text(labEffectSummary)
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Button("恢复档位默认组合", role: .destructive) {
                    lab.resetToTierDefault()
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
            forceGoldRain = SharedStore.defaults?.bool(forKey: SharedStore.Keys.debugForceGoldRain) ?? false
            foilOverride = SharedStore.defaults?.integer(forKey: SharedStore.Keys.debugFoilOverride) ?? 0
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
            lines.append("快照体检：v\(snapshot.snapshotVersion) 等级 \(snapshot.level) "
                + "职业「\(snapshot.className)」 属性 \(snapshot.attributes?.count ?? 0) 项 "
                + "特质技能 \(snapshot.skills?.count ?? 0) 个 装备栏 \(snapshot.equippedDetail?.count ?? 0) 件 "
                + "骰点 \(snapshot.todayDice.map(String.init) ?? "无")")
        } else {
            lines.append("快照：不可读（尚未保存过）")
        }
        // 第十九批：职业觉醒观察进度（连注冲刺默认 7 天 = 觉醒最小观察天数）
        if let engine = currentSimEngine() {
            let p = engine.awakeningProgress
            let minutesText = p.minutes.map { "\($0.key.rawValue) \($0.value)min" }.joined(separator: " ")
            lines.append("觉醒进度：观察 \(p.days)/\(p.requiredDays) 天 · \(minutesText)")
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
                let newEquipment = delta.milestoneGrants.reduce(0) { $0 + $1.allEquipment.count }
                if delta.milestoneGrants.count > 0 {
                    text += "\n活动结算 \(delta.milestoneGrants.count) 次，新装备 \(newEquipment) 件"
                    if let extra = delta.milestoneGrants.compactMap({ MilestoneRules.describeExtra($0) }).first {
                        text += "\n\(extra)"
                    }
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

    /// 模拟日期当天的指定时刻（默认 08:00）：神谕等换日记录的落点，
    /// 保证日记按日分组跟随模拟日期，而非真实 now
    private func simDateTime(_ localDate: String, hour: Int = 8) -> Date {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        let day = f.date(from: localDate) ?? Date()
        return Calendar(identifier: .gregorian)
            .date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
    }

    // MARK: - 实验台辅助

    /// 光泽多选的 Toggle 绑定
    private func glossBinding(_ finish: GlossFinish) -> Binding<Bool> {
        Binding(
            get: { lab.glosses.contains(finish) },
            set: { on in
                if on {
                    lab.glosses.insert(finish)
                } else {
                    lab.glosses.remove(finish)
                }
            })
    }

    private var labEffectSummary: String {
        let pattern = lab.pattern == .none ? "无纹路" : lab.pattern.rawValue
        let glosses = lab.glosses.isEmpty
            ? "无光泽"
            : lab.glosses.map(\.rawValue).sorted().joined(separator: " + ")
        return "当前组合：\(pattern) × \(glosses) × 烫\(lab.tint.rawValue)"
            + (lab.fullFace ? "（整卡）" : "（仅边缘）")
    }

    // MARK: - 手动注入（第二十批）

    private func injectEquipment() {
        let base = SettlementCoordinator.store().directory.deletingLastPathComponent()
        guard let service = try? SettlementService(store: SimulatedUsageSource.store(base: base),
                                                 groups: Array(TrainingGroup.allCases),
                                                 characterSeed: SimulatedUsageSource.seed) else {
            simResult = "注入失败：模拟账本不可读"
            return
        }
        let appearance = injectAppearance == "自动（按 WIS）" ? nil : injectAppearance
        service.debugInjectEquipment(slot: injectSlot, rarity: injectRarity,
                                     appearance: appearance, recordedAt: Date())
        SettlementCoordinator.syncDisplayFromSimulated(service.engine)
        WidgetCenter.shared.reloadAllTimelines()
        simResult = "已注入 \(rarityLabel(injectRarity))\(injectSlot.rawValue)（外观：\(injectAppearance)）"
        refresh()
    }

    private func injectSkill() {
        let base = SettlementCoordinator.store().directory.deletingLastPathComponent()
        guard let service = try? SettlementService(store: SimulatedUsageSource.store(base: base),
                                                 groups: Array(TrainingGroup.allCases),
                                                 characterSeed: SimulatedUsageSource.seed) else {
            simResult = "注入失败：模拟账本不可读"
            return
        }
        service.debugInjectSkill(rarity: injectSkillRarity, isActive: injectActive,
                                 weekday: injectWeekday)
        SettlementCoordinator.syncDisplayFromSimulated(service.engine)
        WidgetCenter.shared.reloadAllTimelines()
        let template = SkillRules.template(forWeekday: injectWeekday)
        let name = injectActive ? template.activeName : template.passiveName
        simResult = "已注入 \(injectActive ? "技能" : "特质")·\(name)（\(rarityLabel(injectSkillRarity))）"
        refresh()
    }

    private func rarityLabel(_ rarity: Rarity) -> String {
        switch rarity {
        case .white: return "白"
        case .green: return "绿"
        case .blue: return "蓝"
        case .purple: return "紫"
        case .orange: return "橙"
        case .red: return "红"
        }
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
