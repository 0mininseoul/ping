import SwiftUI
import PingKit

/// Paired home: a light list of rooms. Tapping a room opens its thread. Replaces
/// the old static "연결됐어요" screen so the app has something to show when opened
/// cold, while keeping the receive+reply role (no recording here).
struct InboxView: View {
    let account: PairedAccount

    @State private var rooms: [PingRoom] = []
    @State private var isLoading = true
    @State private var showDisconnectConfirmation = false

    var body: some View {
        Group {
            if rooms.isEmpty {
                emptyState
            } else {
                List {
                    Section {
                        ForEach(rooms) { room in
                            NavigationLink(value: PingRoute.thread(roomId: room.id, roomName: room.name)) {
                                roomRow(room)
                            }
                        }
                    } footer: {
                        Text("ping 영상은 Mac·PC에서 보내요. 여기선 받은 ping을 보고 빠르게 답할 수 있어요.")
                            .font(.footnote)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Ping")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("연결 해제") {
                    showDisconnectConfirmation = true
                }
                .foregroundStyle(.red)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Label("연결됨", systemImage: "checkmark.seal.fill")
                    .font(.caption2)
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.green)
            }
        }
        .overlay {
            if isLoading && rooms.isEmpty { ProgressView() }
        }
        .refreshable { await load() }
        .task { await pollRooms() }
        .confirmationDialog("연결 해제", isPresented: $showDisconnectConfirmation, titleVisibility: .visible) {
            Button("연결 해제", role: .destructive) {
                AppEnvironment.shared.disconnect()
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("연결을 해제하면 QR 코드를 다시 스캔해야 합니다.")
        }
    }

    private func roomRow(_ room: PingRoom) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.accentColor.opacity(0.15))
                Text(initial(for: room))
                    .font(.headline)
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(room.title(excluding: account.session.userId))
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text("받은 ping과 대화 보기")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func initial(for room: PingRoom) -> String {
        let title = room.title(excluding: account.session.userId)
        return title.isEmpty ? "?" : String(title.prefix(1))
    }

    private var emptyState: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 8)

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 52))
                .foregroundStyle(.green)

            VStack(spacing: 6) {
                Text("연결됐어요")
                    .font(.title2.bold())
                Text("상대가 ping을 보내면 여기와 알림으로 도착해요.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 16) {
                howItWorksRow(icon: "bell.badge.fill", title: "알림으로 도착",
                              detail: "상대가 보낸 ping이 iPhone과 Apple Watch에 알림으로 와요.")
                howItWorksRow(icon: "play.circle.fill", title: "탭하면 바로 재생",
                              detail: "알림이나 목록에서 누르면 3초 영상을 바로 볼 수 있어요.")
                howItWorksRow(icon: "mic.fill", title: "음성으로 답장",
                              detail: "받아쓰기로 말하면 텍스트로 답장이 전송돼요. 영상은 Mac·PC에서 보내요.")
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
            .padding(.horizontal, 24)

            Spacer()
        }
    }

    private func howItWorksRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(Color.accentColor)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.bold())
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func load() async {
        guard let client = AppEnvironment.shared.makeClient() else {
            isLoading = false
            return
        }
        let fetched = (try? await client.myRooms()) ?? []
        rooms = fetched.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        isLoading = false
    }

    private func pollRooms() async {
        while !Task.isCancelled {
            await load()
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }
}
