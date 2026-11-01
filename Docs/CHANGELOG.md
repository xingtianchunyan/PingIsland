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

### CI 首跑修正（2026-11-02 深夜）
- 修复 XcodeGen 空源目录（Recovery 占位）、模拟器目的地（动态创建 iPhone 模拟器）。
- **Actions 三任务全绿**：规则测试、模拟器集成测试、未签名 IPA 构建（工件已下载验证：含 Monitor/Widgets 扩展）。

### 规则引擎扩展（第 10/14 章，2026-11-02）
- 职业觉醒判定（7 日/60 分钟/1pp 并列/其他组判流浪者）、疲劳五阶段（纯展示）、
  遭遇与日记（30% 怪物、胜负各 50%、确定性 golden）、时区与显著跳变分段（5 分钟阈值、单调 ID）。
- Windows XCTest **45/45 通过**。

### 结算引擎核心（Phase 1，2026-11-02）
- SettlementEngine：稳定事件 ID 幂等账本；归属补差（低阈值晚到不倒退）；骰子/神谕/成长/
  探索（每组每日 5 次上限）/装备择优/职业觉醒串联为确定性事件序列处理。
- 门禁验证：批量=逐条、整序列重放全判重、乱序无回归、golden 跨引擎一致。
- Windows XCTest **55/55 通过**。

### 持久化与恢复层（2026-11-02）
- SettlementStore 协议 + JSONFileSettlementStore（Data.atomic 原子写）；SettlementService：
  事件先落日志→结算→存状态；恢复时重放日志补齐，恰好一次生效。SQLite/GRDB 留接口。
- 6 个持久化 XCTest（往返/崩溃恢复/部分进度/重复恢复稳定/无半套文件/跨日分段）。
- Windows XCTest **61/61 通过**。

### 真实事件纵切片（2026-11-02）
- PendingEventQueue（App Group 待结算队列，消费语义 drain）；监控扩展阈值回调解析分钟数
  以稳定事件身份入队（不再伪造 level+1 演示）；SettlementCoordinator：主 App 前台消费队列
  → SettlementService 结算 → 刷新展示快照与 Live Activity；展示失败不回滚结算。
- App 侧测试：队列消费一次、协调器结算+快照刷新、重复入队不重复发奖（CI 模拟器验证）。

### 八修行组选择 UI 与按组监控注册（执行文档 5.2，2026-11-02）
- GroupSelection：固定 8 组顺序、State 持久化（version 递增）、sanitized 跨组 token 查重
  （一个 App 只属一个组，14.3）、泛型 deduplicate 可测。
- MonitorEventParser：事件名 `pingisland.g<组序>.t<分钟>` 生成/解析往返一致；兼容旧格式
  `pingisland.threshold.<分钟>`（归“其他”组）。
- OnboardingView 重写：欢迎（能力边界）→ 逐组 FamilyActivityPicker（展示倾向属性与对应职业、
  setter 内查重）→ 汇总 → 授权成功后持久化分组、建角色种子、按组注册监控、写初始快照。
- MonitoringRegistrar 重写：每组独立 activity（`pingisland.g<组序>`）+ 30/60/90 分钟事件，
  单组失败不阻塞其余组，日志键 monitor.register.v1；SettlementCoordinator 结算组取持久化分组。
- App 侧测试：分组顺序/去重/State 往返、事件名解析（8 组×3 阈值往返、旧格式、非法串）
  —— CI 模拟器验证；Windows 规则引擎回归 61/61 保持通过。
- CI 三轮修正：GroupSelection 补 import PingIslandKit；token 类型不显式命名（成员访问+泛型去重，
  FamilyControls token 符号在编译接口中不保证可见）；测试补 import PingIslandKit。
- **Actions 三任务全绿**（run 41340327661，commit 213c67d），新 IPA 已下载 dist/PingIsland-unsigned.ipa。

### 调试面板与模拟事件源（执行文档 13.1/13.3，2026-11-02）
- SimulatedUsageSource：明确标注的模拟事件源，独立账本目录 settlement-simulated、
  sim. 前缀事件 ID、固定种子 42（结果确定可复现），与生产 DeviceActivity 账本完全隔离。
- DebugPanelView（仅 DEBUG 编译）：授权/分组版本/账本路径状态、最近 20 个已处理事件与高水位、
  模拟事件注入结算（红标“模拟数据”）、Widget 刷新与 Live Activity 测试更新、
  脱敏诊断报告导出（不含 token/真实 App 名）、模拟账本重置。
- Settings：重新授权并重建监控（恢复入口，按已保存分组重注册）、隐私说明按 13.2 补全。
- App 侧测试 5 个：sim 前缀与唯一性、独立目录、模拟结算只写模拟账本、重置清空、固定种子确定性。
- CI 三轮修正：Debug 目录入 target 源列表、补 ActivityKit 导入、测试 base 目录改懒加载存储属性。
- **Actions 三任务全绿**（run 41344183511，commit 0e6d870），新 IPA 已下载 dist/PingIsland-unsigned.ipa。

### 桌面卡片休眠口径与刷新策略（执行文档 11.2，2026-11-02）
- DisplaySnapshot 增加 isStale（>6 小时未确认）与 widgetStatusText：卡片展示“休眠 · 等待同步”，
  仅展示口径不判定系统故障；从未结算也按等待同步处理。
- 小/中卡片接入口径；时间线策略：新鲜 30 分钟跟进、休眠 6 小时后再检查，不堆积条目模拟视频。
- App 侧测试 4 个：1 小时新鲜、7 小时休眠、从未结算、5 小时 59 分边界。
- **Actions 三任务全绿**（run 41344818829，commit 7304d27），新 IPA 已下载 dist/PingIsland-unsigned.ipa。

### 展示优先级（执行文档 11.4，2026-11-02）
- Kit 新增 PresentationPolicy：异常休眠 > 夜间(23:00-07:00) > 神谕/职业觉醒/新收藏 >
  遭遇 > 日常姿态，纯函数 Windows XCTest 10 个全过（判定+夜间小时+横幅文案）。
- DisplaySnapshot 增 displayPriority/bannerText（可选字段，旧快照 JSON 兼容解码）；
  卡片状态行 = 横幅 > 休眠 > 最近事件。
- SettlementCoordinator 结算后按最近增量解析优先级写快照；调试面板可标记/清除异常休眠
  便于端到端验证。
