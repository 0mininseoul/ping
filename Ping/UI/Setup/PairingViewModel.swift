import AppKit
import AVFoundation
import Combine
import Foundation
import UserNotifications

enum SetupPermissionState: Equatable {
    case granted
    case notDetermined
    case denied
    case restricted

    var isGranted: Bool {
        self == .granted
    }

    var needsSystemSettings: Bool {
        self == .denied || self == .restricted
    }
}

enum SetupPermissionKind: String, CaseIterable {
    case camera
    case audio
    case notifications
    case screenRecording

    var displayName: String {
        switch self {
        case .camera:
            return "카메라"
        case .audio:
            return "마이크"
        case .notifications:
            return "알림"
        case .screenRecording:
            return "화면 녹화"
        }
    }

    var settingsURL: URL? {
        let urlString: String
        switch self {
        case .camera:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"
        case .audio:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        case .notifications:
            urlString = "x-apple.systempreferences:com.apple.preference.notifications"
        case .screenRecording:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        }
        return URL(string: urlString)
    }
}

struct PermissionNotice: Equatable {
    let title: String
    let message: String
}

enum PermissionGuidance {
    static func notice(
        camera: SetupPermissionState,
        audio: SetupPermissionState,
        notifications: SetupPermissionState,
        screenRecording: SetupPermissionState = .notDetermined
    ) -> PermissionNotice? {
        let blockedKinds = [
            (SetupPermissionKind.camera, camera),
            (.audio, audio),
            (.notifications, notifications),
            (.screenRecording, screenRecording)
        ]
        .filter { $0.1.needsSystemSettings }
        .map(\.0.displayName)

        guard !blockedKinds.isEmpty else { return nil }

        return PermissionNotice(
            title: "시스템 설정에서 켜야 합니다",
            message: "\(blockedKinds.joined(separator: ", ")) 권한이 macOS에서 꺼져 있습니다. 시스템 설정에서 Ping 스위치를 켠 뒤 이 창으로 돌아오세요."
        )
    }
}

enum OnboardingStartAction: Equatable {
    case createRoom(name: String)
    case joinRoom(Room)
    case later
}

struct OnboardingCompletion: Equatable {
    let nickname: String
    let action: OnboardingStartAction
}

@MainActor
final class PairingViewModel: ObservableObject {
    enum Step: Int, CaseIterable {
        case welcome
        case permissions
        case nickname
        case connectionChoice
        case createRoom
        case joinRoom
        case done
    }

    @Published var step: Step = .welcome
    @Published var nickname = ""
    @Published var roomName = ""
    @Published var selectedJoinRoom: Room?
    @Published private(set) var startAction: OnboardingStartAction?
    @Published private(set) var cameraPermission: SetupPermissionState = .notDetermined
    @Published private(set) var audioPermission: SetupPermissionState = .notDetermined
    @Published private(set) var notificationPermission: SetupPermissionState = .notDetermined
    @Published private(set) var screenRecordingPermission: SetupPermissionState = .notDetermined
    @Published private(set) var isRequestingPermissions = false
    @Published var isCompleting = false
    @Published var errorMessage: String?

    init() {
        refreshMediaPermissionState()
        Task { await refreshNotificationPermissionState() }
        Task { await refreshScreenRecordingPermission() }
    }

    var cameraGranted: Bool {
        cameraPermission.isGranted
    }

    var audioGranted: Bool {
        audioPermission.isGranted
    }

    var notificationGranted: Bool {
        notificationPermission.isGranted
    }

    var screenRecordingGranted: Bool {
        screenRecordingPermission.isGranted
    }

