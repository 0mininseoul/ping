import SwiftUI

struct PairingView: View {
    @ObservedObject var viewModel: PairingViewModel
    var onComplete: (String, String?) -> Void

    @FocusState private var focusedField: Field?

    private enum Field {
        case nickname
        case roomName
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ZStack {
                switch viewModel.step {
                case .welcome:
                    welcomeStep
                case .permissions:
                    permissionsStep
                case .nickname:
                    nicknameStep
                case .firstRoom:
                    firstRoomStep
                case .done:
                    doneStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(28)
        .frame(width: 480, height: 600)
        .background {
            Rectangle()
                .fill(Color(nsColor: .windowBackgroundColor))
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.accentColor.opacity(0.18),
                                    Color.green.opacity(0.10),
                                    Color.clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(height: 280)
                }
        }
    }

    private var header: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Ping")
                    .font(PingFont.title)
                Spacer()
                Text("\(viewModel.step.rawValue + 1) / \(PairingViewModel.Step.allCases.count)")
                    .font(PingFont.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            ProgressView(value: viewModel.progress)
                .controlSize(.small)
                .tint(.accentColor)
        }
        .padding(.bottom, 24)
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
                Text("2초 영상으로 바로 답하기")
                    .font(PingFont.display)
                    .multilineTextAlignment(.center)

                Text("Option+P를 누르면 원형 거울이 열리고, Enter로 짧은 Ping을 보냅니다.")
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
        VStack(spacing: 18) {
            VStack(spacing: 8) {
                Text("필수 권한 허용")
                    .font(PingFont.display)
                Text("카메라와 마이크는 전송에, 알림은 수신 Ping 확인에 필요합니다.")
                    .font(PingFont.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 12) {
                permissionRow(
                    title: "카메라",
                    detail: "원형 거울 미리보기와 녹화",
                    icon: "camera.fill",
                    granted: viewModel.cameraGranted
                ) {
                    Task { await viewModel.requestCamera() }
                }

                permissionRow(
                    title: "마이크",
                    detail: "2초 영상의 음성 녹음",
                    icon: "mic.fill",
                    granted: viewModel.audioGranted
                ) {
                    Task { await viewModel.requestAudio() }
                }

                permissionRow(
                    title: "알림",
                    detail: "상대가 보낸 Ping 배너 표시",
                    icon: "bell.badge.fill",
                    granted: viewModel.notificationGranted
                ) {
                    Task { await viewModel.requestNotifications() }
                }
            }

            if let error = viewModel.errorMessage {
                errorText(error)
            }

            Spacer()

            VStack(spacing: 10) {
                GlassButton(
                    viewModel.isRequestingPermissions ? "요청 중..." : "권한 한 번에 요청",
                    isPrimary: false
                ) {
                    Task { await viewModel.requestAllPermissions() }
                }
                .disabled(viewModel.isRequestingPermissions)
                .opacity(viewModel.isRequestingPermissions ? 0.55 : 1)

                primaryButton("다음", enabled: viewModel.canProceedFromPermissions) {
                    viewModel.next()
                }
            }
        }
    }

    private var nicknameStep: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text("닉네임 설정")
                    .font(PingFont.display)
                Text("룸 검색과 초대 알림에 표시됩니다.")
                    .font(PingFont.body)
                    .foregroundStyle(.secondary)
            }

            GlassPanel {
                VStack(alignment: .leading, spacing: 10) {
                    Text("닉네임")
                        .font(PingFont.label)
                        .foregroundStyle(.secondary)

                    TextField("예: 박영민", text: $viewModel.nickname)
                        .textFieldStyle(.plain)
                        .font(PingFont.title)
                        .focused($focusedField, equals: .nickname)
                        .onSubmit { viewModel.next() }

                    HStack {
                        Text(viewModel.nicknameValidationMessage ?? " ")
                            .font(PingFont.caption)
                            .foregroundStyle(viewModel.canProceedFromNickname ? Color.secondary : Color.yellow)
                        Spacer()
                        Text("\(viewModel.trimmedNickname.count)/24")
                            .font(PingFont.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .padding(16)
            }

            if let error = viewModel.errorMessage {
                errorText(error)
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

    private var firstRoomStep: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text("첫 룸 만들기")
                    .font(PingFont.display)
                Text("상대가 들어올 1:1 룸 이름을 정하세요. 나중에 룸 찾기에서 만들어도 됩니다.")
                    .font(PingFont.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            GlassPanel {
                VStack(alignment: .leading, spacing: 10) {
                    Text("룸 이름")
                        .font(PingFont.label)
                        .foregroundStyle(.secondary)

                    TextField("예: \(viewModel.trimmedNickname) ↔ 김나영", text: $viewModel.roomName)
                        .textFieldStyle(.plain)
                        .font(PingFont.title)
                        .focused($focusedField, equals: .roomName)
                        .onSubmit { viewModel.next() }

                    Text("선택 사항")
                        .font(PingFont.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
            }

            Spacer()

            footerButtons(showBack: true) {
                HStack(spacing: 10) {
                    GlassButton("나중에") {
                        viewModel.skipFirstRoom()
                    }
                    GlassButton("계속", isPrimary: true) {
                        viewModel.next()
                    }
                }
            }
        }
        .onAppear { focusedField = .roomName }
    }

    private var doneStep: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 30)

            GlassPanel(shape: .circle) {
                Image(systemName: "checkmark")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(.green)
                    .frame(width: 112, height: 112)
            }

            VStack(spacing: 10) {
                Text("설정 완료")
                    .font(PingFont.display)
                Text("메뉴바의 Ping 아이콘과 Option+P 단축키로 바로 사용할 수 있습니다.")
                    .font(PingFont.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let roomName = viewModel.completionPayload?.firstRoomName {
                setupChip(roomName, icon: "person.2.fill")
            }

            Spacer()

            footerButtons(showBack: true) {
                GlassButton("Ping 시작", isPrimary: true) {
                    guard let payload = viewModel.completionPayload else {
                        viewModel.step = .nickname
                        return
                    }
                    onComplete(payload.nickname, payload.firstRoomName)
                }
            }
        }
    }

    private func permissionRow(
        title: String,
        detail: String,
        icon: String,
        granted: Bool,
        request: @escaping () -> Void
    ) -> some View {
        GlassPanel {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(PingFont.body)
                    Text(detail)
                        .font(PingFont.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if granted {
                    Label("허용됨", systemImage: "checkmark.circle.fill")
                        .font(PingFont.label)
                        .foregroundStyle(.green)
                } else {
                    GlassButton("허용") {
                        request()
                    }
                }
            }
            .padding(14)
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

    private func setupChip(_ label: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(label)
                .font(PingFont.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            Capsule()
                .glassEffect()
                .overlay {
                    Capsule().strokeBorder(Color.white.opacity(0.28), lineWidth: 1)
                }
        }
    }

    private func errorText(_ message: String) -> some View {
        Text(message)
            .font(PingFont.caption)
            .foregroundStyle(Color.yellow)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }
}

#if DEBUG
#Preview("Pairing") {
    PairingView(viewModel: PairingViewModel()) { _, _ in }
}
#endif
