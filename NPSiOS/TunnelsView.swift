import SwiftUI

struct TunnelsView: View {
    @EnvironmentObject var client: NPSClient

    @State private var tunnels: [Tunnel] = []
    @State private var searchText: String = ""
    @State private var isLoading: Bool = false

    var filtered: [Tunnel] {
        if searchText.isEmpty { return tunnels }
        return tunnels.filter {
            ($0.remark ?? "").localizedCaseInsensitiveContains(searchText)
            || ($0.targetString).localizedCaseInsensitiveContains(searchText)
            || "\($0.id)".contains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if tunnels.isEmpty && !isLoading {
                    EmptyStateView(title: "暂无隧道", systemImage: "point.topleft.down.curvedto.point.bottomright.up",
                                  description: "点击右上角 + 添加一条穿透隧道")
                } else {
                    List {
                        ForEach(filtered) { t in
                            NavigationLink(destination: TunnelFormView(tunnel: t)) {
                                TunnelRow(tunnel: t)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) { Task { await remove(t) } } label: {
                                    Label("删除", systemImage: "trash")
                                }
                                Button {
                                    Task { await toggleRun(t) }
                                } label: {
                                    Label(t.runStatus == true ? "停止" : "启动", systemImage: "playpause")
                                }
                                .tint(.orange)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("隧道")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: TunnelFormView(tunnel: nil)) {
                        Image(systemName: "plus")
                    }
                }
            }
            .searchable(text: $searchText, prompt: "搜索备注/目标")
            .refreshable { await load() }
            .overlay { if isLoading && tunnels.isEmpty { LoadingView() } }
            .task { await load() }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        tunnels = await client.getTunnels()
    }

    private func remove(_ t: Tunnel) async {
        let ok = await client.deleteTunnel(id: t.id)
        if ok { tunnels.removeAll { $0.id == t.id } }
    }

    private func toggleRun(_ t: Tunnel) async {
        let ok = t.runStatus == true
            ? await client.stopTunnel(id: t.id)
            : await client.startTunnel(id: t.id)
        if ok {
            if let idx = tunnels.firstIndex(where: { $0.id == t.id }) {
                var copy = tunnels[idx]
                copy.runStatus = !(t.runStatus == true)
                tunnels[idx] = copy
            }
        }
    }
}

struct TunnelRow: View {
    let tunnel: Tunnel
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(tunnel.displayName)
                    .font(.headline)
                Spacer()
                Text(tunnel.modeLabel)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.blue.opacity(0.12))
                    .foregroundColor(.blue)
                    .clipShape(Capsule())
            }
            HStack(spacing: 12) {
                if let port = tunnel.port {
                    Label("\(port)", systemImage: "number")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Text(tunnel.targetString)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            HStack(spacing: 12) {
                StatusBadge(tunnel.status == true, on: "启用", off: "停用")
                StatusBadge(tunnel.runStatus == true, on: "运行中", off: "已停止")
                Spacer()
                if let clientName = tunnel.client?.displayName {
                    Text(clientName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
