@preconcurrency import AVFoundation
import AppKit
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
    private var interruptedBySleep = false

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
        observeSleep()
    }

    func handleIncoming(_ message: VideoMessage, currentUser: PingUser?) async {
        guard let messageId = message.id,
              let uid = currentUser?.id,
              let nickname = currentUser?.nickname else { return }

        let decision = AutoFaceReplyPolicy.decide(
            AutoFaceReplyPolicy.Context(
                incomingIsAutoReply: message.isAutoReply,
                messageCreatedAt: message.createdAt,
                appStartedAt: appStartedAt,
                now: Date(),
                alreadyReplied: isRecording || repliedMessageIds.contains(messageId),
                isDisplayAsleep: Self.isDisplayAsleep,
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
        interruptedBySleep = false
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
        guard !abandonIfNotLive(message) else { return }

        do {
            let recorder = VideoRecorder(output: camera.movieOutput)
            let clipURL = try await recorder.recordClip(seconds: Self.clipDuration)
            defer { try? FileManager.default.removeItem(at: clipURL) }
            guard !abandonIfNotLive(message) else { return }

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

    /// 도착 순간의 결정은 녹화가 제때 끝난다고 가정한다. 잠 때문에 멈췄다 끝났으면 버린다.
    private func abandonIfNotLive(_ message: VideoMessage) -> Bool {
        guard let reason = AutoFaceReplyPolicy.recheck(
            messageCreatedAt: message.createdAt,
            now: Date(),
            interruptedBySleep: interruptedBySleep
        ) else { return false }
        log("auto_face_reply_skipped", messageId: message.id ?? "", detail: reason.rawValue)
        stopCameraIfIdle()
        return true
    }

    /// 캡처 세션은 잠들 때 멈췄다가 깨어나는 순간 이어서 찍는다. 잠들기 전에 끊어야
    /// 깨어난 뒤 카메라가 다시 켜지지 않는다.
    private func observeSleep() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.interruptForSleep() }
            }
        }
    }

    private func interruptForSleep() {
        guard isRecording else { return }
        interruptedBySleep = true
        // 녹화 도중 사용자가 연 거울이 같은 세션을 쓰면 끊지 않는다. 전송 직전 재검사에서 버려진다.
        guard !isMirrorUsingCamera() else { return }
        camera.movieOutput.stopRecording()
        camera.stop()
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

    /// 다크웨이크에서는 앱과 네트워크가 돌아 핑을 받지만 디스플레이는 꺼져 있다.
    private static var isDisplayAsleep: Bool {
        CGDisplayIsAsleep(CGMainDisplayID()) != 0
    }
}
