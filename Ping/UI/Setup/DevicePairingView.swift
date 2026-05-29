import AppKit
import CoreImage.CIFilterBuiltins
import SwiftUI

/// Settings tab that shows a QR encoding the current session so an iPhone/Apple
/// Watch can adopt this desktop's identity (P4 handoff).
struct DevicePairingView: View {
    @State private var qrImage: NSImage?
    @State private var errorText: String?

    var body: some View {
        SettingsPaneShim {
            VStack(spacing: 14) {
                Text("iPhone · Apple Watch 추가")
                    .font(PingFont.title)

                Text("iPhone의 Ping 앱에서 이 QR을 스캔하면 같은 계정으로 연결됩니다.")
                    .font(PingFont.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Group {
                    if let qrImage {
                        Image(nsImage: qrImage)
                            .interpolation(.none)
                            .resizable()
                            .frame(width: 220, height: 220)
                    } else if let errorText {
                        Text(errorText)
                            .font(PingFont.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    } else {
                        ProgressView()
                    }
                }
                .frame(width: 220, height: 220)

                Text("이 QR에는 로그인 세션이 들어 있습니다. 타인에게 보이지 마세요.")
                    .font(PingFont.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task { await generate() }
    }

    private func generate() async {
        do {
            let data = try await SupabaseClient.shared.exportDeviceHandoff()
            if let image = Self.makeQR(from: data) {
                qrImage = image
            } else {
                errorText = "QR 생성에 실패했습니다."
            }
        } catch {
            errorText = "세션을 준비하지 못했습니다. 로그인 상태를 확인하세요."
        }
    }

    private static func makeQR(from data: Data) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = "L"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let rep = NSCIImageRep(ciImage: scaled)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
}

/// Minimal local pane wrapper (the shared `SettingsPane` in SettingsScene is
/// private to that file).
private struct SettingsPaneShim<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .font(PingFont.body)
            .padding(22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}
