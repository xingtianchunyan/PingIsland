# CHANGELOG

## 2026-11-10 真机反馈批次十（第二十批）：结算规则 v3（职业成长+属性掉落）+ 角色页终版简化 + 调试手动注入 + 日记周切换
- 结算规则 v3（行天第二十批完整公式，恢复职业成长体系）：
  ① 每分钟成长 = 新增分钟 × 骰点/10 × 职业系数（流浪者全组 +3% `.ranger`，其它觉醒职业 +10% `.matched`，
  未觉醒 1.0 `.neutral`）；升级所需经验保持 100 XP/级不变；
  ② 每满 30 分钟一次活动结算，活动经验加成 = 30 × 骰点 / 10（= 3 × 骰点 XP）；
  ③ 属性包入掉落：基础属性 CON/INT/DEX、高级属性 LUK/WIS/CHA；点数 roll 60/30/10 分布；
  ④ 骰点四档：<10 装备率=骰点/10（白/绿，白色率=(10−骰点)/10），否则基础属性 1~3 点；
  =10 50% 装备（白/绿/蓝 60/30/10）或 50% 基础属性 1~3 点；
  10~19 40% 基础属性 3~5 点 / 30% 全六阶装备（40/30/20/8/1.99/0.01%）/ 20% 高级属性 1~3 点 / 10% 白绿蓝特质技能；
  =20 40% 高级属性 3~5 点 / 30% 装备 / 30% 特质技能（均紫/橙/红 80/19/1%），
  且无论主结果都 100% 额外得一件紫/橙/红装备（独立日记记录）
  ⑤ `MilestoneGrant` 新增 `attributePoints` 并入日记 rewardSummary；统计测试重写为 v3 四档分布
- 成长规则 v3.1（行天 2026-11-10 修正："每分钟成长不太对，应该是每升 1 级的成长"）：
  ① 每分钟经验固定 1 XP，不再乘骰点/职业系数（骰点只作用于活动结算与掉落）；
  ② 每升 1 级成长 = 1 点基础智慧 × 职业系数，千分位定点累计——
  其它觉醒职业每级 +1.10、流浪者每级 +1.03、未觉醒每级 +1.00（余量跨段保留，
  引擎新增 wisLevelMilli/wisLevelApplied 状态，旧存档兼容）；
  ③ 职业系数语义说明：1.10/1.03/1.00 是最初体系（98466d0）的成长速度系数——
  非流浪者觉醒职业成长 +10%，流浪者（均衡兜底职业，觉醒最易）全组 +3%，未觉醒 1.0。
  v3.1 把系数的作用点从"每分钟经验"搬到"每级属性成长"，数值含义不变

- 角色页终版简化（第二十批反馈）：
  ① 删除卡牌下方装备栏/特质栏双列（后续按数据做动画/视觉效果）；
  ② 卡牌屏幕垂直居中（GeometryReader + minHeight）；等级去圆形底框改纯文本（三位数等级不再破版）；
  ③ 六维雷达去半透明圆角矩形底板
- 调试面板：
  ① 新增「手动注入」区：装备（部位/外观/品质下拉 + 注入按钮）、特质/技能（周日模板/主被动/品质 + 注入按钮），
  直接入账模拟账本并同步展示（`SettlementService.debugInjectEquipment/Skill`，装备支持外观覆盖 `appearanceOverride`）；
  ② "模拟过一天"在指定骰点开启时先把新日期骰点锁定再换日——修复骰 20 过天不触发神谕、
  首页不显示指定骰点的问题（根因：过天只走正常掷骰未应用 diceOverride）
- 日记页：周汇总卡下方新增「本周/上周」segmented 切换，单日分区与"更早"分组跟随所选周刷新；
  `DisplaySnapshot` 新增 `previousWeekStats`（所选周缺数据回退本周）
- 资产包处置（各自独立分支，不并入本批）：
  monsters-v2 经键与 PNG 哈希比对确认与 feat/content-skills 已整合内容完全一致（重复包，无需再合）；
  eq-fix（重生装备图 8 张）→ 新分支 `assets/eq-fix`；
  holo-card-v2（卡面特效全面更新：6 纹路×4 光泽可组合 + 调试实验台 + 金雨重做）→ 新分支 `feat/holo-card-v2`
  （基于 feat/holo-card@c1dd803；与 batch-20 角色页同文件，大整合时以 batch-20 结构为基移植特效层）

