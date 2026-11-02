import FamilyControls
import Foundation
import PingIslandKit

/// 恢复动作（执行文档 13.3）：重新授权 + 按已保存分组重建监控。
/// 设置页与恢复页共用同一入口，保证行为一致。
enum RecoveryService {
    /// 重建结果文案（主线程回调）
    static func rebuildMonitoring(completion: @escaping (String) -> Void) {
        AuthorizationCenter.shared.requestAuthorization { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    let state = GroupSelection.load()
                    var selections: [TrainingGroup: FamilyActivitySelection] = [:]
                    for group in GroupSelection.orderedGroups {
                        let s = state.selection(for: group)
                        let count = s.applicationTokens.count + s.categoryTokens.count
                            + s.webDomainTokens.count
                        if count > 0 { selections[group] = s }
                    }
                    MonitoringRegistrar.register(selections: selections)
                    completion(selections.isEmpty
                        ? "已授权，但没有已保存的分组；请先完成首次设置。"
                        : "已重建 \(selections.count) 组监控。")
                case .failure(let error):
                    completion("授权未完成：\(error.localizedDescription)")
                }
            }
        }
    }

    /// 当前授权状态文案（13.3：授权失效时显示恢复说明，停止虚构成长）
    static var authStatusText: String {
        switch AuthorizationCenter.shared.authorizationStatus {
        case .notDetermined: return "未请求"
        case .denied: return "已拒绝（已停止成长，历史保留）"
        case .approved: return "已授权"
        @unknown default: return "未知"
        }
    }
}
