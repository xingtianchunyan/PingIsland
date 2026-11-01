import SwiftUI

/// 日记页（执行文档 5.3-2）：按时间展示已结算片段（Phase 3 接入账本，现为占位）
struct DiaryView: View {
    var body: some View {
        NavigationStack {
            List {
                Text("还没有日记。完成首次设置并产生已确认修行时长后，这里会自动出现岛上生活的记录。")
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("日记")
        }
    }
}

/// 收藏页（执行文档 5.3-3）：装备/技能/特质收藏（Phase 4 接入内容池，现为占位）
struct CollectionView: View {
    var body: some View {
        NavigationStack {
            List {
                Text("收藏会在探索中自动发现，无需任何手动领取。")
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("收藏")
        }
    }
}