## 2026-11-06 真机反馈批次九（第十九批）：结算规则 v2 + 球星卡全铺重构 + 调试条件开关
- 结算规则 v2（行天第十九批完整公式，替代原每分钟成长/抽选模型）：
  ① 每分钟只积累 1 XP，不再结算其它内容（原骰点倍率、职业系数成长公式作废）；
  ② 每满 30 分钟结算一次活动，经验加成 = 30 × 骰点 / 10（= 3 × 骰点 XP）；
  ③ 装备/特质·技能按骰点四档：<10 仅白/绿装备（获得率 = 骰点/10，白色率 = (10−骰点)/10）；
  =10 必得白/绿/蓝装备 60/30/10；10~19 70% 六阶装备（40/30/20/8/1.99/0.01%）或 30% 白/绿/蓝特质技能；
  =20 装备与特质技能各 50%（紫/橙/红池 80/19/1%），且 100% 额外获得一件紫/橙/红装备（独立日记记录）；
  ④ 神谕（骰 20 每日一次）改为**换日即触发**、不占活动结算：骰 20 当日记录数恒为奇数（1 神谕 + 每次活动 2 条）；
  新 `MilestoneRules` 为单一实现来源，2 万样本/档的统计测试锁定概率分布
- 角色页球星卡再重构（第十九次反馈）：
  ① 立绘 `.fill` 铺满整卡，卡牌宽度铺满屏幕（水平仅留 12pt），大小机等比缩放；
  ② 六维雷达**覆盖在立绘上层**（仍是卡面内容，垫半透明面板保证可读），卡底深色 scrim 承载名字/日记；
  ③ 装备栏/特质栏浮层**撤销**（效果不理想），恢复为卡牌下方普通双列；后续按数据做动画/视觉效果
- 立绘兜底链修复：觉醒前空白根因是 `app_icon` imageset 缺失（JSON 里是悬空键），
  改为 职业立绘 → `pose_night_sleep` 夜间睡姿图 → emoji；雷达高对比白字白网格（参数化 tint/grid）
- 调试面板重做（行天"设想 2"：删乱糟测试功能，改触发条件直接开关）：
  ① 阈值快捷 chips（点击全跳 480 的 bug 根修）→ 原生 segmented Picker；
  ② 新增「触发条件开关」区：金雨预览（无视 LUK≥900）、闪卡档位预览（普通/银/金/全彩覆盖角色卡与装备卡），
  开了直接满足、关了恢复规则判定；
  ③ 连注冲刺默认 3 → 7 天（对齐觉醒最小观察天数），"运行状态"新增觉醒进度（观察 N/7 天 + 各组分钟）；
  ④ "模拟过一天"改为真实换日语义：先对新日期发神谕（骰 20 时）再刷新展示；
  ⑤ "快照体检"行（版本/等级/职业/属性/技能/装备/骰点计数）加速定位"白白一片"类展示异常
- 已知问题（移交 QwenWork 重生资产）：`eq_head_cloth`（兜帽哥布林持刀）、`eq_head_leather`（怪脸）、
  `eq_legs_iron`（全身骑士像，非裤子）、mech 四张偏完整角色像（body/feet/legs 应为单部位件）

## 2026-11-06 真机反馈批次八（第十八批）：球星卡重构 + 立绘接入 + 结算门槛 + 注入增强
- 角色页球星卡重构（第十八次真机反馈）：
  ① 角色卡从万智牌式卡框改为球星卡式卡面——立绘占卡面上半，六维雷达**移入卡面**（立绘下方，属卡牌展示内容），
  装备栏·特质栏以半透明浮层**叠在卡牌上方**左右两缘，不再置于卡牌之外的下方；
  ② 角色立绘接入美术资产（class_* imageset；觉醒前用岛屿 App 图标占位）——修复"觉醒前只显示一个岛、觉醒后只有衣服"的占位渲染
