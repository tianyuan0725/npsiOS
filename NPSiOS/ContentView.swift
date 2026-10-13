import SwiftUI

struct RootView: View {
    @EnvironmentObject var client: NPSClient

    var body: some View {
        if client.isLoggedIn {
            MainTabView()
        } else {
            LoginView()
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject var client: NPSClient

    var body: some View {
        TabView(selection: $client.selectedTab) {
            DashboardView()
                .tabItem { Label("仪表盘", systemImage: "gauge.medium") }
                .tag(0)
            ClientsView()
                .tabItem { Label("客户端", systemImage: "desktopcomputer") }
                .tag(1)
            TunnelsView()
                .tabItem { Label("隧道", systemImage: "point.topleft.down.curvedto.point.bottomright.up") }
                .tag(2)
            HostsView()
                .tabItem { Label("主机", systemImage: "globe") }
                .tag(3)
            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
                .tag(4)
        }
        .accentColor(.blue)
        // Rebuild all tabs whenever the session changes (login or account
        // switch) so every list/dashboard reloads with the current server.
        .id(client.sessionEpoch)
        .alert("提示", isPresented: Binding(
            get: { client.errorMessage != nil && !client.sessionExpired },
            set: { if !$0 { client.errorMessage = nil } }
        )) {
            Button("确定") { client.errorMessage = nil }
        } message: {
            Text(client.errorMessage ?? "")
        }
    }
}
