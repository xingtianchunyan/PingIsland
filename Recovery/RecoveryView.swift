import PingIslandKit
import SwiftUI

/// 异常恢复页（执行文档 13.3）：授权失效/监控重建/数据状态说明与恢复动作。
/// 不虚构成长：授权失效只说明与重建，绝不生成模拟数据。
struct RecoveryView: View {
    @State private var snapshot: DisplaySnapshot = SnapshotIO.load() ?? DisplaySnapshot()
    @State private var journalCount = 0
    @State private var message = ""

    var body: some View {
        NavigationStack {
            List {
                Section("数据状态") {
                    LabeledContent("授权", value: RecoveryService.authStatusText)
                    LabeledContent("快照版本", value: "v\(snapshot.snapshotVersion)")
                    if let at = snapshot.lastSettlementAt {
                        LabeledContent("最近结算", value: at.formatted(date: .abbreviated, time: .shortened))
                    } else {
                        LabeledContent("最近结算", value: "尚无")
                    }
                    LabeledContent("已入账事件", value: "\(journalCount)")
                    LabeledContent("当前状态", value: snapshot.isStale ? "休眠／等待同步" : snapshot.fatigueText)
                }
                Section("恢复动作") {
                    Button("重新授权并重建监控") {
                        RecoveryService.rebuildMonitoring { message = $0 }
                    }
                    if !message.isEmpty {
                        Text(message).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("说明") {
                    Text("授权失效期间停止成长，历史保留，恢复后不重复结算。")
                    Text("监控注册失败保留角色，可在此重建；单组失败不影响其他组。")
                    Text("数据库写入中断自动恢复有效快照，不会半套奖励入账。")
                    Text("Live Activity 结束后桌面卡片继续展示同一快照。")
                    Text("导入旧备份后奖励身份保留，但旧 token 与授权不默认可用，需重新设置监控。")
                }
            }
            .navigationTitle("恢复")
            .onAppear(perform: refresh)
        }
    }

    private func refresh() {
        SettlementCoordinator.settlePending()
        snapshot = SnapshotIO.load() ?? DisplaySnapshot()
        if let data = try? SettlementCoordinator.store().loadJournal(),
           let events = try? JSONDecoder().decode([UsageEvent].self, from: data) {
            journalCount = events.count
        } else {
            journalCount = 0
        }
    }
}
