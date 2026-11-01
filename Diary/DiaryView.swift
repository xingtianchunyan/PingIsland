import SwiftUI

/// 日记页（执行文档 5.3-2 / 9.7）：按时间展示已结算片段，只读快照
struct DiaryView: View {
    @State private var snapshot: DisplaySnapshot = SnapshotIO.load() ?? DisplaySnapshot()

    var body: some View {
        NavigationStack {
            List {
                if let diaries = snapshot.recentDiaries, !diaries.isEmpty {
                    ForEach(diaries, id: \.self) { entry in
                        Text(entry).font(.callout)
                    }
                } else {
                    Text("还没有日记。完成首次设置并产生已确认修行时长后，这里会自动出现岛上生活的记录。")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("日记")
            .onAppear {
                SettlementCoordinator.settlePending()
                snapshot = SnapshotIO.load() ?? DisplaySnapshot()
            }
        }
    }
}

/// 收藏页（执行文档 5.3-3）：装备藏品，探索中自动发现，无需手动领取
struct CollectionView: View {
    @State private var snapshot: DisplaySnapshot = SnapshotIO.load() ?? DisplaySnapshot()

    var body: some View {
        NavigationStack {
            List {
                if let collection = snapshot.collection, !collection.isEmpty {
                    Section("装备藏品（\(collection.count)）") {
                        ForEach(collection, id: \.self) { Text($0).font(.callout) }
                    }
                } else {
                    Text("收藏会在探索中自动发现，无需任何手动领取。")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("收藏")
            .onAppear {
                SettlementCoordinator.settlePending()
                snapshot = SnapshotIO.load() ?? DisplaySnapshot()
            }
        }
    }
}
