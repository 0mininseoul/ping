import SwiftUI

@main
struct PingApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState.shared

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}
