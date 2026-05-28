import AppKit
import KeyboardShortcuts
import ServiceManagement
import SwiftUI

@MainActor
final class SettingsWindow: NSWindow {
    init<Content: View>(rootView: Content) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 400),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        title = "설정"
        contentView = NSHostingView(rootView: rootView)
        isReleasedWhenClosed = false
        center()
    }
}

struct SettingsView: View {
    @State private var selection: SettingsTab = .general

    var body: some View {
        TabView(selection: $selection) {
            GeneralSettingsView()
                .tabItem { Label("일반", systemImage: "gearshape") }
                .tag(SettingsTab.general)

            HotkeySettingsView()
                .tabItem { Label("단축키", systemImage: "keyboard") }
                .tag(SettingsTab.hotkey)

            RoomSettingsView()
                .tabItem { Label("룸", systemImage: "person.2") }
                .tag(SettingsTab.rooms)

            StorageSettingsView()
                .tabItem { Label("저장", systemImage: "folder") }
                .tag(SettingsTab.storage)

            AboutSettingsView()
                .tabItem { Label("정보", systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .frame(width: 560, height: 400)
    }
}

private enum SettingsTab: Hashable {
    case general
    case hotkey
    case rooms
    case storage
    case about
}

private struct GeneralSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var supabase = SupabaseClient.shared
    @State private var accountPendingDeletion: StoredAccount?

    @AppStorage(PingPreferenceKeys.notificationSound)
    private var notificationSound = PingNotificationSound.systemDefault.rawValue

    @AppStorage(PingPreferenceKeys.appearanceMode)
    private var appearanceMode = PingAppearanceMode.system.rawValue

    @State private var autoLaunchEnabled = Self.isAutoLaunchEnabled()
    @State private var autoLaunchStatusText = Self.autoLaunchStatusText()
    @State private var autoLaunchError: String?
    @State private var nicknameDraft = ""
    @State private var nicknameStatus: String?
    @State private var nicknameError: String?
    @State private var isSavingNickname = false

    var body: some View {
        SettingsPane {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    settingsGroup("앱") {
                        settingRow(
                            title: "로그인 시 자동 시작",
                            subtitle: autoLaunchError ?? autoLaunchStatusText,
                            subtitleColor: autoLaunchError == nil ? .secondary : .red
                        ) {
                            Toggle("", isOn: $autoLaunchEnabled)
                                .labelsHidden()
                        }
                        .onChange(of: autoLaunchEnabled) { newValue in
                            updateAutoLaunch(newValue)
                        }
                    }

                    settingsGroup("알림과 화면") {
                        settingRow(title: "알림 소리", subtitle: "수신 알림 배너에 사용할 소리입니다.") {
                            Picker("알림 소리", selection: $notificationSound) {
                                ForEach(PingNotificationSound.allCases) { sound in
                                    Text(sound.title).tag(sound.rawValue)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(width: 160)
                        }

                        Divider()
                            .opacity(0.45)
                            .padding(.leading, 148)

                        settingRow(title: "테마", subtitle: "메뉴 막대 단축키로도 바꿀 수 있습니다.") {
                            Picker("테마", selection: $appearanceMode) {
                                ForEach(PingAppearanceMode.allCases) { mode in
                                    Text(mode.title).tag(mode.rawValue)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(width: 220)
                        }
                    }

                    settingsGroup("프로필") {
                        settingRow(
                            title: "닉네임",
                            subtitle: nicknameHelperText,
                            subtitleColor: nicknameError == nil ? .secondary : .red
                        ) {
                            HStack(spacing: 10) {
                                TextField("닉네임", text: $nicknameDraft)
                                    .textFieldStyle(.roundedBorder)
                                    .onSubmit(saveNickname)
                                    .disabled(appState.currentUser?.id == nil || isSavingNickname)
                                    .frame(width: 220)

                                Button("저장", action: saveNickname)
                                    .disabled(!canSaveNickname)
                            }
                        }
                    }

                    // 게이트는 bootstrap 때 1회 설정되는 단방향 플래그라 Settings가 열려 있는 동안
                    // 값이 바뀌지 않는다. 따라서 @AppStorage가 아닌 일반 읽기로 충분하다.
                    if MultiAccountGate.isUnlocked() {
                        accountSwitcherGroup
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .alert(item: $accountPendingDeletion) { account in
            Alert(
                title: Text("계정을 삭제할까요?"),
                message: Text("이 익명 계정은 복구할 수 없습니다. 이 기기에서 영구히 사라집니다."),
                primaryButton: .destructive(Text("삭제")) {
                    NotificationCenter.default.post(
                        name: Notification.Name.pingRemoveAccount,
                        object: nil,
                        userInfo: [AccountIntentKey.userId: account.userId]
                    )
                },
                secondaryButton: .cancel(Text("취소"))
            )
        }
        .onAppear {
            refreshAutoLaunchStatus()
            nicknameDraft = appState.currentUser?.nickname ?? ""
        }
        .onChange(of: appState.currentUser?.nickname) { newValue in
            nicknameDraft = newValue ?? ""
        }
        .onChange(of: appearanceMode) { newValue in
            (PingAppearanceMode(rawValue: newValue) ?? .system).apply()
        }
    }

    private var accountSwitcherGroup: some View {
        settingsGroup("계정") {
            ForEach(supabase.accounts) { account in
                accountRow(account)
                if account.userId != supabase.accounts.last?.userId {
                    Divider().opacity(0.45).padding(.leading, 16)
                }
            }

            if !supabase.accounts.isEmpty {
                Divider().opacity(0.45).padding(.leading, 16)
            }

            Button {
                NotificationCenter.default.post(name: Notification.Name.pingAddAccount, object: nil)
            } label: {
                Label("계정 추가", systemImage: "plus.circle")
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func accountRow(_ account: StoredAccount) -> some View {
        let isActive = supabase.activeUserId == account.userId
        let displayName = account.nickname.isEmpty ? "(닉네임 없음)" : account.nickname
        return HStack(spacing: 12) {
            Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary)

            Text(displayName)
                .font(PingFont.label)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 16)

            if !isActive {
                Button("전환") {
                    NotificationCenter.default.post(
                        name: Notification.Name.pingSwitchAccount,
                        object: nil,
                        userInfo: [AccountIntentKey.userId: account.userId]
                    )
                }
                .buttonStyle(.borderless)
            }

            Button(role: .destructive) {
                accountPendingDeletion = account
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .disabled(supabase.accounts.count <= 1)
        }
        .contentShape(Rectangle())
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var nicknameHelperText: String {
        if let nicknameError {
            return nicknameError
        }

        if let nicknameStatus {
            return nicknameStatus
        }

        if appState.currentUser?.id == nil {
            return "사용자 설정이 끝나면 닉네임을 바꿀 수 있습니다."
        }

        return "룸 검색과 초대 알림에 표시됩니다."
    }

    private func settingsGroup<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(PingFont.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)

            VStack(spacing: 0) {
                content()
            }
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(PingDesign.Surface.panelFill)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(PingDesign.Surface.strongHairline.opacity(0.42), lineWidth: 0.8)
                    }
            }
        }
    }

    private func settingRow<Control: View>(
        title: String,
        subtitle: String?,
        subtitleColor: Color = .secondary,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(PingFont.label)
                    .foregroundStyle(Color.primary.opacity(0.88))

                if let subtitle {
                    Text(subtitle)
                        .font(PingFont.caption)
                        .foregroundStyle(subtitleColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 16)

            control()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var canSaveNickname: Bool {
        guard !isSavingNickname, appState.currentUser?.id != nil else { return false }
        let trimmed = nicknameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != appState.currentUser?.nickname
    }

    private func updateAutoLaunch(_ enabled: Bool) {
        autoLaunchError = nil

        do {
            // SMAppService.mainApp is the modern login-item API for this macOS-only app.
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            autoLaunchError = "자동 시작 설정을 변경하지 못했습니다."
        }

        refreshAutoLaunchStatus()
    }

    private func refreshAutoLaunchStatus() {
        autoLaunchEnabled = Self.isAutoLaunchEnabled()
        autoLaunchStatusText = Self.autoLaunchStatusText()
    }

    private func saveNickname() {
        guard canSaveNickname else { return }
        guard let uid = appState.currentUser?.id else { return }

        let nickname = nicknameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        isSavingNickname = true
        nicknameError = nil
        nicknameStatus = nil

        Task { @MainActor in
            do {
                let userService = UserService()
                try await userService.upsert(uid: uid, nickname: nickname)

                if let refreshedUser = try await userService.get(uid: uid) {
                    appState.currentUser = refreshedUser
                    nicknameDraft = refreshedUser.nickname
                } else if var currentUser = appState.currentUser {
                    currentUser.nickname = nickname
                    currentUser.searchableNickname = SearchableText.normalize(nickname)
                    appState.currentUser = currentUser
                    nicknameDraft = nickname
                }

                nicknameStatus = "저장됨"
            } catch {
                nicknameError = "닉네임을 저장하지 못했습니다."
            }

            isSavingNickname = false
        }
    }

    private static func isAutoLaunchEnabled() -> Bool {
        switch SMAppService.mainApp.status {
        case .enabled, .requiresApproval:
            return true
        case .notRegistered, .notFound:
            return false
        @unknown default:
            return false
        }
    }

    private static func autoLaunchStatusText() -> String {
        switch SMAppService.mainApp.status {
        case .enabled:
            return "켜져 있음"
        case .requiresApproval:
            return "시스템 설정에서 승인이 필요합니다."
        case .notRegistered:
            return "꺼져 있음"
        case .notFound:
            return "자동 시작 항목을 찾을 수 없습니다."
        @unknown default:
            return "상태를 확인할 수 없습니다."
        }
    }
}

private struct HotkeySettingsView: View {
    var body: some View {
        SettingsPane {
            Form {
                Section {
                    KeyboardShortcuts.Recorder("Ping 호출", name: .pingTrigger)
                    KeyboardShortcuts.Recorder("라이트/다크 전환", name: .appearanceToggle)
                    KeyboardShortcuts.Recorder("화면+얼굴 거울", name: .captureScreenFace)
                    KeyboardShortcuts.Recorder("내 룸", name: .historyToggle)
                } footer: {
                    Text("전역 단축키는 저장 즉시 적용됩니다.")
                        .font(PingFont.caption)
                }
            }
        }
    }
}

private struct RoomSettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        SettingsPane {
            VStack(alignment: .leading, spacing: 10) {
                Text("내 룸")
                    .font(PingFont.label)
                    .foregroundStyle(.secondary)

                if appState.rooms.isEmpty {
                    emptyRoomsState
                } else {
                    List {
                        ForEach(Array(appState.rooms.enumerated()), id: \.offset) { _, room in
                            HStack(spacing: 12) {
                                Text(room.name)
                                    .font(PingFont.body)
                                    .lineLimit(1)
                                    .truncationMode(.tail)

                                Spacer()

                                Text(room.status.rawValue)
                                    .font(PingFont.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background {
                                        Capsule()
                                            .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
                                    }
                            }
                            .padding(.vertical, 3)
                        }
                    }
                    .listStyle(.inset)
                    .frame(minHeight: 230)
                }
            }
        }
    }

    private var emptyRoomsState: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 32, weight: .regular))
                .foregroundStyle(.secondary)

            Text("룸 없음")
                .font(PingFont.label)
                .foregroundStyle(.secondary)

            Text("참여 중인 룸이 없습니다.")
                .font(PingFont.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct StorageSettingsView: View {
    @AppStorage(LocalArchive.saveSentEnabledKey)
    private var saveSentEnabled = true

    @AppStorage(LocalArchive.saveReceivedEnabledKey)
    private var saveReceivedEnabled = true

    @AppStorage(LocalArchive.allowRecipientsToSaveMyVideosKey)
    private var allowRecipientsToSaveMyVideos = false

    @AppStorage(LocalArchive.autoDeleteAfter30DaysKey)
    private var autoDeleteAfter30Days = false

    var body: some View {
        SettingsPane {
            Form {
                Section {
                    Toggle("보낸 영상 저장", isOn: $saveSentEnabled)
                    Toggle("받은 영상 자동 저장", isOn: $saveReceivedEnabled)
                    Toggle("상대가 내 영상 저장 가능", isOn: $allowRecipientsToSaveMyVideos)
                    Toggle("30일 뒤 자동 삭제", isOn: $autoDeleteAfter30Days)
                        .onChange(of: autoDeleteAfter30Days) { enabled in
                            LocalArchive.autoDeleteAfter30Days = enabled
                        }
                } footer: {
                    Text("받은 영상은 상대가 허용한 영상만 자동 저장됩니다. 끄면 해당 방향의 영상은 전송과 재생에 필요한 임시 파일만 사용합니다. 자동 삭제는 sent, received 폴더의 30일 지난 MP4 파일을 정리합니다.")
                        .font(PingFont.caption)
                }

                Section {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("저장 경로")
                            .frame(width: 96, alignment: .trailing)
                            .foregroundStyle(.secondary)

                        Text(displayPath)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)

                        Spacer()

                        Button {
                            LocalArchive.ensureFolders()
                            NSWorkspace.shared.open(LocalArchive.documentsRoot())
                        } label: {
                            Label("Finder에서 열기", systemImage: "arrow.up.forward.app")
                        }
                    }
                } footer: {
                    Text("보낸 영상과 받은 영상은 이 폴더 아래의 sent, received 폴더에 저장됩니다.")
                        .font(PingFont.caption)
                }
            }
        }
        .onAppear {
            LocalArchive.migrateLegacyPreferencesIfNeeded()
            saveSentEnabled = LocalArchive.saveSentEnabled
            saveReceivedEnabled = LocalArchive.saveReceivedEnabled
            allowRecipientsToSaveMyVideos = LocalArchive.allowRecipientsToSaveMyVideos
            autoDeleteAfter30Days = LocalArchive.autoDeleteAfter30Days
        }
        .onChange(of: saveSentEnabled) { newValue in
            LocalArchive.saveSentEnabled = newValue
        }
        .onChange(of: saveReceivedEnabled) { newValue in
            LocalArchive.saveReceivedEnabled = newValue
        }
        .onChange(of: allowRecipientsToSaveMyVideos) { newValue in
            LocalArchive.allowRecipientsToSaveMyVideos = newValue
        }
    }

    private var displayPath: String {
        LocalArchive.documentsRoot().path
    }
}

private struct AboutSettingsView: View {
    var body: some View {
        SettingsPane {
            VStack(spacing: 12) {
                Text(appName)
                    .font(PingFont.title)

                Text("버전 \(appVersion)")
                    .font(PingFont.body)
                    .foregroundStyle(.secondary)

                Text("개발자 : @0_min._.00")
                    .font(PingFont.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Text(SettingsUserDefaults.licenseDisplayText)
                    .font(PingFont.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Button(action: {
                    if let url = URL(string: "mailto:youngmin@ascentum.co.kr") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    Label("피드백 대환영", systemImage: "envelope.fill")
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "Ping"
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "0.1.4"
    }
}

private enum SettingsUserDefaults {
    static let licenseDisplayText = "라이선스: MIT"
}

private struct SettingsPane<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .font(PingFont.body)
            .padding(22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
