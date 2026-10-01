# Windows QR 기기 연결 검증

2026-10-01. 설정·기기·설치 계획의 Task 2B 구현 결과다. 실제 iPhone/Watch 연결, 계정 관리·업데이트와 최종 설치 EXE는 전체 목표에 남아 있다.

## 구현

- 기기 탭에서 iPhone·Apple Watch 연결 QR을 준비하고 실패 시 다시 시도할 수 있다. QR은 기존 익명 인증 세션을 사용하며 별도 로그인이나 서버를 추가하지 않는다.
- Mac `DeviceHandoffPayload`, `SupabaseClient.exportDeviceHandoff()`와 PingKit `PingHandoffPayload.decode()`를 기준으로 `url`, `anonKey`, `accessToken`, `refreshToken`, `expiresAt`, `userId`의 6개 camelCase 필드와 UTC ISO 8601 날짜 문자열을 유지한다.
- 기존 `AuthenticatedSessionAsync()`를 사용해 만료에 가까운 토큰을 갱신한다. 다른 bootstrap/인증 요청과 같은 refresh 잠금을 사용하고, 기존 계정을 자동으로 교체하지 않는다.
- 표시 중 만료가 가까워지면 QR을 새로 준비한다. 탭 이동·창 닫기·계정 identity 변경·세션 거부 시 이미지와 요청을 제거하며, 늦게 끝난 생성 요청이나 이전 계정의 결과가 다시 표시되지 않도록 한다.
- QR은 production에서 메모리로 생성하고 표시한다. QR 파일·clipboard·로그를 자동 작성하지 않는다. 실패 안내에도 예외에 들어 있는 토큰을 노출하지 않는다. Mac와 같은 로그인 세션 주의 문구를 표시한다.
- QRCoder 1.8.0을 고정해 사용하며 MIT 라이선스를 앱 Assets에 포함한다. PNG의 픽셀 격자를 현재 DPI의 DIP로 환산해 표시하고 DPI 변경 시 다시 계산한다. 기존 220DIP 축소 방식은 합성 데이터의 실제 표시 QR 디코딩에서 실패해 교체했다.

세션/refresh 의미는 [Supabase 공식 세션 문서](https://supabase.com/docs/guides/auth/sessions), PNG 생성 API는 [QRCoder 공식 저장소](https://github.com/Shane32/QRCoder)를 확인했다. Supabase changelog도 확인했으며 이번 작업에서 운영 인증 설정·DB·마이그레이션을 변경하지 않았다.

## 검증

| 검사 | 결과 |
| --- | --- |
| Core Release 테스트 | 256 통과, 새 토큰·6개 필드·ISO 8601·refresh 공유 검사 포함 |
| App Release 테스트 | 307 통과, 취소 후 늦은 결과·계정 변경·안전한 실패/재시도 검사 포함 |
| 실제 WinUI fixture | 150 통과 |
| 정상 x64 Release 빌드 | native/Core/WinUI 경고 0, 오류 0 |
| Production 의존성/파일 | QRCoder 및 라이선스 포함, test-only ZXing decoder와 fixture 타입 제외 |

WinUI 결과: `windows/artifacts/ui-shell-2b5126098db74aecad9665180890f961/`. 앱이 소유한 합성 세션과 fake HTTP로 길이가 긴 토큰을 QR에 넣었다. 원본 PNG뿐 아니라 실제 WinUI Image의 렌더 결과를 ZXing으로 디코딩해 6개 필드를 확인했다. 표시 QR 픽셀은 직접 확인했다. 탭을 떠나거나 창을 닫았을 때 Image.Source와 view model의 이미지가 제거되는 검사도 통과했다.

Fixture의 `settings-pairing-synthetic.png`, `pairing-image-synthetic.png`와 `pairing-fixture/`의 설정·세션은 모두 합성 데이터다. 실제 사용자 설정이나 세션을 읽거나, 운영 backend에 접속하거나, 실제 로그인 QR을 저장하지 않았다.

## 남은 확인

실제 iPhone 카메라 스캔, iPhone/Watch의 계정 채택과 장기 refresh 공유 동작은 실기 검증이 필요하다. 현재 Windows의 200% DPI에서 렌더/디코딩을 확인했으며 여러 모니터와 다른 DPI 이동은 실제 QA에 남아 있다. 생성 결과가 토큰 갱신과 같은 포맷이라는 검사를 실제 기기 간 연결 성공으로 간주하지 않는다.

다음은 Mac 저장 계정 UX를 참고한 기존 계정 유지·전환·명시적 새 계정 추가/제거와 실제 업데이트 흐름이다. 계정 전환 구현에서도 QR 제거를 전환 시작 전에 호출해야 한다.
