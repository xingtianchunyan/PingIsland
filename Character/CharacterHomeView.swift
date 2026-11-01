import PingIslandKit
import SwiftUI

/// 角色主页（执行文档 5.3-1）：只读展示快照，无"领取"类操作
struct CharacterHomeView: View {
    @State private var snapshot: DisplaySnapshot = SnapshotIO.load() ?? DisplaySnapshot()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 12) {
                        Text("🏝️")
                            .font(.system(size: 64))
                        Text(snapshot.className)
                            .font(.title2)
                        Text("等级 \(snapshot.level)")
                            .font(.headline)
                        Text("状态：\(snapshot.fatigueText)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let banner = snapshot.bannerText {
                            Text(banner)
                                .font(.caption)
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(.indigo.opacity(0.12), in: Capsule())
                                .foregroundStyle(.indigo)
                        }
                        Text(snapshot.recentEvent)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let at = snapshot.lastSettlementAt {
                            Text("最近结算：\(at.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        LiveActivityControls()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }

                Section("六维属性（初始）") {
                    if let attributes = snapshot.attributes, !attributes.isEmpty {
                        let ordered = Attribute.allCases.map { ($0.rawValue, attributes[$0.rawValue] ?? 0) }
                        ForEach(ordered, id: \.0) { name, value in
                            HStack {
                                Text(name).font(.caption).frame(width: 36, alignment: .leading)
                                ProgressView(value: Double(value), total: 20)
                                    .tint(.teal)
                                Text("\(value)")
                                    .font(.caption.monospacedDigit())
                                    .frame(width: 24, alignment: .trailing)
                            }
                        }
                    } else {
                        Text("完成首次设置并结算后展示").foregroundStyle(.secondary)
                    }
                }

                Section("装备（自动择优）") {
                    if let equipment = snapshot.equipment, !equipment.isEmpty {
                        ForEach(equipment, id: \.self) { Text($0).font(.caption) }
                    } else {
                        Text("探索获得装备后展示").foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("屏之岛")
            .onAppear {
                // 消费监控扩展积累的待结算事件；无新数据时零开销
                SettlementCoordinator.settlePending()
                snapshot = SnapshotIO.load() ?? DisplaySnapshot()
            }
        }
    }
}
