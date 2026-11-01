import Foundation

/// 时区变化与显著时间跳变的分段处理（执行文档 10.4）。
/// 显著跳变默认：同次开机内，墙上时间变化与单调时钟经过量差超过 5 分钟；
/// 重启后不跨重启比较单调时钟。
public struct SegmentKeeper: Equatable, Codable, Sendable {
    public private(set) var currentSegmentID: Int64
    public private(set) var localDate: String
    public private(set) var timeZoneID: String
    /// 本分段打开时的墙上时间与单调时钟（毫秒）
    public private(set) var openedWallMillis: Int64
    public private(set) var openedMonotonicMillis: Int64
    /// 已关闭分段的只读历史（恢复与审计用）
    public private(set) var closedSegments: [ClosedSegment]

    public struct ClosedSegment: Equatable, Codable, Sendable {
        public var segmentID: Int64
        public var localDate: String
        public var timeZoneID: String
    }

    public init(firstSegmentID: Int64 = 1, localDate: String,
                timeZoneID: String, wallMillis: Int64, monotonicMillis: Int64) {
        self.currentSegmentID = firstSegmentID
        self.localDate = localDate
        self.timeZoneID = timeZoneID
        self.openedWallMillis = wallMillis
        self.openedMonotonicMillis = monotonicMillis
        self.closedSegments = []
    }

    /// 是否显著跳变（同次开机内比较）。
    /// 单调时钟相对本分段打开时刻回退 → 期间重启过，不做跨重启比较。
    public func isSignificantJump(wallNowMillis: Int64,
                                  monotonicNowMillis: Int64,
                                  bootedMonotonicMillis: Int64) -> Bool {
        guard monotonicNowMillis >= openedMonotonicMillis else { return false }
        let wallDelta = wallNowMillis - openedWallMillis
        let monoDelta = monotonicNowMillis - openedMonotonicMillis
        return abs(wallDelta - monoDelta) > SegmentKeeper.jumpThresholdMillis
    }

    public static let jumpThresholdMillis: Int64 = 5 * 60 * 1000

    /// 原子关闭旧分段、打开单调递增新分段；保留历史，不清空成长（成长账本由结算层保留）
    @discardableResult
    public mutating func closeAndOpen(newLocalDate: String,
                                      newTimeZoneID: String,
                                      wallMillis: Int64,
                                      monotonicMillis: Int64) -> Int64 {
        closedSegments.append(ClosedSegment(segmentID: currentSegmentID,
                                            localDate: localDate,
                                            timeZoneID: timeZoneID))
        currentSegmentID += 1
        localDate = newLocalDate
        timeZoneID = newTimeZoneID
        openedWallMillis = wallMillis
        openedMonotonicMillis = monotonicMillis
        return currentSegmentID
    }
}
