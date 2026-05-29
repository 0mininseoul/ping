import SwiftUI
import PingKit

struct ContentView: View {
    @ObservedObject private var environment = AppEnvironment.shared
    @State private var showScanner = false
    @State private var pairError: String?

    var body: some View {
        if let paired = environment.paired {
            pairedView(paired)
        } else {
            unpairedView
        }
    }

    // MARK: - Connected

    private func pairedView(_ paired: PairedAccount) -> some View {
        VStack(spacing: 22) {
            Spacer(minLength: 8)

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.green)

            VStack(spacing: 6) {
                Text("연결됐어요")
                    .font(.title2.bold())
                Text("설정이 모두 끝났습니다.\n이 앱은 닫아두셔도 괜찮아요.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 18) {
                howItWorksRow(
                    icon: "bell.badge.fill",
                    title: "알림으로 도착해요",
                    detail: "상대가 보낸 ping이 이 iPhone과 Apple Watch에 알림으로 와요."
                )
                howItWorksRow(
                    icon: "play.circle.fill",
                    title: "탭하면 바로 재생",
                    detail: "알림을 누르면 3초 영상을 바로 볼 수 있어요."
                )
                howItWorksRow(
                    icon: "mic.fill",
                    title: "음성으로 답장",
                    detail: "받아쓰기로 말하면 텍스트로 답장이 전송돼요."
                )
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )

            Text("이제 따로 할 일은 없어요. 알림이 오면 바로 확인하세요.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer(minLength: 8)

            Text("연결된 계정 \(paired.session.userId.prefix(8))…")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(24)
    }

    private func howItWorksRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(Color.accentColor)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.bold())
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
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
