import SwiftUI

struct HostsView: View {
    @EnvironmentObject var client: NPSClient

    @State private var hosts: [Host] = []
    @State private var searchText: String = ""
    @State private var isLoading: Bool = false

    var filtered: [Host] {
        if searchText.isEmpty { return hosts }
        return hosts.filter {
            ($0.remark ?? "").localizedCaseInsensitiveContains(searchText)
            || ($0.host ?? "").localizedCaseInsensitiveContains(searchText)
            || ($0.targetString).localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if hosts.isEmpty && !isLoading {
                    EmptyStateView(title: "暂无主机", systemImage: "globe",
                                  description: "点击右上角 + 添加一条域名代理")
                } else {
                    List {
                        ForEach(filtered) { h in
                            NavigationLink(destination: HostFormView(host: h)) {
                                HostRow(host: h)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) { Task { await remove(h) } } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("主机")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: HostFormView(host: nil)) {
                        Image(systemName: "plus")
                    }
                }
            }
            .searchable(text: $searchText, prompt: "搜索域名/备注")
            .refreshable { await load() }
            .overlay { if isLoading && hosts.isEmpty { LoadingView() } }
            .task { await load() }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        hosts = await client.getHosts()
    }

    private func remove(_ h: Host) async {
        let ok = await client.deleteHost(id: h.id)
        if ok { hosts.removeAll { $0.id == h.id } }
    }
}

struct HostRow: View {
    let host: Host
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(host.displayName)
                    .font(.headline)
                Spacer()
                if let scheme = host.scheme, !scheme.isEmpty {
                    Text(scheme.uppercased())
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.purple.opacity(0.12))
                        .foregroundColor(.purple)
                        .clipShape(Capsule())
                }
            }
            if let h = host.host, !h.isEmpty {
                Text(h)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            HStack(spacing: 12) {
                Text("→ \(host.targetString)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                if let loc = host.location, !loc.isEmpty {
                    Text("路径: \(loc)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if let clientName = host.client?.displayName {
                    Text(clientName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
