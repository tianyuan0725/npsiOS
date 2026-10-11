# NPS iOS 客户端

一个用于管理 [NPS](https://github.com/ehang-io/nps) 内网穿透服务器的 iOS 原生客户端（SwiftUI）。
通过 NPS Web 后台的 HTTP API 直接管理你的服务器：查看客户端 / 隧道 / 域名主机，增删改，启停隧道，查看在线状态与流量。

> 本项目由 WorkBuddy 生成。代码已按 NPS 官方 web 后台 API（beego AutoRouter）逐一核对字段与路由。

## 功能

- **仪表盘**：客户端总数 / 在线数、隧道总数、域名主机数、入站/出站流量、隧道类型分布、客户端在线状态。
- **客户端管理**：列表、新增、编辑、删除、启用/停用。
- **隧道管理**：TCP / UDP / Socks5 / HTTP 代理 / 私密 / P2P 隧道，列表、新增、编辑、删除、启动/停止。
- **主机（域名）管理**：域名代理列表、新增、编辑、删除，支持协议 / 路径 / Header&Host 改写 / HTTPS 证书。
- **安全**：服务器地址、用户名、密码仅保存在本机钥匙串（Keychain），不上传任何第三方。
- 启动时自动用已保存凭据静默重新登录，会话过期自动退回登录页。

## 构建与安装（需要 macOS + Xcode）

1. 在 macOS 上用 **Xcode 15 或更新版本** 打开 `NPSiOS.xcodeproj`。
2. 选择 `NPSiOS` target → **Signing & Capabilities**：
   - 选择你的 **Team**（免费 Apple ID 即可；首次需在 Xcode → Settings → Accounts 登录）。
   - 把 **Bundle Identifier** 改成你自己的唯一标识，例如 `com.yourname.npsiOS`。
3. （可选）把应用图标放进 `NPSiOS/Assets.xcassets/AppIcon.appiconset`。
4. 用数据线连接 iPhone，选择它为运行目标，按下 **⌘R** 编译运行。
   - 免费账号签名有效期 7 天，到期需重新连 Xcode 跑一次；首次安装后到
     **iOS 设置 → 通用 → VPN与设备管理** 里信任开发者。
   - 也可通过 AltStore / Sideloadly 等侧载工具安装。

## 使用

- **服务器地址**：填写 NPS 后台 Web 地址，含端口，例如 `http://1.2.3.4:8080`。
  若你的服务端配置了 `web_base_url` 前缀，需一并写上，例如 `https://nps.example.com/web`。
- **用户名 / 密码**：NPS 后台的 Web 管理员账号（默认 `web_username` / `web_password`，在 `nps.conf` 中配置）。
- 登录后即可管理。

## 实现说明

- 鉴权方式与官方 Web 后台一致：POST `Login/Verify` 获取会话 Cookie，后续请求自动复用。
- 仪表盘数据由「客户端 / 隧道 / 主机」列表接口实时汇总得出（NPS 后台没有独立的 JSON 仪表盘接口）。
- 因 NPS 常使用 HTTP 或自签名 HTTPS，`Info.plist` 中关闭了 ATS 限制（`NSAllowsArbitraryLoads`）。
  仅在你信任的网络下使用；如需更严格的限制，可改为按域名放行。

## 没有 Mac 也能出 IPA（GitHub Actions 云端编译）

本仓库自带 `.github/workflows/build-ipa.yml`，会在 GitHub 免费的 macOS 云构建机上自动编译并产出 **未签名 IPA**，你只需把代码推到 GitHub 即可下载：

1. 把 `NPSiOS/` 目录初始化为 Git 仓库并推到 GitHub（公开或私有均可）：
   ```bash
   cd NPSiOS
   git init
   git add .
   git commit -m "NPS iOS client"
   git branch -M main
   git remote add origin https://github.com/你的用户名/npsiOS.git
   git push -u origin main
   ```
2. 打开仓库页面 → **Actions** → 左侧 `Build NPS iOS IPA` → **Run workflow**（也可直接 push 到 main 自动触发）。
3. 构建完成后，在 Actions 运行记录页底部的 **Artifacts** 里下载 `NPSiOS-unsigned-ipa`（即 `NPSiOS.ipa`）。
4. 在电脑上用 **Sideloadly**（Windows / macOS 都有，免费）打开这个 IPA，填入你的 Apple ID，把手机连上电脑即可安装到 iPhone。
   - 免费 Apple ID 签名的 App 有效期 **7 天**，到期用 Sideloadly 重新签一次即可。
   - 若你有付费开发者账号，也可把证书/描述文件作为 GitHub Secrets 接入工作流做长期签名（需要时可帮你改工作流）。

> 说明：云端编译产出的是**未签名** IPA（iOS 不允许无签名安装）。Sideloadly 会在你本地用你的 Apple ID 完成签名，所以不需要 Mac，也不需要上传任何账号密码到云端。

## 目录结构

```
NPSiOS/
├── NPSiOS.xcodeproj/      Xcode 工程
└── NPSiOS/
    ├── NPSiOSApp.swift     App 入口
    ├── ContentView.swift   RootView / Tab 导航
    ├── Models.swift        API 数据模型（Codable）
    ├── NPSClient.swift     网络层 + 鉴权 + 所有 API 调用
    ├── KeychainHelper.swift  钥匙串存储
    ├── Shared.swift        通用 UI 组件
    ├── LoginView.swift     登录页
    ├── DashboardView.swift 仪表盘
    ├── ClientsView.swift / ClientFormView.swift       客户端
    ├── TunnelsView.swift / TunnelFormView.swift      隧道
    ├── HostsView.swift   / HostFormView.swift        域名主机
    ├── SettingsView.swift  设置 / 退出登录
    ├── Info.plist
    └── Assets.xcassets
```