- 装备立绘接入：收藏页四宫格与放大装备卡的画框均改显 eq_部位_外观 资产图（缺失时降级 SF Symbol），
  替换原"屏幕纯色图形 + 符号"占位
- 银/金边闪卡修复：旧版 mask+stroke 方案描边一半悬在卡外被裁，只剩未覆盖白边且无流光；
  改为 EdgeShimmerBorder（strokeBorder 动画渐变，描边全落在形内），边框全覆盖 + 流光循环扫动
- 技能抽选骰点门槛（规则修订，真机反馈 3.2）：原实现**每个有效分钟必抽**（骰 5 + 120 分钟也能出一堆技能），
  现改为骰点 < 10 的分钟不抽选；≥ 10 后每分钟按 (骰点−9)/11 的**确定性**概率命中（骰 20 = 每分钟必中），
  同一注入不再一次出现 6 个特质/技能；`SkillDrawRules.occurs` 与引擎结算共用同一判定，测试同步改为门槛过滤后的动态条数
- 调试注入增强（真机反馈 3.1/3.3）：
  ① 快捷阈值档位（30/60/120/240/480）一键设置；
  ② 「指定骰点」开关（UsageEvent.diceOverride，仅模拟事件；1...20，钳制落账）——高骰点效果（金雨/神谕/满掉率）可直接测试；
  ③ 「连注冲刺」：连续 N 个模拟日各注入 480 分钟，等级/闪卡档位快速触达；
  ④ 修复"今日获得"跨天失效：注入事件原误传真实 now 作 confirmedAt，过天（dayOffset>0）后新装备获得时间不在模拟今天内，
  改为按模拟日期落账，新获得装备重新出现在"今日获得"；
  ⑤ 注入结果补充探索次数/新装备件数；装备卡（角色页与收藏页放大卡）展示获得时间与来源（EquippedDetail 增 acquiredAt/origin）

## 2026-11-06 怪物扩展（feat/content-skills 批次二，monsters-v2）
- 怪物图鉴键 3 → 12（六元素 × 2）：新增 树苗精/蘑菇怪/火蜥蜴/火花蝠/岩壳蟹/锈铁傀儡/小水灵/静电球/雷雀，
  保留 小骷髅(土)/哥布林(金)/史莱姆(水)；`ContentLibrary.json` 的 `monsterArtKeys` 与
  `ContentLibraryTests` 断言同步扩到 12 键（元素归属仅文档层标注，规则层 Monster 枚举扩 case 属 Phase A）
- 新增 18 个 imageset（9 主图 768×768 RGBA + 9 `_widget` 240×240），沿用 v2 八段式契约同族风格
- 遭遇抽取逻辑不变：旧 3 怪的 textKey/图鉴 rawValue 继续可解析，等概率与胜负 50/50 不受影响
- 本地验证：JSON/测试期望/图片集三方交叉校验一致（本机 Device Guard 新策略拦截 XCTest 运行器，
  完整 XCTest 以 CI macOS 运行器为准）

## 2026-11-06 真机反馈批次七（第十七批）：控制按钮可用性
- 说明：「开启灵动岛/锁屏实时活动」本身是**一个按钮**——灵动岛与锁屏卡片是同一个 Live Activity 的两个展示位置，开启后同时出现
- 按钮改名「开启实时活动」，去掉易误解的斜杠文案
- 开启/结束从纵向紧贴（间距 8）改为**并排两个等宽按钮**（prominent 主按钮 + 次按钮），真机不再误触相邻按钮；仅界面调整，不动任何逻辑

## 2026-11-06 真机反馈批次六（第十六批）：结束体验 + 角色页版面稳定
- 结束体验：定位「点结束不生效」主因——Sideloadly 重装后新安装无法枚举/结束旧签名安装遗留的实时活动（孤儿活动只能锁屏手动移除或等 8 小时过期）；锁屏选「不允许」会系统级关闭本 App 实时活动，重开需进设置
- 改进一：预检被拒时显示「去设置中开启实时活动」快捷按钮（直达系统设置页），不再让用户手动翻设置
- 改进二：结束仍有残留时提示「多为旧安装遗留，重启手机可清除」
- 角色页版面（行天第十六次反馈）：特质栏高度固定为「骰点 + 6 技能」满编布局，技能数从 0 到 6 页面总高度恒定、雷达位置不再跳动；六维雷达高度随可用宽度等比缩放（小屏 390pt 基准 190，上限 230），大小机型观感一致
- 分支：`fix/live-activity-restart` 追加提交；同版修复已同步到 `feat/holo-card`

