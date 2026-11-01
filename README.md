# 屏之岛（PingIsland）

幻想冒险题材的角色陪伴与放置养成 iOS App。用户正常使用手机，岛上的角色依据**可确认的使用里程碑**自动结算成长。

- 产品基线：《屏之岛》游戏设计文档 v2.3
- 工程依据：《屏之岛_iOS原生App开发执行文档 v1.0》（Kimi Work 版）
- 开发路线（2026-11-02 更新，用户确认无 Mac）：**Windows 写码 + 本机 `swift test` → push → GitHub Actions 免费 macOS runner 编译出未签名 IPA → 下载后用 Sideloadly 自签装进 iPhone，全部真机测试。**

## 目录结构

```text
PingIsland/
  project.yml            # XcodeGen 工程定义（多 Target，xcodegen generate 生成 .xcodeproj）
  App/ Onboarding/ Character/ Diary/ Settings/ Recovery/ Shared/ Resources/
  PingIslandKit/         # 平台无关规则引擎（Swift Package，Windows/macOS 均可 XCTest）
  PingIslandMonitor/     # DeviceActivityMonitor 扩展
  PingIslandWidgets/     # WidgetKit 桌面卡片 + Live Activity（灵动岛/锁屏）
  Tests/                 # 集成测试 + UI 测试
  Docs/                  # 环境、平台验证、已知限制、变更记录
  .github/workflows/     # CI：规则测试 / 模拟器测试 / 未签名 IPA
```

## 本地验证（Windows）

```bash
cd PingIslandKit && swift test     # 规则引擎（SDKROOT 已写入用户环境变量）
```

## CI 构建与装机

1. push 后 Actions 自动跑：规则测试 → 模拟器测试 → 构建未签名 IPA（工件保留 14 天）
2. 在 Actions 运行页下载 `PingIsland-unsigned-ipa` 工件
3. Sideloadly 选 IPA + 自己的 Apple ID 自签安装；iPhone 上信任证书
4. 注意：`com.apple.developer.family-controls` 授权需要付费 Apple Developer 账号单独申请；
   免费自签下监控功能不可用，其余功能（角色/卡片/灵动岛）可正常测试（见 Docs/KNOWN_LIMITATIONS.md）
