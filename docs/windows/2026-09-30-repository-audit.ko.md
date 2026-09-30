# Ping Windows 재개: 저장소 분석과 개발 전략

작성일: 2026-09-30 (Asia/Seoul). 분석 기준: `main`의 `5b21c1962de83d1e0d6c08ba8619802cbd53280b`.

## 결론

기존 Windows 네이티브 캡처·통신·패키징은 재사용하고, 사용자에게 보이는 앱 진입점과 대화 화면은 재구성한다. WinUI 3 / C# / C++ 기반을 유지하는 것이 현재 가장 근거 있는 선택이다. 전체 재작성은 이미 있는 카메라, 마이크, MP4 인코딩, 트레이, 전역 단축키, MSIX 작업까지 다시 검증하게 만든다.

Ping의 핵심은 작업 중 상대와 짧게 연결하는 **3초 영상 메신저**다. 관리 화면처럼 보이는 상태 카드보다 작은 거울, 대화 타임라인, 도착하는 영상이 제품의 중심이어야 한다. macOS 디자인의 의도와 상태 전이를 옮기고, Windows 창·알림·접근성·설치는 해당 OS의 관례로 구현한다.

이 문서는 코드 및 GitHub 기록 분석 결과다. 설치된 Windows 앱이나 실제 Mac을 조작해 동작을 확인한 결과는 아니다. 구현 존재, CI 통과, 실제 제품 QA를 구별한다.

## 현재 진척도