## 2026-11-06 真机反馈批次五（第十五批）：灵动岛无法开启（闪烁/秒死/无授权卡）
- 现象：设置页点"开启灵动岛/锁屏实时活动"后页面快速闪烁，活动净存活为零；灵动岛无反应；锁屏不出现实时活动与"始终允许"授权卡
- 根因一：`LiveActivityControls.start()` 无防重入——连续点击产生并发 Task，后一个 Task 的"结束全部"把前一个刚创建的活动杀掉（第六批修复的同 Task 顺序只保证单次，不防并发）
- 修复一：新增 `busy` 状态，结束/创建序列执行期间禁用开启/结束按钮，重复点击直接忽略
- 根因二：`com.apple.developer.live-activities` entitlement 全工程缺失（此前只在 Info.plist 声明 NSSupportsLiveActivities），重新签名/重装后行为随机退化
- 修复二：project.yml 与 App/Widgets 两个 entitlements 文件补齐声明（Live Activity 视图渲染在 Widget 扩展里，两个 target 都需要）
- 修复三：新增 `Shared/LiveActivityDiagnostics.swift`，每次开启/结束的结果与确切错误写入共享容器，调试面板"运行状态"显示最近 3 条——真机失败不再靠口头转述
- CI：push 触发分支补 `fix/**`；actions/checkout 升 v5（消除 Node 20 弃用警告）
- 分支：`fix/live-activity-restart`（自 feat/ui-redesign）；待 Actions 出 IPA 后第十六次真机验证
## 2026-11-06 UI 特效分支（feat/holo-card，角色页/收藏页 3D 卡牌）
- 新增 `Shared/HoloCardKit.swift`（纯 SwiftUI，零第三方依赖）：2.5D 倾斜交互（±9°，松手弹簧回正）、
  万智牌式卡框（标题栏/画框/类型行/文本框）、闪卡覆层（银边/金边/全彩彩虹，TimelineView 30fps）、
  金雨粒子（运气 ≥900 触发，Canvas 无状态）
- 角色页：角色卡升级为可翻转万智牌式卡牌（闪卡档位按等级：<100 普通 / 100~199 银边 / 200~399 金边 / ≥400 全彩）
- 收藏页：装备四宫格点按放大为可翻转闪卡（白/绿/蓝普通；紫银边；橙金边；红全彩），空槽不可放大
- 设计来源：参考 holo-card-studio（EverettFish，MIT 协议，github.com/EverettFish/holo-card-studio）的交互，
  全部重写为 SwiftUI 实现，无代码拷贝；待 CI 编译验证与真机体验确认
- 分支：`feat/holo-card`（自 feat/ui-redesign `06ac420`）
## 2026-11-06 内容库分支（feat/content-skills，自 feat/assets-v2）
- 新增 PingIslandKit 内容库（`ContentLibrary.swift` + `Resources/ContentLibrary.json`，Bundle 资源随包分发）：
  72 项内容 = 12 技能模板（6 元素 × 主动/被动，与 SkillRules.template(forWeekday:) 单一来源强一致）× 6 稀有度变体，
  含名称/描述/图标键/主动姿态键；装备 16 图标键、职业 8 立绘键、疲劳 5 阶段键、怪物/夜眠/AppIcon 键
- 遵守"数值单一实现来源"：被动数值仍由 SkillRules 推导，本库只做内容与展示定义；
  `isValid` 校验与测试共享同一实现，规则改名即测试失败
- 新增 ContentLibraryTests 10 例（资源加载/模板数/命名一致/72 变体全覆盖/被动属性一致/图标键完整等）
- 美术资产重制（生成规范见 Docs/资产v2-生成规范.md）：八轴契约 + master 基准图保证全套风格一致，
  同名覆盖上一批；新增 45 张 `_widget` 后缀组件尺寸变体（职业/装备，供 Widget/灵动岛用）
