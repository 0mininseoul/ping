import SwiftUI

struct ContentView: View {
    @ObservedObject private var environment = AppEnvironment.shared

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: environment.paired == nil ? "iphone.slash" : "checkmark.seal.fill")
                .font(.system(size: 52))
                .foregroundStyle(environment.paired == nil ? Color.secondary : Color.green)

            Text(environment.paired == nil ? "데스크톱과 연결되지 않음" : "연결됨")
                .font(.headline)

            if let paired = environment.paired {
                Text("계정 \(paired.session.userId.prefix(8))…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("Mac의 Ping 설정에서 QR 코드로 이 기기를 추가하세요.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(32)
        .task { await PushRegistrar.shared.registerIfPossible() }
    }
}