| 구분 | 확인 결과 | 근거 |
|---|---|---|
| macOS | 공개 소스·배포 기준 0.3.80, 2026-09-23 변경 | `project.yml`, `README.md`, main 커밋 |
| Windows | 패키지 버전 0.3.46.0, 마지막 공개 Windows 릴리즈 2026-06-13 | `windows/src/Ping.Windows.App/Package.appxmanifest`, GitHub Releases |
| Windows 기반 | WinUI 3, .NET 10, Windows App SDK 2.1.3, C++ native capture | App/Core csproj, NativeCapture vcxproj |
| 지원 범위 | 현재 패키지는 Windows 11 24H2+, x64/ARM64 | manifest MinVersion 10.0.26100.0 |
| 테스트 | 9월 23일 CI에서 Core 50개, App 224개 통과 | [실행 로그](https://github.com/0mininseoul/ping/actions/runs/35851185404) |
| 빌드 | 같은 CI에서 x64/ARM64 빌드와 Inno EXE 생성 성공 | 위 실행 로그 |
| 런타임 품질 | 실제 장치의 캡처·백그라운드 수신·교차 전송 검증이 여전히 필요 | 기존 QA 문서, 이슈 #24–#35 |
| 남은 개선 PR | #38 draft, 6월 이후 갱신 없음 | [PR #38](https://github.com/0mininseoul/ping/pull/38) |

CI의 App 테스트는 WinUI 앱 전체를 실행하지 않고 여러 앱 소스를 `net10.0` 테스트 프로젝트에 링크한다. 일부는 소스 문자열 검사다. 274개 테스트 통과는 투명한 원형 창, 실제 카메라, 알림 클릭, 설치 후 권한까지 보증하지 않는다. 위 CI 실행의 보존된 Actions artifact 목록은 0개다. 성공 로그와 이번 작업에서 전달할 실제 설치물도 구별해야 한다.

## 제품 의도와 최신 기준

- 얼굴: 단축키 → 200 논리 픽셀 원형 거울 → Enter로 3초 녹화 → 리뷰 → Enter 전송.
- 화면+얼굴: 둥근 프리뷰, 얼굴 PIP, 캡처 영역 확대·이동, 프리뷰와 저장 MP4 일치.
- 룸: 영상·텍스트·사진·답장·반응이 섞인 메신저 타임라인.
- 수신: 새 핑의 floating 재생, 클릭한 알림으로 같은 재생 경로 진입, Enter 재생 / Esc 닫기.
- 상주: 창 닫기는 트레이에 숨김. 명시적인 종료만 앱 종료.
- 시각 언어: Quiet Native Glass, 시스템 글꼴, 절제된 색과 그림자, 얼굴은 원형, 화면 영상은 둥근 사각형.
- 전송 성공: 거울이 사라짐. 별도 성공 토스트를 추가하지 않는다.
- 연결 실패: 기존 계정과 메시지를 보존하고 복구한다. 빈 룸과 연결 실패를 구별한다.
- 삭제: 보낸 영상·채팅의 모두에게서 삭제는 5분 이내. 받은 영상의 내 목록 숨김은 별도 권한.
- 최신 macOS: APNs 배너, live 이벤트 기반 자동 얼굴 회신, 회신 묶음 배치, 계정 전환, QR 기기 연결, 소리·외관·자동 재생 설정.

현재 제품 명세는 자동 얼굴 회신을 macOS에만 적용한다고 명시한다. 사용자의 이번 요청을 완전한 기능 이식 목표로 해석하면 Windows 자동 회신은 기존 Windows 동작의 복구가 아니라 **새 기능**이다. 카메라 사용 정책과 실행 중 표시를 별도 설계·검증해야 한다.

## 코드로 확인한 주요 차이

| 영역 | Windows 현재 상태 | 필요한 변경 / 검증 |
|---|---|---|
| 창 생명주기 | `MainWindow`가 Closing을 취소하고 Hide, `Program`은 단일 인스턴스 activation 사용 | 기초는 보존. 시작 메뉴·트레이·Alt+O·알림이 하나의 대화 화면에 모이도록 재구성하고 packaged 상태 검증 |
| 대화 진입 | MainWindow 상태 패널, HistoryWindow, RoomManagerWindow로 분산 | 대화 목록·타임라인·입력창을 주 화면으로 통합, 룸 관리는 보조 작업 |
| 수신 자동 재생 | `HandleIncomingMessageAsync`는 알림과 열린 룸 갱신만 수행 | live 핑의 재생 준비를 별도 큐로 실행. 클릭 경로와 중복 방지 공유 |
| 수신 확인 순서 | `MarkNotifiedAsync`를 토스트 시도 전에 호출, Unavailable 반환에도 재시도 요청 없음 | 알림 실패가 전달 완료로 기록되지 않게 순서·재시도 정책 수정. 실제 누락 가능성은 재현 테스트로 확인 |
| 실시간성 | incoming/chat/열린 룸을 polling | 인증 갱신이 가능한 Realtime + 상태 보완 polling 설계. 구독 누수와 중복 방지 |
| 인증 복구 | refresh의 모든 HttpRequestException을 세션 만료로 감쌈, bootstrap 재시도는 수동 버튼 | 네트워크·408·429·5xx와 영구 토큰 거부 구별, backoff 및 연결 복구, 계정 유지 |
| 세션 파일 | 로드 실패는 null 반환, 저장은 파일을 바로 덮어씀 | 손상된 기존 세션을 새 계정으로 대체하지 않는 복구 정책, 원자 저장·백업 |
| 타임라인 | 로드 시작에 Videos/Chats/Timeline을 비우고 순차 요청 | 실패 중 기존 대화 보존, 완료된 snapshot 적용, 선택 변경 시 오래된 응답 차단 |
| 읽음 처리 | 룸 로드에서 읽음 호출, `IsViewingRoom`은 선택 ID만 확인 | 보이는 창 + 실제 foreground + 선택 룸 조건을 읽음과 알림 정리에 공유 |
| 최신 메시지 모델 | `VideoMessage`에 `is_auto_reply` 필드 없음 | 회신을 식별·표시·묶음 처리하고 카메라 회신 루프 차단 |
| 삭제 UI | 채팅 삭제는 IsMine 기준, 영상 삭제 액션의 수신자 권한 구분 부족 | 5분 경계와 송신자/수신자/제3자 구분. 서버는 최종 판단 유지 |
| screen+face 재생 | 현재 480 고정 폭, 위치 clamp | 룸 히스토리 재생의 최신 macOS 600pt·32pt 여백 계약을 Windows DIP/DPI로 이식. 수신 bubble 크기와는 별도 구분 |
| screen+face 캡처 | native ABI에는 monitor와 PIP 비율만 있음 | viewport crop·zoom·pan·record 잠금, 프리뷰/MP4 일치, 자기 창 제외 구현 |
| 디자인 | 검정 배경·색상·글자가 XAML마다 반복, 영어와 한국어 혼재 | light/dark/high contrast tokens, 한국어 기본 문구, UIA와 키보드 탐색 |
| 아이콘 | main의 Square150x150Logo는 실제 확인 결과 단색 사각형 | 기존 Ping 브랜드 원본으로 설치·시작 메뉴·트레이·작업표시줄 아이콘 통일 |
| 설정 | 닉네임·단축키·startup·저장은 있음 | macOS 계정 전환·기기 연결·알림 소리·외관·자동 재생·업데이트를 범위에 포함 |
| 설치 | EXE가 인증서와 스크립트를 묶고 MSIX/런타임을 서버에서 다운로드 | 하나의 완결된 EXE 설치물, 올바른 사용자로 MSIX 설치·비관리자 실행, 실제 진행/실패 안내 |
| 업데이트 | 문서에는 MSIX/App Installer/Store 경계, 앱 내 완성된 업데이트 UX 근거 부족 | 서명 검증·버전 비교·업데이트 후 계정/설정 유지·실패 복구를 구현하고 시험 |

주요 근거 파일:

- `windows/src/Ping.Windows.App/Bootstrap/AppCoordinator.cs`
- `windows/src/Ping.Windows.App/Notifications/NotificationController.cs`
- `windows/src/Ping.Windows.Core/Backend/SupabaseClient.cs`
- `windows/src/Ping.Windows.App/History/HistoryViewModel.cs`, `HistoryRows.cs`, `HistoryWindow.xaml.cs`
- `windows/src/Ping.Windows.Core/Models/VideoMessage.cs`
- `windows/src/Ping.Windows.App/Playback/PlaybackViewModel.cs`
- `windows/src/Ping.Windows.NativeCapture/include/PingCaptureEngine.h`
- `windows/installer/PingSetup.iss`
- `Ping/UI/Setup/SettingsScene.swift`, `Ping/UI/History/ScreenFacePlaybackWindow.swift`
- `supabase/migrations/20260910000100_auto_face_reply_on_ping.sql`
- `supabase/migrations/20260915000300_room_timeline_membership_guard.sql`
- `supabase/migrations/20260916000100_sender_delete_window.sql`

## 기존 개발의 활용 방식

[이슈 #29](https://github.com/0mininseoul/ping/issues/29)의 순서는 여전히 유효하다: 상주와 호환성 → 재생 → 캡처 → 메신저 UI → 실제 설치물 QA. #36은 이미 main에 병합돼 있으므로 중복 구현하지 않는다.

#38의 대화 중심 진입점, 실제 로고, payload 포함 설치 방향은 유용하다. 다만 오래된 분기에서 31개 파일이 바뀌었고 캡처·단축키까지 포함돼 있다. 통째 병합하면 현재 main의 수정과 충돌·회귀 위험이 있다. 각 변경을 현재 main에 맞춰 선택적으로 재구현하고 동작 테스트를 붙인다. 해당 PR은 이번 요청에서 직접 수정 대상으로 지정되지 않았으므로 분석 참고로만 취급한다.

`docs/parity/macos-reference.md`는 알림 권한 요청 금지, 클릭 전 다운로드 금지, 480 재생 크기 등 현재 macOS와 다른 기술을 담고 있다. `AGENTS.md`도 버전과 polling/KeepAlive 설명 일부가 오래됐다. 저장소의 금지·보안 규칙은 준수하되 제품 동작 기준은 최신 Swift 코드·최근 명세·SQL을 함께 읽어 확정한다.

## 구현 방식 비교

| 방식 | 장점 | 비용/위험 | 판단 |
|---|---|---|---|
| 기존 Windows UI의 소규모 보정 | 빠른 단기 수정 | 중복 화면·오래된 수신 구조가 계속 남음 | 목표 달성에 부족 |
| 네이티브 기반 재사용 + shell/UX 재구성 | 기존 capture/backend 활용, Windows 통합 유지 | coordinator 분해, 상태 계약과 실기 QA 필요 | **추천** |
| Electron/Tauri 등 전면 재작성 | 화면 공유·웹 기반 UI 제작 쉬움 | WGC/카메라/코덱/원형 투명 창/트레이/설치 재검증, 새 bridge 필요 | 현재 근거로 선택하지 않음 |

## 개발 순서와 완료 조건

1. **재현 가능한 개발 환경과 연결 안정성**: .NET 10/Windows SDK 준비, 기존 tests와 packaged build 재현, 세션 오류 분류·원자 저장·자동 재연결·대화 보존·읽음 정책 수정. 오프라인 및 sleep 복귀 후 계정과 대화 유지.
2. **수신 경로**: live/catch-up/알림 클릭 출처 구분, Realtime와 fallback polling, 재생 큐와 계정별 중복 방지, 알림 실패 복구, floating 재생·seen·회신 묶음. 두 플랫폼 교차 전송을 실제 확인.
3. **메신저 화면과 브랜드**: 단일 대화 진입점, 목록·시간·읽지 않음·메시지 방향·입력창, 이미지·답장·반응·삭제·숨김, light/dark, 실제 로고. 화면별 macOS reference 비교와 Windows screenshots.
4. **최신 캡처·계정·설정 기능**: viewport 확대·이동, 자기 제외, 자동 얼굴 회신과 카메라 ownership, 계정 전환·기기 연결, 소리·외관·자동 재생·저장·업데이트 설정. 각 subsystem은 별도 설계와 검증으로 진행.
5. **EXE와 업데이트**: x64/ARM64 signed MSIX를 묶은 EXE, dependencies·config 포함, 설치/업데이트/제거/재설치와 익명 계정 보존. 실제 장치 QA 완료 후 배포 후보 확정.

단계 1~3 통과는 안정적인 후보의 기준이다. 전체 동일 기능 완성은 단계 4~5와 전체 매트릭스가 통과한 뒤에만 주장한다. UI만 그리거나 CI만 통과한 상태를 최종 Windows 앱이라고 부르지 않는다.

## 현재 PC와 검증 제약

- OS: Windows 11 25H2, build 26200.9457. 현재 패키지 OS 조건 충족.
- .NET: runtime 6/8만 있고 SDK 없음. 이번 세션에서 로컬 .NET tests를 실행하지 못했다.
- Visual Studio Community 2022 17.9.3, C++ workload 존재, MSBuild 경로 존재.
- 설치된 Windows SDK headers: 19041/22621. 현재 앱 타깃 26100에 부족.
- Inno Setup 6 compiler는 확인한 기본 경로에 없음.
- 실제 Mac, 카메라·마이크의 동작, release signer 사용 가능 여부는 이번 분석에서 확인하지 않았다.
- 백엔드 운영 설정·키를 조회하거나 바꾸지 않았다. 테스트에 필요한 공개 설정은 기존 CI 주입 경로를 이용하고 로그에 토큰을 남기지 않는다.

## 외부 기술 근거

- [Microsoft Windows App SDK release channels](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/release-channels): 2026-09-30 조회 기준 stable 2.5.1. 저장소는 2.1.3을 고정하므로 기반 재현 뒤 별도 호환성 변경으로 업데이트를 평가한다. 무조건 다운그레이드하거나 전체 이식과 동시에 바꾸지 않는다.
- [Supabase changelog](https://supabase.com/changelog): 현재 변경을 조회했다. 이번 단계는 로컬 코드 분석이며 운영 DB migration이나 서비스 설정 변경을 하지 않는다.

## 이번 작업에서 준비한 것

저장소와 전체 원격 브랜치를 현재 폴더에 가져오고 `codex/windows-parity`를 main에서 만들었다. GitHub 릴리즈·이슈·미완료 PR·CI 로그를 분석했다. 이 분석 및 다음 단계 설계는 로컬 문서로 보존한다. 제품 코드 변경·새 EXE 제작·공개 배포는 아직 수행하지 않았다.
