import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var client: NPSClient
    @State private var showLogoutConfirm: Bool = false
    @State private var switchingID: String? = nil

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

                Section("关于 NPS iOS") {
                    LabeledRow(title: "项目", value: "https://github.com/ehang-io/nps")
                    LabeledRow(title: "功能", value: "管理 NPS 内网穿透服务器")
                    LabeledRow(title: "版本", value: "1.0.2")
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
