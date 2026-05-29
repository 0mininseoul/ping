import SwiftUI
import PingKit

struct ContentView: View {
    @ObservedObject private var environment = AppEnvironment.shared
    @State private var showScanner = false
    @State private var pairError: String?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: environment.paired == nil ? "iphone.slash" : "checkmark.seal.fill")
                .font(.system(size: 52))
                .foregroundStyle(environment.paired == nil ? Color.secondary : Color.green)

            Text(environment.paired == nil ? "데스크톱과 연결되지 않음" : "연결됨")
                .font(.headline)

            if let paired = environment.paired {
                Text("계정 \(paired.session.userId.prefix(8))…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("Mac의 Ping 설정 → 기기 탭의 QR 코드를 스캔하세요.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button {
                    pairError = nil
                    showScanner = true
                } label: {
                    Label("Mac QR 스캔", systemImage: "qrcode.viewfinder")
                }
                .buttonStyle(.borderedProminent)
            }

            if let pairError {
                Text(pairError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(32)
        .sheet(isPresented: $showScanner) {
            QRScannerView { code in
                showScanner = false
                handleScanned(code)
            }
            .ignoresSafeArea()
        }
        .task { await PushRegistrar.shared.registerIfPossible() }
    }

    private func handleScanned(_ code: String) {
        guard let data = code.data(using: .utf8),
              let payload = try? PingHandoffPayload.decode(data) else {
            pairError = "QR을 읽지 못했습니다. 다시 시도하세요."
            return
        }
        let account = PairedAccount(url: payload.url, anonKey: payload.anonKey, session: payload.session)
        environment.setPaired(account)
        Task { await PushRegistrar.shared.registerIfPossible() }
    }
}
