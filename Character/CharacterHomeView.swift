import SwiftUI

/// 角色主页（执行文档 5.3-1）：只读展示快照，无"领取"类操作
struct CharacterHomeView: View {
    @State private var snapshot: DisplaySnapshot = SnapshotIO.load() ?? DisplaySnapshot()

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("🏝️")
                    .font(.system(size: 72))
                Text(snapshot.className)
                    .font(.title2)
                Text("等级 \(snapshot.level)")
                    .font(.headline)
                Text(snapshot.recentEvent)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("状态：\(snapshot.fatigueText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let at = snapshot.lastSettlementAt {
                    Text("最近结算：\(at.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                LiveActivityControls()
            }
            .navigationTitle("屏之岛")
            .onAppear { snapshot = SnapshotIO.load() ?? DisplaySnapshot() }
        }
    }
}
