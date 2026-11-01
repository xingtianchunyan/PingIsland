import SwiftUI

/// 原型主界面（执行文档 12.2/12.3）：前台可观察动作切换与生命周期，
/// 12.3 各项真机记录项的入口说明见 README。
@main
struct LabApp: App {
    @StateObject private var controller = LabActionController()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                VStack(spacing: 20) {
                    CharacterView(controller: controller)
                        .frame(height: 120)
                    Text("AnimationIslandLab · 实验原型")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 16) {
                        Button("走路") { controller.switchTo(.walk, reason: "manual") }
                        Button("施法") { controller.switchTo(.cast, reason: "manual") }
                        Button("回退姿态") { controller.switchTo(.idle, reason: "manual") }
                    }
                    // 预设节奏推进帧（12.3-1：前台节奏源，离开 App 后的续播需真机记录）
                    TimelineView(.periodic(from: .now, by: controller.current.frameDuration)) { _ in
                        Color.clear
                            .onAppear(perform: tick)
                            .onChange(of: controller.current) { _ in tick() }
                    }
                    .frame(height: 0)
                    Divider()
                    ScrollView {
                        Text(controller.log.lines.joined(separator: "\n"))
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 160)
                }
                .padding()
                .navigationTitle("动画实验")
                .toolbar {
                    ShareLink(item: controller.log.exportText) {
                        Text("导出日志")
                    }
                }
                .onAppear { controller.log.appendMemorySnapshot() }
            }
        }
    }

    private func tick() {
        controller.advanceFrame()
    }
}
