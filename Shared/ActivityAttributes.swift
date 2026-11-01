import ActivityKit
import Foundation

/// Live Activity 数据定义（执行文档 11.3）。
/// 紧凑态/最小态/展开态/锁屏视图全部只读此内容，不另跑游戏公式。
public struct PingIslandActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var level: Int
        public var className: String
        public var recentEvent: String

        public init(level: Int, className: String, recentEvent: String) {
            self.level = level
            self.className = className
            self.recentEvent = recentEvent
        }
    }

    /// 启动时固定、不随更新变化的部分
    public var characterTitle: String

    public init(characterTitle: String) {
        self.characterTitle = characterTitle
    }
}
