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
            .task { await PushRegistrar.shared.registerIfPossible() }
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
        VStack(spacing: 18) {
            Spacer()

            Image(systemName: "qrcode.viewfinder")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                Text("Mac과 연결하기")
                    .font(.title2.bold())
                Text("Mac의 Ping에서 설정 → 기기 탭을 열면\nQR 코드가 나와요. 그걸 스캔하세요.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                pairError = nil
                showScanner = true
            } label: {
                Label("Mac QR 스캔", systemImage: "qrcode.viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 32)

            if let pairError {
                Text(pairError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            Button("앱 기능 미리보기") { loadDemo() }
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 8)
        }
        .padding(24)
        .sheet(isPresented: $showScanner) {
            QRScannerView { code in
                showScanner = false
                handleScanned(code)
            }
            .ignoresSafeArea()
        }
        .task { await PushRegistrar.shared.registerIfPossible() }
    }

    /// Loads a pre-seeded demo account so App Store reviewers can explore the
    /// companion UI without needing a paired Mac.
    private func loadDemo() {
        guard let url = URL(string: "https://qxjtprxvjmaxlbtljcjw.supabase.co") else { return }
        let session = SupabaseSession(
            accessToken: "",
            refreshToken: "4ba67vbxrxzo",
            expiresAt: Date(timeIntervalSince1970: 0),
            userId: "c91fbdbd-ab5c-461e-a74d-e66b99d0d651"
        )
        let account = PairedAccount(
            url: url,
            anonKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InF4anRwcnh2am1heGxidGxqY2p3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzg5MzcxNjQsImV4cCI6MjA5NDUxMzE2NH0.z3mxwdHQrII5CeI0UFlnBKqkWP0jfXbB3iyjBVJ97vI",
            session: session
        )
        environment.setPaired(account)
    }

    private func handleScanned(_ code: String) {
        guard let data = code.data(using: .utf8),
              let payload = try? PingHandoffPayload.decode(data) else {
            pairError = "QR을 읽지 못했어요. 다시 시도해 주세요."
            return
        }
        let account = PairedAccount(url: payload.url, anonKey: payload.anonKey, session: payload.session)
        environment.setPaired(account)
        Task { await PushRegistrar.shared.registerIfPossible() }
    }
}
