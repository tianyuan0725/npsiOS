import SwiftUI

struct LoginView: View {
    @EnvironmentObject var client: NPSClient

    @State private var scheme: String = "http"
    @State private var host: String = ""
    @State private var accounts: [NPSAccount] = []
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
                        // Protocol picker: no need to type http:// or https://.
                        Picker("协议", selection: $scheme) {
                            Text("http://").tag("http")
                            Text("https://").tag("https")
                        }
                        .pickerStyle(.segmented)

                        // Address only — the scheme comes from the picker above.
                        // If a full URL is pasted, the scheme is detected and
                        // stripped automatically.
                        LabeledField(title: "服务器地址（不含 http:// 或 https://）", text: $host,
                                     placeholder: "1.2.3.4:8080", keyboard: .URL)
                            .onChange(of: host) { newValue in
                                if let r = newValue.range(of: "://") {
                                    let s = String(newValue[..<r.lowerBound]).lowercased()
                                    if s == "http" || s == "https" {
                                        scheme = s
                                        host = String(newValue[r.upperBound...])
                                            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                                    }
                                }
                            }

                        LabeledField(title: "用户名", text: $client.username, placeholder: "admin")
                        VStack(alignment: .leading, spacing: 4) {
                            Text("密码")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            SecureField("密码", text: $client.password)
                                .padding(10)
                                .background(Color(.tertiarySystemBackground))
                                .cornerRadius(10)
                        }
                    }

                    if let msg = client.errorMessage {
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
                    .disabled(isLoggingIn || host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if !accounts.isEmpty {
                        savedAccountsSection
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("说明")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                        Text("• 地址只填 IP:端口 或域名（协议用上方按钮切换）。\n• 若服务端配置了 web_base_url 前缀，请一并写上，例如 nps.example.com/web。\n• 登录成功后账号会保存到「已保存账号」，退出登录不会清除，下次无需重新输入。\n• 凭据仅保存在本机钥匙串，不会上传。")
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
            AccountStore.migrateLegacy()
            accounts = AccountStore.load()
            prefillLastAccount()
        }
    }

    // MARK: - Saved accounts (multi-account switching)
    private var savedAccountsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("已保存账号 (\(accounts.count))")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
            VStack(spacing: 8) {
                ForEach(accounts) { acc in
                    HStack {
                        Button {
                            apply(account: acc)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: acc.scheme == "https" ? "lock.shield" : "server.rack")
                                    .foregroundColor(.blue)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(acc.baseURL)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundColor(.primary)
                                    Text(acc.username)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if isCurrent(acc) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                        .buttonStyle(.plain)

                        Button {
                            accounts = AccountStore.remove(id: acc.id)
                        } label: {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(10)
                    .background(Color(.tertiarySystemBackground))
                    .cornerRadius(10)
                }
            }
            Text("点击任意账号即可填入，删除按钮可移除不再使用的账号。")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func isCurrent(_ acc: NPSAccount) -> Bool {
        acc.scheme == scheme
            && acc.host == host.trimmingCharacters(in: .whitespacesAndNewlines)
            && acc.username == client.username
    }

    private func apply(account: NPSAccount) {
        scheme = account.scheme
        host = account.host
        client.username = account.username
        client.password = account.password
        client.errorMessage = nil
    }

    /// Pre-fill the form with the last-used account; fall back to the most
    /// recent one, then to the legacy single-account keys.
    private func prefillLastAccount() {
        if let id = AccountStore.lastID, let acc = accounts.first(where: { $0.id == id }) {
            apply(account: acc)
            return
        }
        if let first = accounts.first {
            apply(account: first)
            return
        }
        // Legacy fallback (fresh install on an old version).
        if let u = KeychainHelper.read(account: "baseURL") {
            var rest = u
            if let r = rest.range(of: "://") {
                let s = String(rest[..<r.lowerBound]).lowercased()
                if s == "http" || s == "https" { scheme = s }
                rest = String(rest[r.upperBound...])
            }
            host = rest.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        if let n = KeychainHelper.read(account: "username") { client.username = n }
        if client.password.isEmpty, let p = KeychainHelper.read(account: "password") {
            client.password = p
        }
    }

    private func doLogin() async {
        let cleanHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanHost.isEmpty else { return }
        host = cleanHost
        isLoggingIn = true
        defer { isLoggingIn = false }
        client.baseURL = "\(scheme)://\(cleanHost)"
        let ok = await client.login(username: client.username, password: client.password, save: true)
        if ok {
            // Save into the multi-account list and mark as last used, so
            // logging out never requires re-typing address / credentials.
            let acc = NPSAccount(scheme: scheme, host: cleanHost,
                                 username: client.username, password: client.password)
            accounts = AccountStore.upsert(acc)
        }
    }
}
