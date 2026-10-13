import SwiftUI
import UIKit

/// GitHub Release info for the in-app update checker.
struct ReleaseInfo: Codable {
    let tag_name: String
    let name: String?
    let body: String?
    let assets: [Asset]

    struct Asset: Codable {
        let name: String
        let browser_download_url: String
    }
}

struct SettingsView: View {
    @EnvironmentObject var client: NPSClient
    @State private var showLogoutConfirm: Bool = false
    @State private var switchingID: String? = nil

    @State private var updateState: UpdateState = .idle
    @State private var latestRelease: ReleaseInfo?

    enum UpdateState: Equatable {
        case idle, checking, upToDate, available, failed
    }

    private static let currentVersion =
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?"

    var body: some View {
        NavigationStack {
            Form {
                Section("当前服务器") {
                    if !client.baseURL.isEmpty {
                        HStack {
                            Text("地址")
                            Spacer()
                            Text(client.baseURL).foregroundColor(.secondary).font(.callout)
                        }
                    }
                    if !client.username.isEmpty {
                        HStack {
                            Text("用户名")
                            Spacer()
                            Text(client.username).foregroundColor(.secondary).font(.callout)
                        }
                    }
                }

                Section("已保存账号") {
                    let saved = AccountStore.load()
                    if saved.isEmpty {
                        Text("暂无").foregroundColor(.secondary).font(.callout)
                    } else {
                        ForEach(saved) { acc in
                            HStack {
                                Image(systemName: acc.scheme == "https" ? "lock.shield" : "server.rack")
                                    .foregroundColor(.blue)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(acc.baseURL).font(.callout)
                                    Text(acc.username).font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                if acc.baseURL == client.baseURL && acc.username == client.username {
                                    Text("当前").font(.caption).foregroundColor(.blue)
                                } else if switchingID == acc.id {
                                    ProgressView()
                                } else {
                                    // One-tap switch: logs in with the saved
                                    // credentials without leaving the app.
                                    Button("切换") {
                                        Task { await switchTo(acc) }
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(.blue)
                                    .font(.caption.weight(.semibold))
                                }
                            }
                        }
                        Text("点击「切换」直接登录到对应账号，无需退出；退出登录后凭据仍会保留。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showLogoutConfirm = true
                    } label: {
                        Text("退出登录")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }

                Section("软件更新") {
                    switch updateState {
                    case .idle, .checking:
                        HStack {
                            Text("正在检查更新…")
                                .foregroundColor(.secondary)
                            Spacer()
                            ProgressView()
                        }
                    case .upToDate:
                        Text("已是最新版本 v\(SettingsView.currentVersion)")
                            .foregroundColor(.secondary)
                    case .available:
                        if let rel = latestRelease {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("发现新版本 \(rel.tag_name)（当前 v\(SettingsView.currentVersion)）")
                                    .font(.callout.weight(.semibold))
                                    .foregroundColor(.orange)
                                if let body = rel.body, !body.isEmpty {
                                    Text(body)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(12)
                                }
                                if let url = rel.assets.first(where: { $0.name.lowercased().hasSuffix(".ipa") })?.browser_download_url
                                    .flatMap(URL.init(string:)) {
                                    Button {
                                        UIApplication.shared.open(url)
                                    } label: {
                                        Label("下载 IPA（Safari 打开后用巨魔安装）", systemImage: "arrow.down.circle.fill")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                            }
                        }
                    case .failed:
                        Text("检查更新失败，请确认网络后重试。")
                            .foregroundColor(.secondary)
                    }
                    Button {
                        Task { await checkForUpdate() }
                    } label: {
                        Text(updateState == .failed ? "重试" : "检查更新")
                    }
                }

                Section("关于 NPS iOS") {
                    LabeledRow(title: "项目", value: "https://github.com/ehang-io/nps")
                    LabeledRow(title: "功能", value: "管理 NPS 内网穿透服务器")
                    LabeledRow(title: "版本", value: "1.0.3")
                    Text("本应用通过 NPS Web 后台 API 管理你的服务器：查看客户端/隧道/主机、增删改、启停隧道、查看流量与在线状态。凭据保存在本机钥匙串，不上传任何第三方。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("安全说明") {
                    Text("由于 NPS 常使用 HTTP 或自签名 HTTPS，本应用在 Info.plist 中关闭了 ATS 限制（NSAllowsArbitraryLoads）。仅在你信任的网络下使用。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("设置")
            .onAppear {
                // Auto-check once per visit; cheap public API call.
                if updateState == .idle { Task { await checkForUpdate() } }
            }
            .alert("确认退出登录？", isPresented: $showLogoutConfirm) {
                Button("取消", role: .cancel) {}
                Button("退出", role: .destructive) { client.logout() }
            }
        }
    }

    /// Directly log in to another saved account from Settings.
    private func switchTo(_ acc: NPSAccount) async {
        switchingID = acc.id
        defer { switchingID = nil }
        _ = await client.switchAccount(to: acc)
    }

    // MARK: - Update check (GitHub Releases)
    private func checkForUpdate() async {
        updateState = .checking
        guard let url = URL(string: "https://api.github.com/repos/tianyuan0725/npsiOS/releases/latest") else {
            updateState = .failed
            return
        }
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let rel = try JSONDecoder().decode(ReleaseInfo.self, from: data)
            latestRelease = rel
            if Self.isNewer(rel.tag_name, than: SettingsView.currentVersion) {
                updateState = .available
            } else {
                updateState = .upToDate
            }
        } catch {
            updateState = .failed
        }
    }

    /// Compare "v1.2.3" style tags numerically.
    private static func isNewer(_ tag: String, than current: String) -> Bool {
        let tagParts = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            .split(separator: ".").compactMap { Int($0) }
        let curParts = current.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(tagParts.count, curParts.count) {
            let t = i < tagParts.count ? tagParts[i] : 0
            let c = i < curParts.count ? curParts[i] : 0
            if t != c { return t > c }
        }
        return false
    }
}

struct LabeledRow: View {
    let title: String
    let value: String
    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundColor(.secondary).font(.callout).multilineTextAlignment(.trailing)
        }
    }
}
