import Foundation

/// Supabase Realtime 소켓 주소를 프로젝트 URL에서 만든다.
///
/// `URLComponents`로 조립하면 안 된다. `Supabase.plist`의 URL은 끝에 슬래시가 없어
/// `components.path`가 빈 문자열이고, 여기에 `appendingPathComponent`를 쓰면
/// 앞 슬래시가 없는 `"realtime/v1"`이 된다. 호스트가 있는데 경로가 `/`로 시작하지 않으면
/// `URLComponents.url`은 **nil**을 돌려주므로 연결을 시도조차 못 하고 폴링으로 떨어졌다.
/// 2026-09-03까지 Realtime이 한 번도 붙지 않은 원인이다.
enum RealtimeEndpoint {
    static func socketURL(for projectURL: URL) -> URL {
        projectURL.appendingPathComponent("realtime/v1")
    }
}
