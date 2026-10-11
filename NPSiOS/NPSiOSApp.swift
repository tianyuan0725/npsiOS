import SwiftUI

@main
struct NPSiOSApp: App {
    @StateObject private var client = NPSClient.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(client)
                .preferredColorScheme(.light)
        }
    }
}
