import Foundation

/// 动作状态机（执行文档 12.2）：两套少帧动作 + 静态回退姿态。
/// 只接受外部"已保存状态"驱动切换，不做无依据的自动循环承诺。
enum LabAction: String, CaseIterable {
    case idle = "idle"     // 静态回退姿态
    case walk = "walk"     // 少帧：走路
    case cast = "cast"     // 少帧：施法

    /// 帧节奏（秒/帧）。少帧原则：每套动作 ≤ 4 帧。
    var frameCount: Int {
        switch self {
        case .idle: return 1
        case .walk: return 4
        case .cast: return 3
        }
    }

    /// 预设节奏（秒/帧）。12.3-1 记录项：离开 App 后是否按此节奏继续
    var frameDuration: TimeInterval { 0.4 }
}

/// 动作切换控制：当前姿态 + 生命周期日志
final class LabActionController: ObservableObject {
    @Published private(set) var current: LabAction = .idle
    @Published private(set) var frame: Int = 0
    private(set) var log = LabLog()

    /// 依据已保存状态切换到指定动作（12.4-2：可靠切换而非只会循环）
    func switchTo(_ action: LabAction, reason: String) {
        guard action != current else { return }
        current = action
        frame = 0
        log.append("action.switch.\(action.rawValue).\(reason)")
    }

    /// 前进一帧（少帧循环）
    func advanceFrame() {
        frame = (frame + 1) % current.frameCount
    }
}
