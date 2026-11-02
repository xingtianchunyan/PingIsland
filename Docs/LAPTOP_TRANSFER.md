# 转移到笔记本操作清单（真机装机环境）

台式机无 USB-C 无法连 iPhone，装机与真机测试改到 Windows 笔记本进行。本清单在克隆仓库后可直接对照执行。

## 一、代码（无需拷贝任何文件）

代码全部已推送到 GitHub 私有仓库，笔记本上克隆即可：

```powershell
git clone https://github.com/xingtianchunyan/PingIsland.git
cd PingIsland
git checkout feat/xcode-ci-build
```

文档（Docs/CHANGELOG.md、COVERAGE.md、KNOWN_LIMITATIONS.md、PLATFORM_VALIDATION.md、本清单）随仓库一起到手。

## 二、需要随身带的东西（U 盘拷 3 个文件）

| 文件 | 位置（台式机） | 用途 |
|---|---|---|
| `PingIsland-unsigned.ipa` | `D:\dev\PingIsland\dist\` | 游戏本体（约 450 KB，仓库不入库） |
| `iCloudSetup.exe` | `D:\Backup\Downloads\` | 桌面版 iCloud（Sideloadly 前置） |
| `iTunes64Setup.exe` | `D:\Backup\Downloads\` | 桌面版 iTunes（提供设备驱动） |

Sideloadly 届时从官网下载：https://sideloadly.io → Download → Windows 64-bit。

## 三、笔记本环境准备（按序执行）

### 1. 装 iCloud（大概率再次遇到"缺少 media feature pack"）

笔记本若是 Windows 11 24H2，苹果安装程序的老 bug 会重现。先以**管理员身份**打开 PowerShell，执行：

```powershell
dism /online /enable-feature /featurename:WindowsMediaPlayer /all /norestart
```

看到"操作成功完成"且 `WindowsMediaPlayer | 已启用` 后，再运行 `iCloudSetup.exe`。
（根因：24H2 默认禁用旧版 Windows Media Player 且从设置界面隐藏，iCloud 安装程序恰恰检查它。）

### 2. 装 iTunes

先确认笔记本没有商店版 iTunes（设置 → 应用 → 搜 iTunes，有就卸载），然后运行 `iTunes64Setup.exe`。装完不用打开。

### 3. 装 Sideloadly

官网下载安装，打开即可。

## 四、装机

1. iPhone 数据线连笔记本（USB-C 口），手机上点「信任此电脑」。
2. Sideloadly 中拖入 `PingIsland-unsigned.ipa`。
3. 填入 Apple ID（免费账号即可；有双重认证会引导验证），点 Start。
4. 手机桌面出现《屏之岛》→ 设置 → 通用 → VPN与设备管理 → 信任该开发者证书 → 打开 App。

## 五、可选：在笔记本上跑规则测试

需要的话装 swift.org 官方 Windows 工具链（6.4.2）并设置 SDKROOT 环境变量，见任务书；不装也完全不影响装机与真机测试。