    var trimmedNickname: String {
        nickname.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedRoomName: String {
        roomName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canProceedFromPermissions: Bool {
        cameraGranted && audioGranted && notificationGranted && screenRecordingGranted
    }

    var permissionNotice: PermissionNotice? {
        PermissionGuidance.notice(
            camera: cameraPermission,
            audio: audioPermission,
            notifications: notificationPermission,
            screenRecording: screenRecordingPermission
        )
    }

    var canProceedFromNickname: Bool {
        !trimmedNickname.isEmpty && trimmedNickname.count <= 24
    }

    var canProceedFromCreateRoom: Bool {
        !trimmedRoomName.isEmpty
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

    var roomNameValidationMessage: String? {
        if trimmedRoomName.isEmpty {
            return "룸 이름을 입력하세요."
        }
        return nil
    }

    var completionPayload: OnboardingCompletion? {
        guard canProceedFromNickname, let startAction else { return nil }
        return OnboardingCompletion(nickname: trimmedNickname, action: startAction)
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
        errorMessage = nil
        switch step {
        case .welcome:
            return
        case .permissions:
            step = .welcome
        case .nickname:
            step = .permissions
        case .connectionChoice:
            step = .nickname
        case .createRoom, .joinRoom:
            step = .connectionChoice
        case .done:
            switch startAction {
            case .createRoom:
                step = .createRoom
            case .joinRoom:
                step = .joinRoom
            case .later, nil:
                step = .connectionChoice
            }
        }
    }

    func chooseCreateRoom() {
        errorMessage = nil
        roomName = ""
        startAction = nil
        step = .createRoom
    }

    func chooseJoinRoom() {
        errorMessage = nil
        selectedJoinRoom = nil
        startAction = nil
        step = .joinRoom
    }

    func deferRoomSetup() {
        errorMessage = nil
        startAction = .later
        step = .done
    }

    func completeCreateRoom() {
        guard canProceedFromCreateRoom else {
            errorMessage = roomNameValidationMessage
            return
        }

        errorMessage = nil
        startAction = .createRoom(name: trimmedRoomName)
        step = .done
    }

    func selectRoomForJoin(_ room: Room) {
        selectedJoinRoom = room
        startAction = .joinRoom(room)
        errorMessage = nil
        step = .done
    }

    func requestAllPermissions() async {
        isRequestingPermissions = true
        defer { isRequestingPermissions = false }

        cameraPermission = await requestMediaAccess(for: .video)
        audioPermission = await requestMediaAccess(for: .audio)
        notificationPermission = await requestNotificationAccess()

        errorMessage = nil
    }

    func requestCamera() async {
        cameraPermission = await requestMediaAccess(for: .video)
        errorMessage = nil
    }

    func requestAudio() async {
        audioPermission = await requestMediaAccess(for: .audio)
        errorMessage = nil
    }

    func requestNotifications() async {
        notificationPermission = await requestNotificationAccess()
        errorMessage = nil
    }

    func requestScreenRecording() {
        // Screen recording permission cannot be requested programmatically;
        // guide the user to system settings.
        openSystemPermissionSettings(for: .screenRecording)
    }

    func refreshPermissionStates() async {
        refreshMediaPermissionState()
        await refreshNotificationPermissionState()
        await refreshScreenRecordingPermission()
        if canProceedFromPermissions || permissionNotice != nil {
            errorMessage = nil
        }
    }

    func refreshScreenRecordingPermission() async {
        let status = await ScreenCapturePermission.currentStatus()
        switch status {
        case .authorized:
            screenRecordingPermission = .granted
        case .denied:
            screenRecordingPermission = .denied
        case .unknown:
            screenRecordingPermission = .notDetermined
        }
    }

    func openSystemPermissionSettings(for kind: SetupPermissionKind? = nil) {
        let target = kind ?? firstBlockedPermissionKind() ?? .camera
        guard let url = target.settingsURL else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func validateCurrentStep() -> Bool {
        guard !isCompleting else { return false }

        switch step {
        case .welcome, .connectionChoice, .joinRoom, .done:
            errorMessage = nil
            return true
        case .permissions:
            guard canProceedFromPermissions else {
                errorMessage = permissionNotice == nil
                    ? "남은 권한을 허용하면 다음으로 넘어갈 수 있습니다."
                    : nil
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
        case .createRoom:
            guard canProceedFromCreateRoom else {
                errorMessage = roomNameValidationMessage
                return false
            }
            errorMessage = nil
            return true
        }
    }

    private func refreshMediaPermissionState() {
        cameraPermission = permissionState(for: AVCaptureDevice.authorizationStatus(for: .video))
        audioPermission = permissionState(for: AVCaptureDevice.authorizationStatus(for: .audio))
    }

    private func firstBlockedPermissionKind() -> SetupPermissionKind? {
        if cameraPermission.needsSystemSettings {
            return .camera
        }
        if audioPermission.needsSystemSettings {
            return .audio
        }
        if notificationPermission.needsSystemSettings {
            return .notifications
        }
        if screenRecordingPermission.needsSystemSettings {
            return .screenRecording
        }
        return nil
    }

    private func refreshNotificationPermissionState() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationPermission = permissionState(for: settings.authorizationStatus)
    }

    private func requestMediaAccess(for mediaType: AVMediaType) async -> SetupPermissionState {
        switch AVCaptureDevice.authorizationStatus(for: mediaType) {
        case .authorized:
            return .granted
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: mediaType)
            if granted {
                return .granted
            }
            return permissionState(for: AVCaptureDevice.authorizationStatus(for: mediaType))
        case .denied, .restricted:
            return permissionState(for: AVCaptureDevice.authorizationStatus(for: mediaType))
        @unknown default:
            return .restricted
        }
    }

    private func requestNotificationAccess() async -> SetupPermissionState {
        let current = await UNUserNotificationCenter.current().notificationSettings()
        switch current.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return .granted
        case .notDetermined:
            _ = await LocalNotificationCenter.shared.requestAuthorization()
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            return permissionState(for: settings.authorizationStatus)
        case .denied:
            return .denied
        @unknown default:
            return .restricted
        }
    }

    private func permissionState(for status: AVAuthorizationStatus) -> SetupPermissionState {
        switch status {
        case .authorized:
            return .granted
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .restricted
        }
    }

    private func permissionState(for status: UNAuthorizationStatus) -> SetupPermissionState {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return .granted
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        @unknown default:
            return .restricted
        }
    }
}
