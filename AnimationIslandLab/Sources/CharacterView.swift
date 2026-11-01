import SwiftUI

/// 角色视图（执行文档 12.2：一个原创角色、两套少帧动作、一个静态回退姿态）。
/// 原型阶段用 SF Symbol 字符替身，不引入素材管线；每帧只改变换，不做连续画布假设。
struct CharacterView: View {
    @ObservedObject var controller: LabActionController

    var body: some View {
        // 帧替身：🚶 走路 / ✨ 施法 / 🧘 静态回退
        Text(glyph)
            .font(.system(size: 56))
            .offset(x: offsetX, y: 0)
            .scaleEffect(scale)
            .animation(.easeInOut(duration: controller.current.frameDuration), value: frameKey)
            .onAppear { controller.log.append("view.appear.\(controller.current.rawValue)") }
    }

    private var glyph: String {
        switch controller.current {
        case .idle: return "🧘"
        case .walk: return "🚶"
        case .cast: return "✨"
        }
    }

    /// 少帧位移：走路帧间横向摆动
    private var offsetX: CGFloat {
        guard controller.current == .walk else { return 0 }
        return controller.frame % 2 == 0 ? -8 : 8
    }

    /// 少帧缩放：施法帧间脉动
    private var scale: CGFloat {
        guard controller.current == .cast else { return 1 }
        return controller.frame % 2 == 0 ? 1.0 : 1.2
    }

    /// 帧标识：变换动画的 value 依赖
    private var frameKey: Int { controller.frame }
}
