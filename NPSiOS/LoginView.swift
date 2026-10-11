import SwiftUI

struct LoginView: View {
    @EnvironmentObject var client: NPSClient

    @State private var baseURL: String = ""
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var isLoggingIn: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    VStack(spacing: 8) {
                        Image(systemName: "network")
                            .font(.system(size: 56))
                            .foregroundColor(.blue)
                        Text("NPS 管理")
                            .font(.largeTitle.weight(.bold))
                        Text("管理你的内网穿透服务器")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 40)

                    VStack(spacing: 14) {
                        LabeledField(title: "服务器地址", text: $baseURL,
                                     placeholder: "http://1.2.3.4:8080", keyboard: .URL)
                        LabeledField(title: "用户名", text: $username, placeholder: "admin")
                        VStack(alignment: .leading, spacing: 4) {
                            Text("密码")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            SecureField("密码", text: $password)
                                .padding(10)
                                .background(Color(.tertiarySystemBackground))
                                .cornerRadius(10)
                        }
                    }

                    if let msg = client.errorMessage, !client.sessionExpired {
                        Text(msg)
                            .font(.caption)
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button {
                        Task { await doLogin() }
                    } label: {
                        if isLoggingIn {
                            ProgressView().tint(.white)
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("登录")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: 48)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .disabled(isLoggingIn || baseURL.isEmpty)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("说明")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                        Text("• 地址填写 NPS 后台 Web 地址（含端口）。\n• 若服务端配置了 web_base_url 前缀，请一并写上，例如 https://nps.example.com/web。\n• 凭据仅保存在本机钥匙串，不会上传。")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(24)
            }
            .navigationBarHidden(true)
        }
        .onAppear {
            // Pre-fill from saved credentials for convenience.
            if let u = KeychainHelper.read(account: "baseURL") { baseURL = u }
            if let n = KeychainHelper.read(account: "username") { username = n }
        }
    }

    private func doLogin() async {
        isLoggingIn = true
        defer { isLoggingIn = false }
        client.baseURL = baseURL
        _ = await client.login(username: username, password: password, save: true)
    }
}
