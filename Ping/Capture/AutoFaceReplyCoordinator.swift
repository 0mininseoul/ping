@preconcurrency import AVFoundation
import Foundation

/// 실시간으로 받은 핑에 얼굴 3초를 녹화해 보낸 사람에게 되돌려 보낸다.
///
/// 판단은 `AutoFaceReplyPolicy`가, 실행만 여기서 한다. 스킵이든 실패든 사유를 그대로
/// 남기는 이유: "자동 회신이 안 왔다"를 로그 읽기 전에 추론으로 답하면 틀린다.
@MainActor
final class AutoFaceReplyCoordinator {
    static let clipDuration: Double = 3.0

    private let camera: CameraManager
    private let messageService: MessageService
    private let appStartedAt: Date
    private let isMirrorUsingCamera: () -> Bool

    private var repliedMessageIds: Set<String> = []
    private var isRecording = false

    init(
        camera: CameraManager,
        messageService: MessageService,
        appStartedAt: Date,
        isMirrorUsingCamera: @escaping () -> Bool
    ) {
        self.camera = camera
        self.messageService = messageService
        self.appStartedAt = appStartedAt
        self.isMirrorUsingCamera = isMirrorUsingCamera
    }

    func handleIncoming(_ message: VideoMessage, currentUser: PingUser?) async {
        guard let messageId = message.id,
              let uid = currentUser?.id,
              let nickname = currentUser?.nickname else { return }

        let decision = AutoFaceReplyPolicy.decide(
            AutoFaceReplyPolicy.Context(
                isEnabled: PingAutoFaceReplyPreference.isEnabled,
                incomingIsAutoReply: message.isAutoReply,
                messageCreatedAt: message.createdAt,
                appStartedAt: appStartedAt,
                now: Date(),
                alreadyReplied: isRecording || repliedMessageIds.contains(messageId),
                isCameraAuthorized: Self.isCameraAuthorized,
                isCameraBusy: isMirrorUsingCamera()
            )
        )

        switch decision {
        case .skip(let reason):
            log("auto_face_reply_skipped", messageId: messageId, detail: reason.rawValue)
        case .record:
            repliedMessageIds.insert(messageId)
            await recordAndSend(message, senderUid: uid, senderNickname: nickname)
        }
    }

    private func recordAndSend(_ message: VideoMessage, senderUid: String, senderNickname: String) async {
        let messageId = message.id ?? ""
        isRecording = true
        defer { isRecording = false }

        let indicator = AutoReplyIndicatorWindow(
            senderNickname: message.senderNickname,
            duration: Self.clipDuration
        )
        indicator.present()
        defer { indicator.dismiss() }

        await camera.startWithAudio()
        guard camera.isReady else {
            log("auto_face_reply_skipped", messageId: messageId, detail: "camera_not_ready")
            stopCameraIfIdle()
            return
        }

        do {
            let recorder = VideoRecorder(output: camera.movieOutput)
            let clipURL = try await recorder.recordClip(seconds: Self.clipDuration)
            defer { try? FileManager.default.removeItem(at: clipURL) }

            try await messageService.sendAutoReply(
                to: message,
                localVideoURL: clipURL,
                senderUid: senderUid,
                senderNickname: senderNickname
            )
            log("auto_face_reply_sent", messageId: messageId, detail: nil)
        } catch {
            NSLog("Auto face reply failed: \(error)")
            log("auto_face_reply_failed", messageId: messageId, detail: "\(error)")
        }

        stopCameraIfIdle()
    }

    /// 녹화 중에 사용자가 거울을 열었을 수 있다. 그때 세션을 끄면 사용자가 직접 찍던 핑이 깨진다.
    private func stopCameraIfIdle() {
        guard !isMirrorUsingCamera() else { return }
        camera.stop()
    }

    private func log(_ event: String, messageId: String, detail: String?) {
        var properties: [String: Any] = ["message_id": messageId]
        if let detail {
            properties["reason"] = detail
        }
        ClientEventService.shared.log(event, properties: properties)
    }

    private static var isCameraAuthorized: Bool {
        AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    }
}
