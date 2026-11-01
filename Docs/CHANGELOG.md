# CHANGELOG

## [未发布] - 环境配置阶段（2026-11-02）

###  added
- 仓库初始化：.gitignore（Swift/Windows/证书）、README、Docs（ENVIRONMENT_BLOCKED / PLATFORM_VALIDATION / KNOWN_LIMITATIONS）。
- PingIslandKit 平台无关规则引擎 Swift Package：每日骰子、线性成长、初始属性、探索稀有度配置、装备生成与自动择优，含 golden tests。
- CI 工作流 `.github/workflows/ios.yml`：规则引擎 swift test 任务。

### BLOCKED
- VS2022 Build Tools / Swift on Windows 安装进行中（本机无管理员令牌，UAC 需用户确认）。
- 原生 Xcode 工程：等待 macOS 环境。
