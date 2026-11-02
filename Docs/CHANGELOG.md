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
- **Actions 三任务全绿**（run 41346401604，commit 61dce1b），Kit 70/70（+10 优先级测试），新 IPA 已下载。

### 角色主页数据完整化（Phase 4，2026-11-02）
- DisplaySnapshot 增 attributes（六维初始属性）与 equipment（择优装备预格式化摘要），
  可选字段旧 JSON 兼容；SnapshotPresentation 品阶文案（白~红）。
- SettlementCoordinator 结算时把引擎属性/已装备写入快照；角色主页重写为分区列表：
  角色卡（横幅/最近事件/实时活动控制）、六维属性条、装备栏。
- App 侧测试 +1：带新字段快照往返一致。

### 日记页与收藏页接入快照（Phase 4，2026-11-02）
- DisplaySnapshot 增 recentDiaries（最近 10 条，新→旧预格式化）与 collection（装备藏品，
  品阶降序）；协调器从引擎填充；日记页/收藏页占位实现改为只读快照列表。
- 快照往返测试扩展覆盖新字段。

### 装备外观与六行效果模板（执行文档 9.5/9.6，2026-11-02）
- EquipmentAppearance：外观等级 = 1 + floor(最终智慧/50)；布甲/皮甲/铁甲/机甲分段，
  只影响展示不改词条。
- SkillRules：周一~周日六行模板（周六日同为雷）、12 个模板名、被动数值=稀有度序号×
  等级倍率（Lv1~5：100/130/150/165/180%，四舍五入）、Lv5 后重复转化规则。
- Windows XCTest 76/76 通过（+6 内容池测试）。

### 技能抽选确定性链路（执行文档 9.6，2026-11-02）
- SkillDrawRules：每有效分钟一次逻辑抽选，由（角色种子、当日骰点、分钟序号、星期）
  fnv1a 种子确定性重建；主动只影响演出、被动 Lv1 数值与 SkillRules 一致；
  sequence() 批量重建=逐分钟调用。无后台任务、无动画帧存储。
- Windows XCTest 82/82 通过（+6 抽选测试：可复现、分钟独立、星期模板、批量等价、数值一致）。

### 真机验证矩阵模板（2026-11-02）
- 新增 Docs/PLATFORM_VALIDATION.md：按执行文档 7.3/12.3/14.4 建表（监控配置验证、
  真机验证矩阵、实验动画必测），未测项显式标注，含免费签名限制前置说明。

### 异常恢复页完整实现（执行文档 13.3，2026-11-02）
- RecoveryService：重新授权+按已保存分组重建监控，设置页与恢复页共用同一入口；
  授权状态文案（失效=已停止成长、历史保留）。
- RecoveryView：数据状态（授权/快照版本/最近结算/已入账事件/休眠口径）、恢复动作、
  13.3 六类异常行为说明；进入时顺带消费待结算队列。

### 遭遇日记文案层（执行文档 9.7，2026-11-02）
- DailyLifePool 六条日常生活片段；Monster 胜负文案；DiaryText.display(textKey) 单一来源解析，
  未知键原样返回便于排查。协调器三处 textKey 输出改走展示文案（快照/日记/Live Activity）。
- Windows XCTest 86/86 通过（+4：全怪物胜负解析、200 连抽全可解析、未知键透传、池非空）。

### 中尺寸卡片属性摘要（执行文档 11.2，2026-11-02）
- DisplaySnapshot 增 attributeSummary（六维一行摘要，固定 CON→CHA 顺序）；中卡片展示。
- App 侧测试 +1（含空/缺省 nil）。

### 实验动画原型骨架（执行文档第 12 章，2026-11-02）
- AnimationIslandLab 独立工程（不进 CI、不合入正式产品）：动作状态机（idle/walk/cast，
  只接受外部状态驱动）、少帧变换角色视图、生命周期+内存日志与导出、12.3 必测项与
  12.4 合入门禁写入 README；真实 DeviceActivity 事件接入列为后续项。

### 覆盖率核对表（2026-11-02）
- 新增 Docs/COVERAGE.md：执行文档逐章对照（0~14 章），标记 已完成/已写待验/待真机/未做，
  列出明确后续项。

### 技能收藏账本（执行文档 9.6，2026-11-02）
- SkillDraw 增 weekday 字段；SkillCollection：同一模板（星期+主被动）＋同一稀有度=
  同一收藏项，重复升 Lv2~Lv5，Lv5 后再重复按稀有度转化为属性点（点数与池来自 SkillRules）。
- Windows XCTest 91/91 通过（+5：新建、升满五级、满级转化、异稀有度分项、Codable 往返）。

## 2026-11-02 技能抽选接入结算主流程（9.6）
- SettlementEngine.process 第 5.5 步：每个有效分钟一次 SkillDrawRules 确定性抽选（种子+骰点+分钟序号+星期），写入 skillCollection 并进入 delta.skillDraws
- SettlementEngine 新增 skillCollection 存储属性；手写 init(from:) 兼容旧格式 state JSON（skillCollection 键缺失按空收藏解码），编码保持合成
- SettlementDelta 新增 skillDraws 字段
- 新增 SkillEngineIntegrationTests（4 例）：跨引擎序列确定性、与独立重建一致、旧 JSON 解码兼容、跨天星期归档
- 本地 Kit 回归 95/95 通过

## 2026-11-02 真机反馈修复：首启授权降级 + Debug 面板可见
- 首启新增"暂不授权，先进入应用"降级路径（欢迎页 + 授权失败错误处）：保存分组与角色种子，跳过监控注册；无监控、无虚构成长，设置页可重新授权（真机确认自签环境 FamilyControls 报"无法与帮助程序通信"）
- 未授权时组选择页不再显示空白 FamilyActivityPicker，改为提示文案与跳过
- 汇总页全空时给出无监控模式说明
- 移除 Debug 面板全部 #if DEBUG 条件编译：Release IPA（CI 产物）也可见，自测期间用模拟数据体验全功能；模拟账本与真实账本隔离
- 反馈登记：Docs/PLATFORM_VALIDATION.md F-1~F-7；已知限制更新：Docs/KNOWN_LIMITATIONS.md

## 2026-11-02 CI 故障根因定位：账号 Actions 额度耗尽（非镜像退役）
- 证据链：全新私有探针仓库 hello-world 同样 runner_id=0 秒挂（账号级，非仓库/工作流级）；macos-14 退役不适用（本仓库早已用 macos-15，试切 macos-26 亦失败）；官方社区同症状案例确认是 Free 私有库 2000 分钟额度耗尽 + 默认 $0 支出上限 → 调度层直接拒绝分配 runner
- 私有库 macOS 按 10× 计费：前期两个全绿 run 加多次长时重试已耗尽额度
- 工作流优化：规则引擎 swift test 迁到 ubuntu-latest（1× 计费），macOS 只留给模拟器测试与 IPA 构建
- 待账号侧决策：仓库转公开 / 等账单周期重置 / 升级付费（见 KNOWN_LIMITATIONS 同款说明）

## 2026-11-02 仓库转公开后 CI 全面恢复
- 账号额度根因确认后仓库转公开（行天拍板）：公开库 Actions 免费不限量，runner 立即恢复分配
- 修复真机首启暴露的编译错误：RecoveryService.swift 缺 import PingIslandKit（TrainingGroup 未解析）
- setup-swift@v2 无 6.4.2：规则引擎测试迁回 macos-26（公开库免费）
- run 41399530958 全绿（Kit 95/95 + 模拟器测试 + Release 归档）；新 IPA 落 dist/PingIsland-unsigned.ipa
