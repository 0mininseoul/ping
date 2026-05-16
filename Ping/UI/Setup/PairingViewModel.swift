import AVFoundation
import Combine
import Foundation
import UserNotifications

@MainActor
final class PairingViewModel: ObservableObject {
    enum Step: Int, CaseIterable {
        case welcome
        case permissions
        case nickname
        case firstRoom
        case done
    }

    @Published var step: Step = .welcome
    @Published var nickname = ""
    @Published var roomName = ""
    @Published private(set) var cameraGranted = false
    @Published private(set) var audioGranted = false
    @Published private(set) var notificationGranted = false
    @Published private(set) var isRequestingPermissions = false
    @Published var errorMessage: String?

    init() {
        refreshMediaPermissionState()
        Task { await refreshNotificationPermissionState() }
    }

    var trimmedNickname: String {
        nickname.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedRoomName: String {
        roomName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canProceedFromPermissions: Bool {
        cameraGranted && audioGranted && notificationGranted
    }

    var canProceedFromNickname: Bool {
        !trimmedNickname.isEmpty && trimmedNickname.count <= 24
    }

    var nicknameValidationMessage: String? {
        if trimmedNickname.isEmpty {
            return "닉네임을 입력하세요."
        }
        if trimmedNickname.count > 24 {
            return "닉네임은 24자 이하여야 합니다."
        }
        return nil
    }

    var completionPayload: (nickname: String, firstRoomName: String?)? {
        guard canProceedFromNickname else { return nil }
        return (trimmedNickname, trimmedRoomName.isEmpty ? nil : trimmedRoomName)
    }

    var progress: Double {
        Double(step.rawValue + 1) / Double(Step.allCases.count)
    }

    func next() {
        guard validateCurrentStep() else { return }
        guard let nextStep = Step(rawValue: step.rawValue + 1) else { return }
        errorMessage = nil
        step = nextStep
    }

    func back() {
        guard let previousStep = Step(rawValue: step.rawValue - 1) else { return }
        errorMessage = nil
        step = previousStep
    }

    func skipFirstRoom() {
        roomName = ""
        step = .done
    }

    func requestAllPermissions() async {
        isRequestingPermissions = true
        defer { isRequestingPermissions = false }

        cameraGranted = await requestMediaAccess(for: .video)
        audioGranted = await requestMediaAccess(for: .audio)
        notificationGranted = await LocalNotificationCenter.shared.requestAuthorization()

        if !canProceedFromPermissions {
            errorMessage = "카메라, 마이크, 알림 권한을 모두 허용해야 Ping을 사용할 수 있습니다."
        } else {
            errorMessage = nil
        }
    }

    func requestCamera() async {
        cameraGranted = await requestMediaAccess(for: .video)
        updatePermissionError()
    }

    func requestAudio() async {
        audioGranted = await requestMediaAccess(for: .audio)
        updatePermissionError()
    }

    func requestNotifications() async {
        notificationGranted = await LocalNotificationCenter.shared.requestAuthorization()
        updatePermissionError()
    }

    func validateCurrentStep() -> Bool {
        switch step {
        case .welcome, .firstRoom, .done:
            errorMessage = nil
            return true
        case .permissions:
            guard canProceedFromPermissions else {
                errorMessage = "카메라, 마이크, 알림 권한을 먼저 허용하세요."
                return false
            }
            errorMessage = nil
            return true
        case .nickname:
            guard canProceedFromNickname else {
                errorMessage = nicknameValidationMessage
                return false
            }
            errorMessage = nil
            return true
        }
    }

    private func refreshMediaPermissionState() {
        cameraGranted = authorizationGranted(for: .video)
        audioGranted = authorizationGranted(for: .audio)
    }

    private func refreshNotificationPermissionState() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationGranted = settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
    }

    private func requestMediaAccess(for mediaType: AVMediaType) async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: mediaType) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: mediaType)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private func authorizationGranted(for mediaType: AVMediaType) -> Bool {
        AVCaptureDevice.authorizationStatus(for: mediaType) == .authorized
    }

    private func updatePermissionError() {
        errorMessage = canProceedFromPermissions
            ? nil
            : "카메라, 마이크, 알림 권한을 모두 허용해야 합니다."
    }
}
