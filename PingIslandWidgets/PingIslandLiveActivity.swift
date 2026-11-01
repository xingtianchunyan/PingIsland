import ActivityKit
import SwiftUI
import WidgetKit

/// Live Activity（执行文档 11.3）：紧凑态/最小态/展开态/锁屏
struct PingIslandLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PingIslandActivityAttributes.self) { context in
            // 锁屏与展开背景视图
            LockScreenView(state: context.state)
                .activityBackgroundTint(Color.cyan.opacity(0.25))
                .activitySystemActionForegroundColor(Color.cyan)
        } dynamicIsland: { context in
            DynamicIsland {
                // 展开态
                DynamicIslandExpandedRegion(.leading) {
                    Text("🏝️").font(.largeTitle)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack {
                        Text(context.state.className).font(.headline)
                        Text("等级 \(context.state.level)").font(.subheadline)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.recentEvent)
                        .font(.caption)
                        .lineLimit(2)
                        .frame(width: 90)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.attributes.characterTitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Text("🏝️")
            } compactTrailing: {
                Text("Lv.\(context.state.level)")
                    .font(.caption)
                    .monospacedDigit()
            } minimal: {
                Text("🏝️")
            }
            .widgetURL(URL(string: "pingisland://character"))
            .keylineTint(Color.cyan)
        }
    }
}

/// 锁屏/展开内容：角色、最近片段、成长摘要、最近结算时间（只读）
struct LockScreenView: View {
    let state: PingIslandActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("🏝️").font(.title)
                VStack(alignment: .leading) {
                    Text(state.className).font(.headline)
                    Text("等级 \(state.level)").font(.subheadline)
                }
            }
            Text(state.recentEvent)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
