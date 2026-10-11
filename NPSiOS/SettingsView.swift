import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var client: NPSClient
    @State private var showLogoutConfirm: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Section("当前服务器") {
                    if let url = KeychainHelper.read(account: "baseURL") {
                        HStack {
                            Text("地址")
                            Spacer()
                            Text(url).foregroundColor(.secondary).font(.callout)
                        }
                    }
                    if let user = KeychainHelper.read(account: "username") {
                        HStack {
                            Text("用户名")
                            Spacer()
                            Text(user).foregroundColor(.secondary).font(.callout)
                        }
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
                    LabeledRow(title: "版本", value: "1.0.0")
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