- 接入指南：Docs/美术资产与技能库接入指南.md
- 交付包两处修正（本地 Windows XCTest 实测发现并修复）：
  ① SwiftPM 资源处理在本机 Windows 工具链不可用（WindowsError 4551，最小复现亦失败）——
  JSON 改放 `Sources/PingIslandKit/Content/`（目录名 Resources 会被 SwiftPM 隐式当资源处理），
  Package.swift 保持原样；`ContentLibrary.load()` 改为 Bundle.main → 源码树路径两级回退，
  project.yml 把 JSON 以 resources 构建阶段打进 App 主 bundle
  ② JSON 缺周日（7）模板：周日与周六同为雷，查找时归一化到 6（与 SkillRules 映射一致），
  修复前 16 个测试失败（周日 12 变体查不到）
- 本地验证：Windows XCTest **118/118 通过**（原 108 + 内容库 10）
- 分支：`feat/content-skills`；UI 侧引用（Image(图标键) 替换 SF Symbol 占位）随后续合并进行

## 2026-11-06 美术资源分支（feat/assets-v2）
- 合入《PingIsland-Assets V2》：标准 .xcassets 结构 56 个 imageset / 93 张 PNG（约 22 MB）
- 覆盖：8 职业立绘（768×1152）、16 装备图（4 部位 × 布/皮/铁/机甲外观，768×768）、
  5 疲劳阶段、3 遭遇怪（史莱姆/骷髅/哥布林）、12 技能图标（6 元素 × 主动/被动）、
  夜间睡姿、新版 AppIcon（1024×1024 水彩岛屿）
- 命名与代码枚举对齐：class_* / eq_部位_外观 / fatigue_* / skill_元素_active|passive / monster_*
  —— SwiftUI 侧可按名直接 `Image("...")` 引用
- 风格统一为水彩 Q 版（与 holo 卡牌卡框裁切方式匹配）；单 scale 无 @2x/@3x，RGB 无透明通道（卡面图带背景）
- 分支：`feat/assets-v2`（自 feat/ui-redesign `06ac420`）；UI 引用接入随 holo 分支后续进行

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

## 2026-11-02 真机反馈修复二：模拟结算接通展示链路
- 现象：调试面板注入模拟事件只有高水位+1，日记页/角色页/Widget 全无变化
- 根因：模拟账本结算结果从未同步到展示快照——角色/日记/Widget 读的是生产快照，桥没搭
- 修复：SettlementCoordinator 新增 syncDisplayFromSimulated(_:)（仅模拟数据用）；注入后同步快照 + WidgetCenter.reloadAllTimelines + Live Activity
- 体验：同组同日同阈值重复注入会提示"无新增入账分钟（补差不倒退），调高阈值再试"；运行状态新增模拟高水位

## 2026-11-02 真机反馈修复三：小组件不同步的根因与诊断
- 现象：模拟结算后角色页/日记页正常，桌面小组件始终占位（等级1）
- 定位：主 App 与 Widget 扩展靠 App Group 共享快照；主 App 内读写正常（两页即证明），扩展读不到 → Sideloadly 免费自签不解备 App Group（同 FamilyControls 一类签名限制）
- 处置：调试面板运行状态新增"共享容器：可用/不可用"与"快照：vN 等级X"诊断行；KNOWN_LIMITATIONS 记录限制与替代签名方式（付费账号 / SideStore）

## 2026-11-02 真机反馈修复四：智慧成长规则 + Live Activity 声明
- 数值答疑：31 级是设计本意（文档 8.3 验收例：30 分钟骰点 15 → 等级 50）；升级不加 CON/INT/DEX 也是设计
- 但「基础智慧 = 初始智慧 + G」（文档 8.3）代码漏实现：SettlementEngine 第 5 步补 WIS 增量（按 G 的增量补，跨段小数不进位）
- 新增 WisdomGrowthEngineTests 2 例（不变式：任意时刻 WIS = 初始 + G）；Kit 回归 97/97
- Live Activity 点击无反应：主 App 与 Widget 扩展 Info.plist 缺 NSSupportsLiveActivities → 补声明（真机确认行为）

