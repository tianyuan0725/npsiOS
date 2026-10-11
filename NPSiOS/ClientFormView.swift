import SwiftUI

struct ClientFormView: View {
    @EnvironmentObject var client: NPSClient
    @Environment(\.dismiss) private var dismiss

    // nil = add mode, non-nil = edit mode
    let editing: Client?

    @State private var remark: String = ""
    @State private var vkey: String = ""
    @State private var compress: Bool = false
    @State private var crypt: Bool = false
    @State private var configConnAllow: Bool = false
    @State private var rateLimit: String = ""
    @State private var maxConn: String = ""
    @State private var maxTunnel: String = ""
    @State private var flowLimit: String = ""
    @State private var webUsername: String = ""
    @State private var webPassword: String = ""
    @State private var isSaving: Bool = false
    @State private var loadError: String?

    init(client: Client?) {
        self.editing = client
    }

    var body: some View {
        Form {
            Section("基本信息") {
                LabeledField(title: "备注", text: $remark, placeholder: "例如 家里路由器")
                LabeledField(title: "连接密钥 (VerifyKey)", text: $vkey,
                             placeholder: "客户端连接所用密钥", keyboard: .asciiCapable)
                Toggle("压缩传输", isOn: $compress)
                Toggle("加密传输", isOn: $crypt)
                Toggle("允许配置文件连接", isOn: $configConnAllow)
            }
            Section("限制") {
                LabeledField(title: "速率限制 (KB/s, 0=不限)", text: $rateLimit, keyboard: .numberPad)
                LabeledField(title: "最大连接数 (0=不限)", text: $maxConn, keyboard: .numberPad)
                LabeledField(title: "最大隧道数 (0=不限)", text: $maxTunnel, keyboard: .numberPad)
                LabeledField(title: "流量限制 (MB, 0=不限)", text: $flowLimit, keyboard: .numberPad)
            }
            Section("客户端 Web 登录 (可选)") {
                LabeledField(title: "Web 用户名", text: $webUsername, placeholder: "留空则不启用")
                SecureField("Web 密码", text: $webPassword)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            if let e = loadError {
                Section { Text(e).foregroundColor(.red).font(.caption) }
            }
        }
        .navigationTitle(editing == nil ? "新增客户端" : "编辑客户端")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(editing == nil ? "创建" : "保存") { Task { await save() } }
                    .disabled(isSaving)
            }
        }
        .overlay { if isSaving { LoadingView() } }
        .task { await loadIfEdit() }
    }

    private func loadIfEdit() async {
        guard let c = editing else {
            // Suggest a random verify key for new clients.
            vkey = randomToken()
            return
        }
        remark = c.remark ?? ""
        vkey = c.verifyKey ?? ""
        compress = c.cnf?.compress ?? false
        crypt = c.cnf?.crypt ?? false
        configConnAllow = c.configConnAllow ?? false
        rateLimit = c.rateLimit.map { "\($0)" } ?? ""
        maxConn = c.maxConn.map { "\($0)" } ?? ""
        maxTunnel = c.maxTunnelNum.map { "\($0)" } ?? ""
        flowLimit = c.flow?.flowLimit.map { "\($0)" } ?? ""
        webUsername = c.webUserName ?? ""
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        var params: [String: String] = [:]
        params["remark"] = remark
        params["vkey"] = vkey
        params["compress"] = compress ? "true" : "false"
        params["crypt"] = crypt ? "true" : "false"
        params["config_conn_allow"] = configConnAllow ? "true" : "false"
        params["rate_limit"] = rateLimit.isEmpty ? "0" : rateLimit
        params["max_conn"] = maxConn.isEmpty ? "0" : maxConn
        params["max_tunnel"] = maxTunnel.isEmpty ? "0" : maxTunnel
        params["flow_limit"] = flowLimit.isEmpty ? "0" : flowLimit
        params["web_username"] = webUsername
        params["web_password"] = webPassword

        let ok: Bool
        if let c = editing {
            ok = await client.editClient(id: c.id, params: params)
        } else {
            ok = await client.addClient(params: params)
        }
        if ok { dismiss() }
        else { loadError = client.errorMessage ?? "保存失败" }
    }

    private func randomToken() -> String {
        let chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<16).map { _ in chars.randomElement()! })
    }
}
