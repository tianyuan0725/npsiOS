import SwiftUI

struct HostFormView: View {
    @EnvironmentObject var client: NPSClient
    @Environment(\.dismiss) private var dismiss

    let editing: Host?

    @State private var remark: String = ""
    @State private var host: String = ""
    @State private var location: String = ""
    @State private var scheme: String = "all"
    @State private var target: String = ""
    @State private var headerChange: String = ""
    @State private var hostChange: String = ""
    @State private var clientId: Int = 0
    @State private var localProxy: Bool = false
    @State private var keyFilePath: String = ""
    @State private var certFilePath: String = ""

    @State private var clients: [Client] = []
    @State private var isSaving: Bool = false
    @State private var loadError: String?

    init(host: Host?) {
        self.editing = host
    }

    var body: some View {
        Form {
            Section("域名") {
                LabeledField(title: "域名 (Host)", text: $host, placeholder: "例如 a.test.com", keyboard: .URL)
                LabeledField(title: "URL 路径 (Location, 可选)", text: $location, placeholder: "例如 /api", keyboard: .URL)
                Picker("协议", selection: $scheme) {
                    Text("全部 (all)").tag("all")
                    Text("HTTP").tag("http")
                    Text("HTTPS").tag("https")
                }
                LabeledField(title: "备注", text: $remark, placeholder: "备注")
            }
            Section("目标") {
                LabeledField(title: "内网目标地址", text: $target,
                             placeholder: "例如 127.0.0.1:8080", keyboard: .URL)
                Toggle("本地代理模式", isOn: $localProxy)
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
            Section("高级 (可选)") {
                LabeledField(title: "Header 修改", text: $headerChange, placeholder: "留空")
                LabeledField(title: "Host 修改", text: $hostChange, placeholder: "留空")
                LabeledField(title: "证书文件 (HTTPS)", text: $certFilePath, placeholder: "留空")
                LabeledField(title: "密钥文件 (HTTPS)", text: $keyFilePath, placeholder: "留空")
            }
            if let e = loadError {
                Section { Text(e).foregroundColor(.red).font(.caption) }
            }
        }
        .navigationTitle(editing == nil ? "新增主机" : "编辑主机")
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
        clients = await client.getClients()
        guard let h = editing else { return }
        remark = h.remark ?? ""
        host = h.host ?? ""
        location = h.location ?? ""
        scheme = h.scheme ?? "all"
        target = h.target?.targetStr ?? ""
        headerChange = h.headerChange ?? ""
        hostChange = h.hostChange ?? ""
        clientId = h.client?.id ?? 0
        localProxy = h.target?.localProxy ?? false
        keyFilePath = h.keyFilePath ?? ""
        certFilePath = h.certFilePath ?? ""
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        guard clientId != 0 else {
            loadError = "请先选择归属客户端"
            return
        }
        guard !host.isEmpty else {
            loadError = "请填写域名 (Host)"
            return
        }

        var params: [String: String] = [:]
        params["host"] = host
        params["location"] = location
        params["scheme"] = scheme
        params["target"] = target
        params["header"] = headerChange
        params["hostchange"] = hostChange
        params["client_id"] = "\(clientId)"
        params["remark"] = remark
        params["local_proxy"] = localProxy ? "true" : "false"
        params["key_file_path"] = keyFilePath
        params["cert_file_path"] = certFilePath

        let ok: Bool
        if let h = editing {
            ok = await client.editHost(id: h.id, params: params)
        } else {
            ok = await client.addHost(params: params)
        }
        if ok { dismiss() }
        else { loadError = client.errorMessage ?? "保存失败" }
    }
}
