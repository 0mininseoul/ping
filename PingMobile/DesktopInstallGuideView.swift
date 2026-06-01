import PingKit
import SwiftUI
import UIKit

struct DesktopInstallGuideView: View {
    let onScanQR: () -> Void
    let onPreview: () -> Void

    @State private var copied = false
    @State private var copyResetTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 12)

                Image(systemName: "macbook.and.iphone")
                    .font(.system(size: 58, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text("Ping은 Mac용 Ping의 iPhone companion입니다")
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)

                    Text("Mac에서 3초 영상을 보내고, iPhone과 Apple Watch에서 바로 보고 답장해요. 먼저 Mac에 Ping을 설치한 뒤 QR로 연결하세요.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 12) {
                    setupStep(number: "1", title: "Mac에서 설치 페이지 열기", detail: PingProductLinks.desktopInstallPageText)
                    setupStep(number: "2", title: "Ping 설치 후 기기 QR 표시", detail: "Mac Ping > 설정 > 기기")
                    setupStep(number: "3", title: "이 iPhone으로 QR 스캔", detail: "같은 익명 계정으로 연결됩니다")
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemBackground))
                )

                VStack(spacing: 10) {
                    Button(action: copyInstallURL) {
                        Label(copied ? "복사됐어요" : "Mac 설치 링크 복사", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) {
                            shareButton
                            safariLink
                        }

                        VStack(spacing: 10) {
                            shareButton
                            safariLink
                        }
                    }

                    Button(action: onScanQR) {
                        Label("설치 끝났어요, QR 스캔", systemImage: "qrcode.viewfinder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }

                Button("앱 기능 미리보기", action: onPreview)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
            }
            .padding(24)
        }
        .background(Color(uiColor: .systemBackground))
        .onDisappear {
            copyResetTask?.cancel()
            copyResetTask = nil
        }
    }

    private var shareButton: some View {
        ShareLink(item: PingProductLinks.desktopInstallPage) {
            Label("Mac으로 공유", systemImage: "square.and.arrow.up")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    private var safariLink: some View {
        Link(destination: PingProductLinks.desktopInstallPage) {
            Label("Safari에서 보기", systemImage: "safari")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    private func setupStep(number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.accentColor))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
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
