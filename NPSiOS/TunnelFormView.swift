import SwiftUI

struct TunnelFormView: View {
    @EnvironmentObject var client: NPSClient
    @Environment(\.dismiss) private var dismiss

    let editing: Tunnel?

    @State private var remark: String = ""
    @State private var mode: String = "tcp"
    @State private var port: String = ""
    @State private var serverIp: String = ""
    @State private var target: String = ""
    @State private var clientId: Int = 0
    @State private var password: String = ""
    @State private var localProxy: Bool = false
    @State private var localPath: String = ""
    @State private var stripPre: String = ""

    @State private var clients: [Client] = []
    @State private var isSaving: Bool = false
    @State private var loadError: String?

    init(tunnel: Tunnel?) {
        self.editing = tunnel
    }

    var body: some View {
        Form {
            Section("类型与端口") {
                Picker("模式", selection: $mode) {
                    ForEach(Tunnel.modes, id: \.self) { m in
                        Text(Tunnel.modeLabelStatic(m)).tag(m)
                    }
                }
                LabeledField(title: "服务端端口", text: $port, placeholder: "例如 9001", keyboard: .numberPad)
                LabeledField(title: "服务端 IP (可选)", text: $serverIp, placeholder: "留空=默认", keyboard: .decimalPad)
            }
            Section("目标") {
                LabeledField(title: "内网目标地址", text: $target,
                             placeholder: "例如 127.0.0.1:80", keyboard: .URL)
                Toggle("本地代理模式", isOn: $localProxy)
                if mode == "httpProxy" || mode == "secret" {
                    SecureField("访问密码 (可选)", text: $password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            Section("归属客户端") {
                if clients.isEmpty {
                    Text("加载客户端列表中…").foregroundColor(.secondary).font(.caption)
                } else {
                    Picker("客户端", selection: $clientId) {
                        Text("请选择").tag(0)
                        ForEach(clients) { c in
                            Text(c.displayName).tag(c.id)
                        }
                    }
                }
            }
            Section("其他 (可选)") {
                LabeledField(title: "备注", text: $remark, placeholder: "备注")
                if mode == "httpProxy" {
                    LabeledField(title: "本地路径 (LocalPath)", text: $localPath, placeholder: "留空")
                    LabeledField(title: "去除前缀 (StripPre)", text: $stripPre, placeholder: "留空")
                }
            }
            if let e = loadError {
                Section { Text(e).foregroundColor(.red).font(.caption) }
            }
        }
        .navigationTitle(editing == nil ? "新增隧道" : "编辑隧道")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(editing == nil ? "创建" : "保存") { Task { await save() } }
                    .disabled(isSaving || (editing == nil && clientId == 0))
            }
        }
        .overlay { if isSaving { LoadingView() } }
        .task { await prepare() }
    }

    private func prepare() async {
        clients = await client.getClients() ?? []
        guard let t = editing else { return }
        remark = t.remark ?? ""
        mode = t.mode ?? "tcp"
        port = t.port.map { "\($0)" } ?? ""
        serverIp = t.serverIp ?? ""
        target = t.target?.targetStr ?? t.targetAddr ?? ""
        clientId = t.client?.id ?? 0
        password = t.password ?? ""
        localProxy = t.target?.localProxy ?? false
        localPath = t.localPath ?? ""
        stripPre = t.stripPre ?? ""
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        guard clientId != 0 else {
            loadError = "请先选择归属客户端"
            return
        }

        var params: [String: String] = [:]
        params["type"] = mode
        params["port"] = port
        params["server_ip"] = serverIp
        params["target"] = target
        params["client_id"] = "\(clientId)"
        params["remark"] = remark
        params["password"] = password
        params["local_proxy"] = localProxy ? "true" : "false"
        params["local_path"] = localPath
        params["strip_pre"] = stripPre

        let ok: Bool
        if let t = editing {
            ok = await client.editTunnel(id: t.id, params: params)
        } else {
            ok = await client.addTunnel(params: params)
        }
        if ok { dismiss() }
        else { loadError = client.errorMessage ?? "保存失败" }
    }
}