## 2026-11-02 真机反馈修复五：灵动岛可见性
- 诊断：锁屏已出现实时活动与系统授权弹窗（活动本身启动成功）；灵动岛"无内容"主因是 App 在前台时系统不在灵动岛展示本 App 的活动（iOS 行为），加上多次启动堆叠了多个活动
- 修复：启动前先结束旧活动（11.3 同一时刻一个活动）

## 2026-11-02 真机反馈修复六：灵动岛活动被自杀
- 根因：上轮"先结束后创建"用了独立 Task，结束任务在新活动创建后才执行，把新活动一并结束（经典竞态）→ 点击开启后任何卡片都不出现
- 修复：结束旧活动与创建新活动放进同一 Task 顺序执行；启动前预检 areActivitiesEnabled，被拒时给出确切设置路径

## 2026-11-02 真机验证里程碑：灵动岛全通
- iPhone 18 Pro Max / iOS 27.0.1（Sideloadly 免费自签）：Live Activity 启动、桌面灵动岛紧凑态（🏝️+Lv）、锁屏卡片与长按展开全部通过
- 修复路上共定位三个真 bug：缺 NSSupportsLiveActivities 声明（Info.plist）、清理旧活动的异步竞态杀新活动、模拟结算未接展示链路
- 至此规则循环（结算→快照→灵动岛/锁屏/页面）在真机完整跑通；桌面小组件受 App Group 签名限制、真实监控受 Family Controls 签名限制，均需付费账号或换签名方式

## 2026-11-02 真机反馈修复七：装备展示显示具体词条
- 现象：装备只显示"白装 · 部位 · 评 N"，看不出加什么属性；用户疑惑白装是否生效
- 澄清：生成规则本就正确（白装=1 条随机 CON/INT/DEX +1，文档 9.4）；缺的是展示
- 修复：SnapshotPresentation.equipmentSummary 统一格式化"部位 · 品阶 · CON +1、INT +2（评 N）"，装备栏与收藏页同时生效；新增格式化测试 2 断言组

## 2026-11-02 真机反馈修复八：角色面板显示最终属性
- 现象：装备词条记录正确、装备栏显示正确，但角色面板属性数字不含装备加成
- 根因：refreshSnapshot 写快照用 baseAttributes（不含装备），展示应为最终属性
- 修复：改用 engine.finalAttributes()（基础+已装备词条，Kit 已有组合逻辑与测试）

## 2026-11-02 真机反馈修复九：收藏装备中标记 + 模拟跨天
- 收藏页同部位多个"装备中"：换装时旧藏品的装备标记未撤 → apply() 换装备时同步撤销旧条目标记（Kit 回归 97/97）
- 日记页上限 10 → 30 条（快照 recentDiaries）
- "点着点着没反应"澄清：同日同阈值注入按"补差不倒退"规则无新入账，非死机；结算预览已显示"日期 · 新增入账 X 分钟 · 骰点 D"便于判断
- 调试面板：阈值步进改为 30 分钟粒度（30~480）；新增"模拟过一天"按钮（今天+N 天注入，每日独立骰点）；结算结果显示当日骰点
- 收藏"19 个上限"：收藏页无代码上限，19 是同日探索饱和后的存量；过天后可继续增长

