# KNOWN_LIMITATIONS — 已知限制

- **Family Controls 依赖付费账号**：`com.apple.developer.family-controls` entitlement 需要 Apple Developer Program 会员并向 Apple 申请。Sideloadly 免费自签下该 entitlement 不生效，DeviceActivity 监控不可用；届时 App 仍可运行，监控相关入口会显示授权失败说明（执行文档 5.1/13.3）。办会员并获批后同一 IPA 重新签名即可启用。
- 规则引擎在 Windows Swift 上 XCTest 验证；iOS 集成未验证（待 Actions 构建 + 真机）。
- 首个未签名 IPA 已由 Actions 构建成功（含主 App + 监控扩展 + Widget 扩展，模拟器测试通过）；IPA 为未签名，需 Sideloadly 用 Apple ID 自签；自签应用 7 天有效期（免费账号）。
- 桌面卡片、Live Activity、灵动岛展示：待真机验证，当前无任何"已通过"声明。
