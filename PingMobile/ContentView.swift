import SwiftUI
import PingKit

struct ContentView: View {
    @ObservedObject private var environment = AppEnvironment.shared
    @State private var path: [PingRoute] = []
    @State private var showScanner = false
    @State private var pairError: String?

    var body: some View {
        if let paired = environment.paired {
            NavigationStack(path: $path) {
                InboxView(account: paired)
                    .navigationDestination(for: PingRoute.self) { route in
                        switch route {
                        case .thread(let roomId):
                            ThreadView(account: paired, roomId: roomId)
                        }
                    }
            }
            .task { await PushRegistrar.shared.requestAuthorizationAndRegister() }
            .onAppear { consumePendingRoute() }
            .onChange(of: environment.pendingRoute) { _, _ in consumePendingRoute() }
        } else {
            unpairedView
        }
    }

    /// When a notification tap set a route, push it (replacing the stack so a
    /// second tap doesn't pile screens up).
    private func consumePendingRoute() {
        guard let route = environment.pendingRoute else { return }
        path = [route]
        environment.pendingRoute = nil
    }

    // MARK: - Not connected

    private var unpairedView: some View {
        DesktopInstallGuideView(
            onScanQR: {
                pairError = nil
                showScanner = true
            }
        )
        .overlay(alignment: .bottom) {
            if let pairError {
                Text(pairError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.bottom, 18)
            }
        }
        .sheet(isPresented: $showScanner) {
            QRScannerView { code in
                showScanner = false
                handleScanned(code)
            }
            .ignoresSafeArea()
            .presentationDragIndicator(.visible)
        }
    }

    private func handleScanned(_ code: String) {
        guard let data = code.data(using: .utf8),
              let payload = try? PingHandoffPayload.decode(data) else {
            pairError = "QR을 읽지 못했어요. 다시 시도해 주세요."
            return
        }
        let account = PairedAccount(url: payload.url, anonKey: payload.anonKey, session: payload.session)
        environment.setPaired(account)
        Task { await PushRegistrar.shared.requestAuthorizationAndRegister() }
    }
}
