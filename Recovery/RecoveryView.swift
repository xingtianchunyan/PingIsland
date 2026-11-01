import SwiftUI

/// 异常恢复页（执行文档 13.3：授权失效/监控重建/数据状态说明，Phase 2 接入完整恢复动作）
struct RecoveryView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("数据状态") {
                    Text("存档有效时显示最近结算与快照版本；恢复动作在 Phase 2 接入。")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("恢复")
        }
    }
}
