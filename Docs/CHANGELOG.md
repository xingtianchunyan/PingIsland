# CHANGELOG

## [未发布] - 2026-11-02

### 环境配置（任务书阶段 0~5，已完成）
- Git 2.47 / VS Code 1.97 + Swift 扩展 2.18 / VS2022 Build Tools 17.14（VCTools）/ Swift 6.4.2 官方完整版（winget 版缺 stdlib，已换官方包；SDKROOT 已写入用户环境变量）。
- PingIslandKit 规则引擎：骰子/成长(定点数)/初始属性/探索/装备/魅力追加/神谕，Windows XCTest **27/27 通过**。
- 私有仓库 github.com/xingtianchunyan/PingIsland，凭据推送成功。

### 路线变更（用户确认无 Mac）
- 采用 CI 云编译路线：Windows 写码 → Actions macOS runner 构建未签名 IPA → Sideloadly 自签真机测试。
- Xcode 工程改为 XcodeGen 定义（project.yml），多 Target：PingIsland / PingIslandMonitor / PingIslandWidgets / PingIslandTests / PingIslandUITests。
- CI 工作流启用三任务：规则测试、模拟器测试（iPhone 16）、未签名 IPA 构建（工件 14 天）。

### 代码
- 主 App：onboarding（FamilyControls 授权 + App 选择）、角色主页（只读快照）、日记/收藏占位、设置页、Live Activity 开关、监控注册（30/60/90 分钟阈值）。
- 监控扩展：DeviceActivityMonitor 阈值回调写入共享容器与快照（结算引擎 Phase 2 接入）。
- Widget 扩展：小/中卡片 + Live Activity 紧凑/最小/展开/锁屏视图，全部只读共享快照。

### BLOCKED
- Family Controls entitlement 需付费开发者账号 + Apple 授权（免费自签不可用，见 KNOWN_LIMITATIONS）。
- 真机验证矩阵（执行文档 14.4）：待实体 iPhone 到位。
