# PLATFORM_VALIDATION — 平台能力验证记录

状态：**未开始（BLOCKED：无 macOS/Xcode 环境）**

按执行文档 4.3 节，Phase 0 必须在真实 macOS/iOS 环境验证并记录以下项目。每一项在实测前保持 `NOT VERIFIED`，不得预填结论。

| 验证项 | 状态 | 记录 |
|---|---|---|
| Family Controls 授权路径与系统选择器 | NOT VERIFIED | — |
| 主 App 与监控扩展 entitlement | NOT VERIFIED | — |
| App Group 在扩展中的文件访问 | NOT VERIFIED | — |
| DeviceActivity 注册/回调/撤销/重建 | NOT VERIFIED | — |
| Widget 扩展读取共享快照 | NOT VERIFIED | — |
| Live Activity 启动/更新/结束/读取已有活动 | NOT VERIFIED | — |
| 分发签名与开发签名差异 | NOT VERIFIED | — |
| 多日不打开 App 的回调有效性 | NOT VERIFIED | — |
| 跨阈值/乱序/延迟事件表现 | NOT VERIFIED | — |

恢复环境后的首次验证应追加日期、macOS/Xcode 版本、设备型号与 iOS 版本。
