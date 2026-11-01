# 屏之岛（PingIsland）

幻想冒险题材的角色陪伴与放置养成 iOS App。用户正常使用手机，岛上的角色依据**可确认的使用里程碑**自动结算成长。

- 产品基线：《屏之岛》游戏设计文档 v2.3
- 工程依据：《屏之岛_iOS原生App开发执行文档 v1.0》（Kimi Work 版）
- 当前状态：**环境配置阶段 + 平台无关规则引擎开发**（原生 iOS 工程验收因无 macOS/Xcode 暂停，见 `Docs/ENVIRONMENT_BLOCKED.md`）

## 目录结构

```text
PingIsland/
  PingIslandKit/        # 平台无关规则引擎（Swift Package，可在 Windows/macOS 跑 XCTest）
    Sources/PingIslandKit/
    Tests/PingIslandKitTests/
  Docs/                 # 环境、平台验证、已知限制、变更记录
  .github/workflows/    # CI
```

## 规则引擎验证（任何平台）

```bash
cd PingIslandKit
swift test
```

## 当前 BLOCKED 项

- 原生多 Target Xcode 工程、DeviceActivity / WidgetKit / ActivityKit 验证：需要 macOS + Xcode（见 Docs/ENVIRONMENT_BLOCKED.md）
