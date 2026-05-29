import SwiftUI

struct WatchContentView: View {
    @ObservedObject private var store = WatchSessionStore.shared

    var body: some View {
        VStack(spacing: 10) {
            if store.paired == nil {
                Image(systemName: "iphone.slash")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text("iPhone에서 연결을 기다리는 중")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Image(systemName: "checkmark.seal.fill")
                    .font(.title3)
                    .foregroundStyle(.green)
                Text("연결됨")
                    .font(.headline)
                Text("ping 알림에서 영상을 보고 답장하세요.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .sheet(item: Binding(
            get: { store.pendingMessageId.map { MessageRef(id: $0) } },
            set: { store.pendingMessageId = $0?.id }
        )) { ref in
            WatchPlaybackView(messageId: ref.id)
        }
    }
}

private struct MessageRef: Identifiable {
    let id: String
}
