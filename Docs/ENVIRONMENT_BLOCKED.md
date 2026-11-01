# ENVIRONMENT — 环境状态与路线说明

更新日期：2026-11-02（路线变更）

## 原门禁结论（执行文档 0.2 节）

本机为 Windows，无 macOS/Xcode，原生工程验收曾暂停。

## 现行路线（用户 2026-11-02 确认，无 Mac）

**Windows（Kimi Work 写码 + swift test 规则测试）→ push → GitHub Actions 免费 macOS runner 自动编译未签名 IPA → 下载 → Sideloadly 自签装入实体 iPhone，全部测试在手机上进行。**

- CI 云编译机只负责构建，不承担交互式开发；
- 工程以 XcodeGen 定义（`project.yml`），任何机器 `xcodegen generate` 可重建 .xcodeproj；
- 模拟器集成测试也在 Actions 上运行；
- 真机验收（阈值回调、长期不打开 App、灵动岛生命周期、耗电）在实体 iPhone 上进行并记录到 `Docs/PLATFORM_VALIDATION.md`。

## 仍缺失（外部条件）

| 缺失项 | 影响 | 恢复方式 |
|---|---|---|
| 实体 iPhone | 无法做真实监控/灵动岛/锁屏验证 | 用户自备 |
| Apple ID（建议专用） | Sideloadly 自签必需 | 用户在 Sideloadly 界面亲自输入 |
| 付费 Apple Developer + Family Controls 授权 | 监控扩展 entitlement 无法生效 | 免费自签下监控不可用；办会员并向 Apple 申请 |

## Windows 侧已完成

- VS2022 Build Tools（VCTools）、Swift 6.4.2 官方完整版、VS Code + Swift 扩展；
- PingIslandKit 规则引擎 27/27 XCTest 通过（详见 环境配置报告.md）；
- 多 Target Xcode 工程定义（App/Monitor/Widgets/Tests）已提交，CI 构建结果见 Actions。
