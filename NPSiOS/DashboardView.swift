import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var client: NPSClient

    @State private var clients: [Client] = []
    @State private var tunnels: [Tunnel] = []
    @State private var hosts: [Host] = []
    @State private var isLoading: Bool = false

    var onlineCount: Int { clients.filter { $0.isConnect == true }.count }
    var inlet: Int64 { clients.reduce(0) { $0 + ($1.flow?.inletFlow ?? 0) } }
    var export: Int64 { clients.reduce(0) { $0 + ($1.flow?.exportFlow ?? 0) } }

    var tunnelCounts: [String: Int] {
        var dict: [String: Int] = [:]
        for t in tunnels { dict[t.mode ?? "其他", default: 0] += 1 }
        return dict
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if isLoading && clients.isEmpty {
                    LoadingView()
                        .frame(height: 300)
                } else {
                    LazyVStack(spacing: 16) {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            StatCard(title: "客户端总数", value: "\(clients.count)", icon: "desktopcomputer", accent: .blue)
                            StatCard(title: "在线客户端", value: "\(onlineCount)", icon: "wifi", accent: .green)
                            StatCard(title: "隧道总数", value: "\(tunnels.count)", icon: "point.topleft.down.curvedto.point.bottomright.up", accent: .orange)
                            StatCard(title: "主机(域名)数", value: "\(hosts.count)", icon: "globe", accent: .purple)
                            StatCard(title: "入站流量", value: formatBytes(inlet), icon: "arrow.down.circle", accent: .teal)
                            StatCard(title: "出站流量", value: formatBytes(export), icon: "arrow.up.circle", accent: .indigo)
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("隧道类型分布")
                                .font(.headline)
                            if tunnelCounts.isEmpty {
                                Text("暂无隧道")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                ForEach(tunnelCounts.sorted(by: { $0.key < $1.key }), id: \.key) { key, val in
                                    HStack {
                                        Text(Tunnel.modeLabelStatic(key))
                                        Spacer()
                                        Text("\(val)")
                                            .fontWeight(.semibold)
                                    }
                                    .font(.subheadline)
                                }
                            }
                        }
                        .padding(14)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(14)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("客户端状态")
                                .font(.headline)
                            if clients.isEmpty {
                                Text("暂无客户端")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                ForEach(clients.prefix(8)) { c in
                                    HStack {
                                        Text(c.displayName)
                                        Spacer()
                                        StatusBadge(c.isConnect == true, on: "已连接", off: "未连接")
                                    }
                                    .font(.subheadline)
                                }
                                if clients.count > 8 {
                                    Text("… 等 \(clients.count) 个客户端")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(14)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(14)
                    }
                    .padding(16)
                }
            }
            .navigationTitle("仪表盘")
            .refreshable { await load() }
            .task { await load() }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        async let c = client.getClients()
        async let t = client.getTunnels()
        async let h = client.getHosts()
        clients = await c
        tunnels = await t
        hosts = await h
    }
}

extension Tunnel {
    static func modeLabelStatic(_ mode: String) -> String {
        switch mode {
        case "tcp": return "TCP"
        case "udp": return "UDP"
        case "socks5": return "Socks5"
        case "httpProxy": return "HTTP代理"
        case "secret": return "私密"
        case "p2p": return "P2P"
        default: return mode
        }
    }
}
