import AppKit
import SwiftUI

struct PairingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ObservedObject var viewModel: PairingViewModel
    var onComplete: (OnboardingCompletion) -> Void

    @StateObject private var roomSearchViewModel: RoomSearchViewModel
    @FocusState private var focusedField: Field?
    @FocusState private var joinSearchFocused: Bool
    private let excludingUid: String?

    private enum Field: Equatable {
        case nickname
        case roomName
    }

    private enum Layout {
        static let headerHeight: CGFloat = 82
    }

    init(
        viewModel: PairingViewModel,
        excludingUid: String? = nil,
        onComplete: @escaping (OnboardingCompletion) -> Void
    ) {
        self.viewModel = viewModel
        self.onComplete = onComplete
        self.excludingUid = excludingUid
        _roomSearchViewModel = StateObject(wrappedValue: RoomSearchViewModel(excludingUid: excludingUid))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: Layout.headerHeight, alignment: .top)

            ZStack {
                switch viewModel.step {
                case .welcome:
                    welcomeStep
                case .permissions:
                    permissionsStep
                case .nickname:
                    nicknameStep
                case .connectionChoice:
                    connectionChoiceStep
                case .createRoom:
                    createRoomStep
                case .joinRoom:
                    joinRoomStep
                case .done:
                    doneStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, 28)
        .padding(.top, 22)
        .padding(.bottom, 24)
        .frame(width: 480, height: 600)
        .background {
            onboardingBackground
        }
        .task {
            await viewModel.refreshPermissionStates()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await viewModel.refreshPermissionStates() }
        }
    }

    private var onboardingBackground: some View {
        ZStack(alignment: .top) {
            PingDesign.Surface.windowBase

            LinearGradient(
                colors: [
                    PingDesign.Surface.backgroundWashLeading,
                    PingDesign.Surface.backgroundWashTrailing,
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    PingDesign.Surface.radialHighlight,
                    PingDesign.Surface.radialHighlight.opacity(0.18),
                    Color.clear
                ],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 380
            )
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    headerLogo
                    Text("Ping")
                        .font(PingFont.wordmark)
                }
                Spacer()
                Text("\(viewModel.step.rawValue + 1) / \(PairingViewModel.Step.allCases.count)")
                    .font(PingFont.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            onboardingProgressBar(progress: viewModel.progress)
        }
    }

    private func onboardingProgressBar(progress: Double) -> some View {
        GeometryReader { proxy in
            let width = max(1, proxy.size.width)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(PingDesign.Surface.progressTrack)
                Capsule()
                    .fill(PingDesign.ColorToken.accent)
                    .frame(width: width)
                    .scaleEffect(x: min(max(progress, 0), 1), y: 1, anchor: .leading)
            }
            .animation(reduceMotion ? nil : PingDesign.Motion.progressGauge, value: progress)
            .clipped()
        }
        .frame(height: 5)
    }

    private var headerLogo: some View {
        Image("HeaderLogo")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: 38, height: 38)
            .pingShadow(PingDesign.Shadow.chip)
            .accessibilityHidden(true)
    }

    private var welcomeStep: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 18)

            GlassPanel(shape: .circle) {
                Image(systemName: "video.bubble.left.fill")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 112, height: 112)
            }

            VStack(spacing: 10) {
                Text(OnboardingCopy.welcomeHeadline)
                    .font(PingFont.display)
                    .multilineTextAlignment(.center)

                Text(OnboardingCopy.welcomeSubtitle)
                    .font(PingFont.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                setupChip("Option+P", icon: "keyboard")
                setupChip("2초", icon: "timer")
                setupChip("메뉴바", icon: "menubar.rectangle")
            }

            Spacer()

            GlassButton("시작하기", isPrimary: true) {
                viewModel.next()
            }
        }
    }

    private var permissionsStep: some View {
        VStack(spacing: 14) {
            permissionStepHeader

            VStack(spacing: 10) {
                permissionRow(
                    title: "카메라",
                    detail: "원형 거울 미리보기와 녹화",
                    icon: "camera.fill",
                    state: viewModel.cameraPermission,
                    actionTitle: viewModel.cameraPermission.needsSystemSettings ? "설정" : "허용"
                ) {
                    if viewModel.cameraPermission.needsSystemSettings {
                        viewModel.openSystemPermissionSettings(for: .camera)
                    } else {
                        Task { await viewModel.requestCamera() }
                    }
                }

                permissionRow(
                    title: "마이크",
                    detail: "2초 영상의 음성 녹음",
                    icon: "mic.fill",
                    state: viewModel.audioPermission,
                    actionTitle: viewModel.audioPermission.needsSystemSettings ? "설정" : "허용"
                ) {
                    if viewModel.audioPermission.needsSystemSettings {
                        viewModel.openSystemPermissionSettings(for: .audio)
                    } else {
                        Task { await viewModel.requestAudio() }
                    }
                }

                permissionRow(
                    title: "알림",
                    detail: "상대가 보낸 Ping 배너 표시",
                    icon: "bell.badge.fill",
                    state: viewModel.notificationPermission,
                    actionTitle: viewModel.notificationPermission.needsSystemSettings ? "설정" : "허용"
                ) {
                    if viewModel.notificationPermission.needsSystemSettings {
                        viewModel.openSystemPermissionSettings(for: .notifications)
                    } else {
                        Task { await viewModel.requestNotifications() }
                    }
                }

                permissionRow(
                    title: "화면 녹화",
                    detail: "화면+얼굴 모드 녹화",
                    icon: "rectangle.on.rectangle.fill",
                    state: viewModel.screenRecordingPermission,
                    actionTitle: "설정 열기"
                ) {
                    viewModel.requestScreenRecording()
                }
            }

            if let notice = viewModel.permissionNotice {
                permissionNoticeView(notice)
            } else if let error = viewModel.errorMessage {
                inlineMessage(error)
            }

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                GlassButton("이전") {
                    viewModel.back()
                }

                Spacer()

                if viewModel.canProceedFromPermissions {
                    primaryButton("다음", enabled: true) {
                        viewModel.next()
                    }
                } else if viewModel.permissionNotice != nil {
                    GlassButton("시스템 설정 열기", isPrimary: true) {
                        viewModel.openSystemPermissionSettings()
                    }
                } else {
                    GlassButton(
                        viewModel.isRequestingPermissions ? "요청 중..." : "권한 한 번에 요청",
                        isPrimary: true
                    ) {
                        Task { await viewModel.requestAllPermissions() }
                    }
                    .disabled(viewModel.isRequestingPermissions)
                    .opacity(viewModel.isRequestingPermissions ? 0.55 : 1)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var permissionStepHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                Text("권한 체크")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text("보내기와 받기에 필요한 항목만 켭니다. 화면 녹화는 macOS 설정에서 확인합니다.")
                    .font(PingFont.caption)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            VStack(spacing: 3) {
                Text("\(viewModel.grantedPermissionCount)")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("/ 4")
                    .font(PingFont.caption)
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(viewModel.canProceedFromPermissions ? PingDesign.ColorToken.success : PingDesign.ColorToken.accent)
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(PingDesign.Surface.chipFill)
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(PingDesign.Surface.strongHairline, lineWidth: 0.8)
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var nicknameStep: some View {
        VStack(spacing: 20) {
            stepHeading(
                title: "닉네임 설정",
                subtitle: "룸 검색과 초대 알림에 표시됩니다."
            )

            onboardingTextField(
                label: "닉네임",
                placeholder: "예: 박영민",
                text: $viewModel.nickname,
                field: .nickname,
                message: nicknameFieldMessage,
                count: "\(viewModel.trimmedNickname.count)/24",
                isWarning: nicknameFieldIsWarning,
                onSubmit: { viewModel.next() }
            )

            if let error = viewModel.errorMessage {
                inlineMessage(error)
            }

            Spacer()

            footerButtons(showBack: true) {
                primaryButton("다음", enabled: viewModel.canProceedFromNickname) {
                    viewModel.next()
                }
            }
        }
        .onAppear { focusedField = .nickname }
    }

    private var connectionChoiceStep: some View {
        VStack(spacing: 18) {
            stepHeading(
                title: "어떻게 시작할까요?",
                subtitle: "룸을 만들거나 상대가 만든 룸에 참여할 수 있습니다."
            )
            .padding(.bottom, 6)

            VStack(spacing: 12) {
                connectionChoiceButton(
                    title: "룸 생성하기",
                    detail: "상대를 초대할 1:1 룸을 먼저 만듭니다.",
                    icon: "plus.message.fill",
                    action: viewModel.chooseCreateRoom
                )

                connectionChoiceButton(
                    title: "룸 참여하기",
                    detail: "상대가 만든 열린 룸을 검색해서 들어갑니다.",
                    icon: "person.2.wave.2.fill",
                    action: viewModel.chooseJoinRoom
                )
            }

            secondaryLaterButton

            Spacer()

            footerButtons(showBack: true) {
                EmptyView()
            }
        }
    }

    private var createRoomStep: some View {
        VStack(spacing: 20) {
            stepHeading(
                title: "룸 생성하기",
                subtitle: "상대가 들어올 1:1 룸 이름을 정하세요."
            )

            onboardingTextField(
                label: "룸 이름",
                placeholder: "",
                text: $viewModel.roomName,
                field: .roomName,
                message: roomNameFieldMessage,
                count: "\(viewModel.trimmedRoomName.count)/\(RoomLimits.maxRoomNameLength)",
                isWarning: roomNameFieldIsWarning,
                onSubmit: { viewModel.completeCreateRoom() }
            )

            Spacer()

            footerButtons(showBack: true) {
                primaryButton("룸 만들기", enabled: viewModel.canProceedFromCreateRoom) {
                    viewModel.completeCreateRoom()
                }
            }
        }
        .onAppear { focusedField = .roomName }
    }

    private var joinRoomStep: some View {
        VStack(spacing: 18) {
            stepHeading(
                title: "룸 참여하기",
                subtitle: "상대가 만든 열린 룸 이름을 검색하세요."
            )
            .padding(.bottom, 4)

            joinSearchField

            if let error = roomSearchViewModel.errorMessage {
                inlineMessage(error)
            }

            joinRoomResults

            Spacer(minLength: 0)

            footerButtons(showBack: true) {
                EmptyView()
            }
        }
        .onAppear {
            roomSearchViewModel.updateExcludingUid(excludingUid ?? AppState.shared.currentUser?.id)
            joinSearchFocused = true
        }
    }

    private var nicknameFieldMessage: String {
        if viewModel.trimmedNickname.isEmpty {
            return "24자 이내로 표시됩니다."
        }
        return viewModel.nicknameValidationMessage ?? "좋습니다."
    }

    private var nicknameFieldIsWarning: Bool {
        !viewModel.trimmedNickname.isEmpty && !viewModel.canProceedFromNickname
    }

    private var roomNameFieldMessage: String {
        if viewModel.trimmedRoomName.isEmpty {
            return "초대받은 사람이 확인할 수 있는 이름입니다. 최대 \(RoomLimits.maxRoomNameLength)자."
        }
        return viewModel.roomNameValidationMessage ?? "이 이름으로 1:1 룸을 만듭니다."
    }

    private var roomNameFieldIsWarning: Bool {
        !viewModel.trimmedRoomName.isEmpty && !viewModel.canProceedFromCreateRoom
    }

    private var doneStep: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 30)

            GlassPanel(shape: .circle) {
                Image(systemName: "checkmark")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(PingDesign.ColorToken.success)
                    .frame(width: 112, height: 112)
            }

            VStack(spacing: 10) {
                Text("설정 완료")
                    .font(PingFont.display)
                Text(doneSubtitle)
                    .font(PingFont.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            setupChip(doneChipText, icon: doneChipIcon)

            if let error = viewModel.errorMessage {
                inlineMessage(error)
            }

            Spacer()

            footerButtons(showBack: true) {
                GlassButton(doneButtonTitle, isPrimary: true) {
                    guard !viewModel.isCompleting else { return }
                    guard let payload = viewModel.completionPayload else {
                        viewModel.step = .connectionChoice
                        return
                    }
                    onComplete(payload)
                }
                .disabled(viewModel.isCompleting)
                .opacity(viewModel.isCompleting ? 0.58 : 1)
            }
        }
    }

    private var doneSubtitle: String {
        switch viewModel.completionPayload?.action {
        case .createRoom:
            return "룸을 만들고 바로 초대 화면을 엽니다."
        case .joinRoom:
            return "선택한 룸에 참여한 뒤 바로 사용할 수 있습니다."
        case .later:
            return "메뉴바의 내 룸에서 언제든 룸을 만들거나 참여할 수 있습니다."
        case nil:
            return "메뉴바의 Ping 아이콘과 Option+P 단축키로 바로 사용할 수 있습니다."
        }
    }

    private var doneChipText: String {
        switch viewModel.completionPayload?.action {
        case .createRoom(let name):
            return name
        case .joinRoom(let room):
            return room.name
        case .later:
            return "나중에 설정"
        case nil:
            return "준비 중"
        }
    }

    private var doneChipIcon: String {
        switch viewModel.completionPayload?.action {
        case .joinRoom:
            return "person.2.fill"
        case .later:
            return "clock"
        case .createRoom, nil:
            return "plus.message.fill"
        }
    }

    private var doneButtonTitle: String {
        if viewModel.isCompleting {
            return "처리 중..."
        }

        switch viewModel.completionPayload?.action {
        case .createRoom:
            return "룸 만들고 초대하기"
        case .joinRoom:
            return "룸 참여하고 시작"
        case .later:
            return "Ping 시작"
        case nil:
            return "계속"
        }
    }

    private var secondaryLaterButton: some View {
        Button {
            viewModel.deferRoomSetup()
        } label: {
            Text("나중에 하기")
                .font(PingFont.caption)
                .foregroundStyle(Color.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private var joinSearchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField("룸 이름 검색", text: $roomSearchViewModel.query)
                .textFieldStyle(.plain)
                .font(PingFont.body)
                .focused($joinSearchFocused)
                .onSubmit { roomSearchViewModel.searchNow() }

            if roomSearchViewModel.isSearching {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: PingDesign.Radius.row, style: .continuous)
                .fill(joinSearchFocused ? PingDesign.Surface.inputFieldFocusedFill : PingDesign.Surface.inputFieldFill)
                .overlay {
                    RoundedRectangle(cornerRadius: PingDesign.Radius.row, style: .continuous)
                        .strokeBorder(
                            joinSearchFocused
                                ? PingDesign.ColorToken.accent.opacity(0.44)
                                : PingDesign.Surface.hairline,
                            lineWidth: 1
                        )
                }
        }
    }

    @ViewBuilder private var joinRoomResults: some View {
        let query = roomSearchViewModel.query.trimmingCharacters(in: .whitespacesAndNewlines)

        ScrollView {
            LazyVStack(spacing: 10) {
                if query.isEmpty {
                    emptyJoinRooms("룸 이름을 입력하세요")
                } else if roomSearchViewModel.roomResults.isEmpty && !roomSearchViewModel.isSearching {
                    emptyJoinRooms("열린 룸이 없습니다")
                } else {
                    ForEach(roomSearchViewModel.roomResults) { room in
                        joinRoomResult(room)
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .frame(maxHeight: 190)
    }

    private func joinRoomResult(_ room: Room) -> some View {
        Button {
            viewModel.selectRoomForJoin(room)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(PingDesign.ColorToken.accent)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text(room.name)
                        .font(PingFont.body)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("방장: \(room.memberNicknames[room.ownerUid] ?? "알 수 없음")")
                        .font(PingFont.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(PingDesign.ColorToken.accent)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: PingDesign.Radius.row, style: .continuous)
                    .fill(PingDesign.Surface.rowFill)
                    .overlay {
                        RoundedRectangle(cornerRadius: PingDesign.Radius.row, style: .continuous)
                            .strokeBorder(PingDesign.Surface.strongHairline, lineWidth: 0.8)
                    }
            }
        }
        .buttonStyle(.plain)
    }

    private func emptyJoinRooms(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.secondary)
            Text(message)
                .font(PingFont.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private func connectionChoiceButton(
        title: String,
        detail: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: PingDesign.Radius.iconTile, style: .continuous)
                        .fill(PingDesign.ColorToken.accent.opacity(0.11))
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(PingDesign.ColorToken.accent)
                }
                .frame(width: 46, height: 46)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(PingFont.title)
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(PingFont.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background {
                RoundedRectangle(cornerRadius: PingDesign.Radius.panel, style: .continuous)
                    .fill(PingDesign.Surface.rowFill)
                    .overlay {
                        RoundedRectangle(cornerRadius: PingDesign.Radius.panel, style: .continuous)
                            .strokeBorder(PingDesign.Surface.strongHairline, lineWidth: 0.8)
                    }
            }
        }
        .buttonStyle(.plain)
    }

    private func permissionRow(
        title: String,
        detail: String,
        icon: String,
        state: SetupPermissionState,
        actionTitle: String,
        request: @escaping () -> Void
    ) -> some View {
        let granted = state.isGranted
        let blocked = state.needsSystemSettings

        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: PingDesign.Radius.iconTile, style: .continuous)
                    .fill(permissionAccent(for: state).opacity(granted ? 0.16 : 0.10))
                    .overlay {
                        RoundedRectangle(cornerRadius: PingDesign.Radius.iconTile, style: .continuous)
                            .strokeBorder(PingDesign.Surface.hairline, lineWidth: 0.7)
                    }

                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(granted ? PingDesign.ColorToken.success : Color.primary.opacity(0.78))
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(PingFont.body)
                    .foregroundStyle(Color.primary.opacity(0.90))
                Text(detail)
                    .font(PingFont.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if granted {
                permissionStatusPill("켜짐", icon: "checkmark", color: PingDesign.ColorToken.success)
            } else {
                HStack(spacing: 8) {
                    permissionStatusPill(blocked ? "필요" : "대기", icon: blocked ? "gearshape.fill" : "circle", color: permissionAccent(for: state))
                    GlassButton(actionTitle) {
                        request()
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: PingDesign.Radius.row, style: .continuous)
                .fill(PingDesign.Surface.rowFill)
                .overlay {
                    RoundedRectangle(cornerRadius: PingDesign.Radius.row, style: .continuous)
                        .strokeBorder(PingDesign.Surface.hairline, lineWidth: 0.8)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: PingDesign.Radius.row, style: .continuous)
                        .inset(by: 1)
                        .strokeBorder(PingDesign.Surface.strongHairline.opacity(0.48), lineWidth: 0.6)
                }
                .pingShadow(PingDesign.Shadow.control)
        }
    }

    private func permissionStatusPill(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
            Text(title)
                .font(PingFont.caption)
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background {
            Capsule()
                .fill(color.opacity(0.10))
                .overlay {
                    Capsule()
                        .strokeBorder(color.opacity(0.20), lineWidth: 0.7)
                }
        }
    }

    private func permissionAccent(for state: SetupPermissionState) -> Color {
        switch state {
        case .granted:
            return PingDesign.ColorToken.success
        case .denied, .restricted:
            return PingDesign.Status.warning
        case .notDetermined:
            return PingDesign.ColorToken.accent
        }
    }

    private func footerButtons<Content: View>(
        showBack: Bool,
        @ViewBuilder trailing: () -> Content
    ) -> some View {
        HStack {
            if showBack {
                GlassButton("이전") {
                    viewModel.back()
                }
                .disabled(viewModel.isCompleting)
                .opacity(viewModel.isCompleting ? 0.55 : 1)
            }
            Spacer()
            trailing()
        }
    }

    private func primaryButton(_ title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        GlassButton(title, isPrimary: true, action: action)
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.45)
    }

    private func onboardingTextField(
        label: String,
        placeholder: String,
        text: Binding<String>,
        field: Field,
        message: String,
        count: String?,
        isWarning: Bool,
        onSubmit: @escaping () -> Void
    ) -> some View {
        let isFocused = focusedField == field

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(label)
                    .font(PingFont.label)
                    .foregroundStyle(Color.primary.opacity(0.72))

                if field == .roomName {
                    Text("필수")
                        .font(PingFont.caption)
                        .foregroundStyle(PingDesign.ColorToken.accent.opacity(0.90))
                }
            }

            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 21, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.primary.opacity(0.90))
                .lineLimit(1)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .frame(height: 52)
                .background {
                    inputFieldSurface(isFocused: isFocused)
                }
                .focused($focusedField, equals: field)
                .onSubmit(onSubmit)
                .onChange(of: text.wrappedValue) { newValue in
                    guard field == .roomName else { return }
                    let cappedName = RoomLimits.sanitizedRoomName(newValue)
                    if cappedName != newValue {
                        text.wrappedValue = cappedName
                    }
                }

            HStack(alignment: .firstTextBaseline) {
                Text(message)
                    .font(PingFont.caption)
                    .foregroundStyle(isWarning ? PingDesign.Status.warning : Color.secondary)

                Spacer()

                if let count {
                    Text(count)
                        .font(PingFont.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .frame(height: 18)
        }
        .padding(18)
        .background {
            onboardingInputCard(isFocused: isFocused)
        }
        .animation(reduceMotion ? nil : PingDesign.Motion.buttonHover, value: isFocused)
    }

    private func onboardingInputCard(isFocused: Bool) -> some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(PingDesign.Surface.inputCardFill)
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(
                        isFocused
                            ? PingDesign.ColorToken.accent.opacity(0.28)
                            : PingDesign.Surface.strongHairline,
                        lineWidth: 0.8
                    )
            }
    }

    private func inputFieldSurface(isFocused: Bool) -> some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(isFocused ? PingDesign.Surface.inputFieldFocusedFill : PingDesign.Surface.inputFieldFill)
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        isFocused
                            ? PingDesign.ColorToken.accent.opacity(0.48)
                            : PingDesign.Surface.hairline,
                        lineWidth: isFocused ? 1.1 : 0.8
                    )
            }
            .animation(reduceMotion ? nil : PingDesign.Motion.buttonHover, value: isFocused)
    }

    private func stepHeading(title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(PingFont.display)
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(PingFont.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func permissionNoticeView(_ notice: PermissionNotice) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(PingDesign.Status.warning)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 3) {
                Text(notice.title)
                    .font(PingFont.label)
                    .foregroundStyle(Color.primary.opacity(0.88))
                Text(notice.message)
                    .font(PingFont.caption)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(PingDesign.Status.warningFill)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(PingDesign.Status.warningStroke, lineWidth: 0.8)
                }
        }
    }

    private func setupChip(_ label: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.76))
            Text(label)
                .font(PingFont.caption)
                .foregroundStyle(Color.primary.opacity(0.80))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background {
            Capsule()
                .fill(PingDesign.Surface.chipFill)
                .overlay {
                    Capsule()
                        .strokeBorder(PingDesign.Surface.strongHairline, lineWidth: 0.8)
                }
                .overlay {
                    Capsule()
                        .inset(by: 1)
                        .strokeBorder(PingDesign.Surface.hairline, lineWidth: 0.6)
                }
                .pingShadow(PingDesign.Shadow.chip)
        }
    }

    private func inlineMessage(_ message: String) -> some View {
        Text(message)
            .font(PingFont.caption)
            .foregroundStyle(PingDesign.Status.warning)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }
}

#if DEBUG
#Preview("Pairing") {
    PairingView(viewModel: PairingViewModel()) { _ in }
}
#endif