## 2026-11-03 真机反馈批次一：成长规则 v1.1 + 神谕日记 + 收藏增强展示
- **成长规则 v1.1（行天修订，替代文档 v1.0「1 XP = 1 级」）**：100 XP 升 1 级（骰点 10 时 100 分钟一级）；智慧 = 初始 +（等级 − 1），每级 +1
- 骰点 20 神谕：日记新增 oracleBoon 条目（"☀️ 骰点 20 大成功·神谕降临" + 具体奖励数值），每日一次有测试
- 收藏页增强：品阶字体颜色（白/绿/蓝/紫/橙/红）、外观类型图标（布 tshirt/皮 半盾/铁 盾/机甲 cpu）、装备中条目显示获得时间+原因
- EquipmentItem 新增 acquiredAt/origin（旧存档 decodeIfPresent 兼容）；快照新增 collectionDetail 结构化字段（旧快照回退字符串）
- Kit 回归 101/101（成长/智慧/神谕新测试 6 例）
- CI 修复两轮：DiaryView 补 `import PingIslandKit`（Rarity scope）；`SimulatedUsageSourceTests` 升级断言对齐 v1.1（60 分钟单事件不保证升级，改为断言成长入账 + 等级公式自洽）。Actions 三任务全绿（run 41495020893），IPA 已下载
- 待做（下一批）：日记页"屏幕使用时间"式周/日分区展示；角色页六边形雷达 + 魔兽式装备/技能面板

## 2026-11-03 真机反馈批次二：文案精简
- 神谕日记条目简化为「☀️ 神谕降临」（删去「骰点 20 大成功」字样），奖励数值行保留
- 收藏页结构化条目省略「白装/绿装」等品阶文字（品阶已由字体颜色表达），格式改为「部位 · 词条（评 N）」；旧快照回退字符串保持原样
- Kit 回归 101/101；Actions run 41560778589 三任务全绿，IPA 已下载

## 2026-11-03 UI 改版分支（feat/ui-redesign，第九次反馈点名两项）
- 引擎新增按日聚合 DayStats（分钟/成长值/升级数，旧存档 decodeIfPresent 兼容）+ 5 个新测试
- 快照新增：diaryDetail（结构化日记）、weekStats（本周一~日聚合）、equippedDetail（四部位）、skills（技能收藏前 6）、todayDice
- 日记页「屏幕使用时间」式改版：本周汇总卡（总分钟 + 经验/升级/日记数 + 7 天柱状图）→ 今天分区（最常使用式行）→ 更早按日分组；旧快照回退原列表
- 角色页重设计：中上职业/等级/最新日记；正中左装备栏（四部位图标，品阶配色）· 职业形象（觉醒后显示职业符号）· 右特质栏（今日骰点 + 技能图标带等级角标）；中下六边形属性雷达（自绘 Path，3 层网格环）
- 分支：feat/ui-redesign（自 feat/xcode-ci-build 切出）；CI run 41565658226 全绿，IPA 已下载

## 2026-11-03 真机反馈批次三（第十二批）：三页版面精简
- 日记页 / 收藏页删除导航大标题（底部标签已表意）
- 角色页合一卡片：行1 状态·职业·等级居中同行；行2 最新日记+最近结算整体居中；行3 左装备栏·立绘·右特质栏；行4 六边形雷达——全部同卡
- 收藏页改版：上方四宫格（当前装备四部位卡：图标+品阶配色+词条+评分）；下方"今日获得"分区（与日记当天同款行式，只留当天获得，过天清空）；旧存档装备无获得时间不计入今日
- 移除 List 容器改 ScrollView + LazyVStack/LazyVGrid（去分组列表样式）；CI 全绿，IPA 已下载

## 2026-11-04 真机反馈批次四（第十三批）：调试链路修正 + 版面细节
- 调试面板「模拟过一天」改为仅切换日期（不再连带注入结算）；偏移量持久化，重启保留
- 调试面板新增「刷新展示」按钮；「重置模拟数据」同步清零展示（特质/骰点/等级全部归零）
- Kit 新增 previewDice（预览骰点=结算骰点，不写状态）+ 2 测试；快照新增 dayOffset，"今天"判定（日记/收藏今日分区、周卡高亮、角色页骰点）全部跟随模拟日期
- 修复结束实时活动后锁屏残留：dismissalPolicy .default → .immediate
- 灵动岛开关移至设置页；角色页头部绝对居中（ZStack 左状态/中职业等级，删"状态："字样）、卡牌整体缩小（立绘 92、雷达 190）
- 日记/收藏页顶部留白 +10；收藏四宫格固定 132 等高；今日获得行式对齐日记页并删除（评 N）
- DisplaySnapshot 自定义兼容解码（旧快照缺新键不崩）；Kit 108/108；CI 全绿，IPA 已下载
