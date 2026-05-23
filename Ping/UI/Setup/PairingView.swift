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
        static let windowWidth: CGFloat = 480
        static let windowHeight: CGFloat = 600
        static let horizontalPadding: CGFloat = 28
        static let topPadding: CGFloat = 22
        static let bottomPadding: CGFloat = 24
        static let headerHeight: CGFloat = 82
        static let permissionTrailingWidth: CGFloat = 78
        static let contentWidth = windowWidth - (horizontalPadding * 2)
        static let contentHeight = windowHeight - topPadding - bottomPadding - headerHeight
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
        ZStack(alignment: .top) {
            onboardingBackground

            VStack(spacing: 0) {
                header
                    .frame(width: Layout.contentWidth, height: Layout.headerHeight, alignment: .top)
                    .fixedSize(horizontal: false, vertical: true)

                ZStack(alignment: .top) {
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
                .frame(width: Layout.contentWidth, height: Layout.contentHeight, alignment: .top)
            }
            .padding(.horizontal, Layout.horizontalPadding)
            .padding(.top, Layout.topPadding)
            .padding(.bottom, Layout.bottomPadding)
        }
        .frame(width: Layout.windowWidth, height: Layout.windowHeight)
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
                Text("\(viewModel.displayedStepNumber) / \(viewModel.displayedStepCount)")
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
                setupChip("3초", icon: "timer")
                setupChip("메뉴바", icon: "menubar.rectangle")
            }

            Spacer()

            GlassButton("시작하기", isPrimary: true) {
                viewModel.next()
            }
        }
    }

    private var permissionsStep: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: 26)

            permissionStepHeader
                .padding(.bottom, 18)

            VStack(spacing: 8) {
                permissionRow(
                    title: "카메라",
                    icon: "camera.fill",
                    kind: .camera,
                    state: viewModel.cameraPermission,
                    actionTitle: permissionActionTitle(for: .camera, state: viewModel.cameraPermission)
                ) {
                    if viewModel.cameraPermission.needsSystemSettings {
                        viewModel.openSystemPermissionSettings(for: .camera)
                    } else {
                        Task { await viewModel.requestCamera() }
                    }
                }

                permissionRow(
                    title: "마이크",
                    icon: "mic.fill",
                    kind: .audio,
                    state: viewModel.audioPermission,
                    actionTitle: permissionActionTitle(for: .audio, state: viewModel.audioPermission)
                ) {
                    if viewModel.audioPermission.needsSystemSettings {
                        viewModel.openSystemPermissionSettings(for: .audio)
                    } else {
                        Task { await viewModel.requestAudio() }
                    }
                }

                permissionRow(
                    title: "알림",
                    icon: "bell.fill",
                    kind: .notifications,
                    state: viewModel.notificationPermission,
                    actionTitle: permissionActionTitle(for: .notifications, state: viewModel.notificationPermission)
                ) {
                    if viewModel.notificationPermission.needsSystemSettings {
                        viewModel.openSystemPermissionSettings(for: .notifications)
                    } else {
                        Task { await viewModel.requestNotifications() }
                    }
                }

                permissionRow(
                    title: "화면 및 시스템 오디오 녹음",
                    icon: "rectangle.inset.filled.and.person.filled",
                    kind: .screenRecording,
                    state: viewModel.screenRecordingPermission,
                    actionTitle: permissionActionTitle(for: .screenRecording, state: viewModel.screenRecordingPermission)
                ) {
                    Task { await viewModel.requestScreenRecording() }
                }
            }

            if let notice = viewModel.permissionNotice {
                permissionNoticeView(notice)
                    .padding(.top, 14)
            } else if let error = viewModel.errorMessage {
                inlineMessage(error)
                    .padding(.top, 14)
            }

            Spacer(minLength: 28)

            HStack(spacing: 10) {
                GlassButton("이전") {
                    viewModel.back()
                }

                Spacer()

                if viewModel.permissionNotice != nil {
                    GlassButton("시스템 설정 열기") {
                        viewModel.openSystemPermissionSettings()
                    }
                }

                primaryButton(viewModel.allPermissionsGranted ? "다음" : "계속", enabled: true) {
                    viewModel.next()
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var permissionStepHeader: some View {
        HStack {
            Text("권한 허용")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            Spacer()
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
        icon: String,
        kind: SetupPermissionKind,
        state: SetupPermissionState,
        actionTitle: String,
        request: @escaping () -> Void
    ) -> some View {
        let granted = state.isGranted

        return HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(granted ? PingDesign.ColorToken.success : Color.primary.opacity(0.70))
                .frame(width: 24)

            Text(title)
                .font(PingFont.body)
                .foregroundStyle(Color.primary.opacity(0.90))

            Spacer()

            if granted {
                Text("켜짐")
                    .font(PingFont.caption)
                    .foregroundStyle(PingDesign.ColorToken.success)
                    .frame(width: Layout.permissionTrailingWidth, alignment: .center)
            } else {
                GlassButton(actionTitle) {
                    request()
                }
                .frame(width: Layout.permissionTrailingWidth)
                .disabled(viewModel.isRequesting(kind))
                .opacity(viewModel.isRequesting(kind) ? 0.55 : 1)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background {
            RoundedRectangle(cornerRadius: PingDesign.Radius.row, style: .continuous)
                .fill(PingDesign.Surface.rowFill)
                .overlay {
                    RoundedRectangle(cornerRadius: PingDesign.Radius.row, style: .continuous)
                        .strokeBorder(PingDesign.Surface.hairline, lineWidth: 0.8)
                }
        }
    }

    private func permissionActionTitle(for kind: SetupPermissionKind, state: SetupPermissionState) -> String {
        if viewModel.isRequesting(kind) {
            return "확인 중"
        }
        if kind == .screenRecording {
            return "확인"
        }
        return state.needsSystemSettings ? "설정" : "허용"
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
        HStack(spacing: 8) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(PingDesign.Status.warning)

            Text(notice.title)
                .font(PingFont.caption)
                .foregroundStyle(Color.primary.opacity(0.78))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            Capsule(style: .continuous)
                .fill(PingDesign.Status.warningFill)
                .overlay {
                    Capsule(style: .continuous)
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
