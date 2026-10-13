import SwiftUI

struct ClientsView: View {
    @EnvironmentObject var client: NPSClient

    @State private var clients: [Client] = []
    @State private var searchText: String = ""
    @State private var isLoading: Bool = false

    var filtered: [Client] {
        if searchText.isEmpty { return clients }
        return clients.filter { ($0.remark ?? "").localizedCaseInsensitiveContains(searchText)
            || "\($0.id)".contains(searchText)
            || ($0.addr ?? "").localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if clients.isEmpty && !isLoading {
                    EmptyStateView(title: "暂无客户端", systemImage: "desktopcomputer",
                                  description: "点击右上角 + 添加一个客户端")
                } else {
                    List {
                        ForEach(filtered) { c in
                            NavigationLink(destination: ClientFormView(client: c)) {
                                ClientRow(client: c)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) { Task { await remove(c) } } label: {
                                    Label("删除", systemImage: "trash")
                                }
                                Button {
                                    Task { await toggle(c) }
                                } label: {
                                    Label(c.status == true ? "停用" : "启用", systemImage: "power")
                                }
                                .tint(.orange)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("客户端")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: ClientFormView(client: nil)) {
                        Image(systemName: "plus")
                    }
                }
            }
            .searchable(text: $searchText, prompt: "搜索备注/IP")
            .refreshable {
                // Unstructured task: SwiftUI may cancel the refreshable task's
                // context mid-flight; a cancelled request used to wipe the list.
                await Task { @MainActor in await load() }.value
            }
            .overlay { if isLoading && clients.isEmpty { LoadingView() } }
            .task { await load() }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        // nil = fetch failed: keep the current rows instead of blanking out.
        if let v = await client.getClients() { clients = v }
    }

    private func remove(_ c: Client) async {
        let ok = await client.deleteClient(id: c.id)
        if ok { clients.removeAll { $0.id == c.id } }
    }

    private func toggle(_ c: Client) async {
        let newStatus = !(c.status == true)
        let ok = await client.changeClientStatus(id: c.id, status: newStatus)
        if ok {
            if let idx = clients.firstIndex(where: { $0.id == c.id }) {
                var copy = clients[idx]
                copy.status = newStatus
                clients[idx] = copy
            }
        }
    }
}

struct ClientRow: View {
    let client: Client
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(client.displayName)
                    .font(.headline)
                Spacer()
                StatusBadge(client.isConnect == true, on: "已连接", off: "未连接")
            }
            HStack(spacing: 12) {
                Text("ID: \(client.id)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if let v = client.verifyKey, !v.isEmpty {
                    Text("密钥: \(v)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            HStack(spacing: 12) {
                if let addr = client.addr, !addr.isEmpty {
                    Label(addr, systemImage: "network")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                if let ver = client.version, !ver.isEmpty {
                    Text("v\(ver)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text("↑\(formatBytes(client.flow?.inletFlow ?? 0)) ↓\(formatBytes(client.flow?.exportFlow ?? 0))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
