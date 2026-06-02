import PingKit
import SwiftUI
import UIKit

struct DesktopInstallGuideView: View {
    let onScanQR: () -> Void

    @State private var copied = false
    @State private var copyResetTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Spacer(minLength: 20)

                Image(systemName: "macbook.and.iphone")
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text("Mac용 Ping과 연결하는 iPhone 앱이에요")
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)

                    Text("Mac에 Ping을 설치한 뒤, Mac 앱에서 QR 코드를 열고 스캔하세요.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                installPageRow

                VStack(spacing: 8) {
                    Button(action: onScanQR) {
                        Label("QR 스캔", systemImage: "qrcode.viewfinder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Text("Mac Ping > 설정 > 기기")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 16)
            }
            .padding(24)
        }
        .background(Color(uiColor: .systemBackground))
        .onDisappear {
            copyResetTask?.cancel()
            copyResetTask = nil
        }
    }

    private var installPageRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Mac 앱 설치 페이지")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Link(destination: PingProductLinks.desktopInstallPage) {
                    Text(PingProductLinks.desktopInstallPageText)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
            }

            Spacer(minLength: 8)

            Button(action: copyInstallURL) {
                installActionImage(copied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(copied ? "설치 주소 복사됨" : "설치 주소 복사")

            ShareLink(item: PingProductLinks.desktopInstallPage) {
                installActionImage("square.and.arrow.up")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("설치 주소 공유")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }

    private func installActionImage(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Color.accentColor)
            .frame(width: 40, height: 40)
            .background(
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
            )
    }

    private func copyInstallURL() {
        UIPasteboard.general.string = PingProductLinks.desktopInstallPage.absoluteString
        copied = true
        copyResetTask?.cancel()

        copyResetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled else { return }
            copied = false
            copyResetTask = nil
        }
    }
}
