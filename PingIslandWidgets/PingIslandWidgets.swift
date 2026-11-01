import SwiftUI
import WidgetKit

/// Widget 扩展：小/中桌面卡片 + Live Activity（执行文档 11.2/11.3）
@main
struct PingIslandWidgets: WidgetBundle {
    var body: some Widget {
        PingIslandSmallWidget()
        PingIslandMediumWidget()
        PingIslandLiveActivity()
    }
}

/// 小尺寸卡片：角色关键帧、等级、最近事件标识
struct PingIslandSmallWidget: Widget {
    let kind = "PingIslandSmallWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SnapshotTimelineProvider()) { entry in
            VStack(spacing: 4) {
                Text("🏝️").font(.largeTitle)
                Text("Lv.\(entry.snapshot.level)").font(.headline)
                Text(entry.snapshot.widgetStatusText)
                    .font(.caption2)
                    .lineLimit(2)
                    .foregroundStyle(.secondary)
            }
            .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("屏之岛·小")
        .description("角色关键帧与最近事件")
        .supportedFamilies([.systemSmall])
    }
}

/// 中尺寸卡片：职业、属性摘要、最近结算时间
struct PingIslandMediumWidget: Widget {
    let kind = "PingIslandMediumWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SnapshotTimelineProvider()) { entry in
            HStack(spacing: 12) {
                Text("🏝️").font(.system(size: 44))
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.snapshot.className).font(.headline)
                    Text("等级 \(entry.snapshot.level)").font(.subheadline)
                    Text(entry.snapshot.isStale ? "休眠 · 等待同步" : "状态：\(entry.snapshot.fatigueText)")
                        .font(.caption).foregroundStyle(.secondary)
                    if let at = entry.snapshot.lastSettlementAt, !entry.snapshot.isStale {
                        Text("最近结算 \(at.formatted(date: .omitted, time: .shortened))")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                Spacer()
            }
            .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("屏之岛·中")
        .description("职业、等级与最近结算")
        .supportedFamilies([.systemMedium])
    }
}

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: DisplaySnapshot
}

/// 只读共享快照；不承诺逐分钟刷新（执行文档 11.2）
struct SnapshotTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: DisplaySnapshot())
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: Date(), snapshot: SnapshotIO.load() ?? DisplaySnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let snapshot = SnapshotIO.load() ?? DisplaySnapshot()
        let entry = SnapshotEntry(date: Date(), snapshot: snapshot)
        // 预排一条合理时间线；不堆积条目模拟视频（执行文档 11.2）。
        // 新鲜快照按 30 分钟跟进；休眠快照放宽到 6 小时后再唤醒检查。
        let minutes = snapshot.isStale ? 360 : 30
        let next = Calendar.current.date(byAdding: .minute, value: minutes, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}
