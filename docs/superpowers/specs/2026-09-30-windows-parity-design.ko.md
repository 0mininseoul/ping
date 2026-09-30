# Ping Windows 이식 설계와 첫 구현 범위

작성일: 2026-09-30. 상태: 사용자 검토용 설계안. 기준 커밋: `5b21c1962de83d1e0d6c08ba8619802cbd53280b`.

관련 분석: [저장소 분석](../../windows/2026-09-30-repository-audit.ko.md).

## 1. 요청과 성공 기준

사용자는 최신 macOS Ping과 같은 UI/UX 및 기능을 Windows에서 사용하고, EXE로 설치할 수 있기를 요청했다. 기존 Windows 작업은 활용하되 더 나은 구현을 위해 재구성할 수 있다.

이를 다음과 같이 해석한다.

- 일반 사용자는 개발자 설정 파일을 작성하지 않고 설치·닉네임 설정·초대만으로 시작한다.
- 얼굴/화면+얼굴 3초 송신, 대화, 수신 floating 재생, 계정과 기기 연결, 최신 설정까지 기능 매트릭스에 포함한다.
- Mac/Windows가 같은 룸·메시지·저장 정책을 공유한다.
- 원형 얼굴, 둥근 화면 영상, 조용한 네이티브 표면, 짧은 키보드 흐름을 유지한다.
- Windows의 Alt 단축키, 트레이, notification center, 시작프로그램, DPI·모니터·접근성에 맞게 구현한다.
- 기존 익명 계정과 룸을 업데이트 과정에서 잃지 않는다.
- 실제 EXE 설치·업데이트·교차 송수신까지 확인한 뒤 완성으로 인정한다.

설계상의 기본 가정: Windows 11 24H2+, x64/ARM64 및 기존 Supabase 프로젝트를 유지한다. Windows 10 지원 확대, 이메일/소셜 로그인, 별도 서버·새 유료 서비스 도입은 이번 목표에 포함하지 않는다. Windows 자동 얼굴 회신은 macOS와 같은 최신 기능을 원하는 요청에 맞춰 목표 범위에 넣지만 현재 제품에는 없는 새 subsystem으로 분리한다.

## 2. 선택한 접근

**WinUI 3 / C# / native C++를 유지하며 shell과 UX를 재구성한다.**

단순한 XAML 보정은 중복 화면과 오래된 연결 흐름을 해결하지 못한다. 웹 런타임으로 전면 재작성하면 이미 구현된 native capture와 시스템 통합을 다시 검증해야 한다. 기존 테스트 가능한 Core·캡처를 활용하는 구조가 목적에 가장 잘 맞는다.

macOS는 참고 원본이다. Swift나 Apple 전용 API를 Windows에 흉내 낸 이름으로 포장하지 않고 Windows native 기능으로 동일한 사용자 결과를 만든다. APNs를 Windows에서 사용하는 식의 이식은 하지 않는다.

## 3. 전체 구조

최종 앱의 책임 경계는 다음과 같다. 후속 단계에서 필요한 경계를 추출하며 한 번에 전체 파일을 교체하지 않는다.

| 구성 | 책임 | 주요 입력/출력 |
|---|---|---|
| App lifetime / activation | 단일 인스턴스, tray, startup, normal/notification/invite activation, 명시적 종료 | activation → 앱 명령 |
| Session / connection | 익명 세션, 계정 선택, 갱신, 오류 분류, 복구 상태 | 활성 계정 → 유효 token/연결 상태 |
| Room / timeline store | 룸·영상·채팅·반응 snapshot, 선택·읽음 상태 | RPC/event → 대화 상태 |
| Incoming coordinator | live/catch-up 구분, 중복 방지, 알림, 재생 큐 | 메시지 + 출처 → UI side effects |
| Capture coordinator | 카메라 ownership, 얼굴·화면 캡처, viewport, 리뷰·전송 | 사용자 명령 → MP4 + 메타데이터 |
| Playback coordinator | 표시 위치·크기·그룹 배치, seen, replay·dismiss·timeout | 영상 메타데이터 + 캐시 → 재생창 |
| Account/device settings | 계정 전환, 기존 세션 이전, QR handoff, 사용자 설정 | 설정/계정 명령 → 저장 상태 |
| Release/update boundary | 패키지 identity, 서명·버전 검증, EXE, 업데이트 | 검증된 build → 설치물 |

`AppCoordinator`는 이 책임을 연결하는 얇은 composition root로 줄인다. 서비스는 UI controls를 직접 변경하지 않는다. 타이머·구독·창·카메라에는 종료 및 계정 전환 시 정리되는 owner를 둔다.

## 4. 화면과 상호작용 기준

주 화면은 룸 목록 + 선택 룸 타임라인 + 하단 입력창이다. 시작 메뉴·트레이 열기·Alt+O·채팅 알림은 동일한 창을 재사용한다. 초기 연결 상태와 오류는 대화 화면의 작은 banner로 표시한다. 최초 사용자에게만 온보딩을 보여준다.

- 목록: 룸 이름·인원·최신 활동·읽지 않음, 기본 송신 대상 표시.
- 타임라인: 날짜·시간·발신자·내/상대 메시지 방향, 원형 얼굴/둥근 화면 썸네일, 사진·답장·반응·링크 미리보기.
- 메시지 작업: 컨텍스트 메뉴로 답장·허용된 저장·삭제/숨김. 반응 버튼과 데이터 ID를 항상 노출하지 않는다.
- 입력: Enter 전송, Shift+Enter 줄바꿈, 한국어 IME 조합 중 Enter는 확정에 사용하며 전송하지 않는다.
- 캡처: Alt+P/Alt+L, Enter 녹화·리뷰 전송, Backspace 다시 촬영, Esc 취소, Tab/1~9 대상, 0/A 전체. Alt+Shift+L 빠른 전송은 기존 선택 설정을 보존한다.
- 수신: live 핑은 자동 재생 설정에 따라 floating 재생, 알림 클릭은 동일 playback 경로. Enter 재생, Esc/닫기, 종료 후 약 10초 timeout.
- 크기: 얼굴 200 DIP 원형. screen+face 히스토리 재생은 최신 macOS의 600 논리 픽셀 목표·32 여백·비율 보존을 적용한다. 캡처 preview와 incoming bubble의 크기는 각각 원본 상태 기준으로 구별한다.
- 외관: Segoe UI와 한국어 시스템 fallback, 공통 light/dark/high contrast tokens, 제한적인 Acrylic/Mica 사용, 효과 미지원 fallback.
- 접근성: UI Automation 이름, tab order, focus restoration, reduced motion, 키보드 전용 조작, 100/150/200% DPI.

모든 화면은 macOS source reference, 구현 전/후 Windows screenshots, 상태별 동작 검증을 기록한다. 실제 Mac 실행 확인 전에는 pixel parity를 보증하지 않는다.

## 5. 데이터·알림·카메라의 최종 계약

기존 RPC named arguments, `face_only`/`screen_face`, private `ping-videos`/`ping-media`, `mirror_position` 내부 camelCase, `allows_local_save`, `is_auto_reply`를 보존한다. 클라이언트에 service-role이나 APNs 비밀 키를 넣지 않는다.

Realtime는 현재 세션 token을 읽어 재인증하고 실패 시 제한된 backoff로 복구한다. polling은 상태 보완용이며 구독이 살아 있을 때 중복 작업을 만들지 않는다. 이벤트의 출처는 live / startup-catch-up / reconnect-catch-up / notification-click으로 유지한다. 오래된 메시지나 앱 시작 전 핑을 자동 재생·자동 회신하지 않는다. 알림 클릭은 나이와 관계없이 최신 서버 권한과 영상 유효성 확인 후 사용자 의도로 재생한다.

Windows 토스트와 Mac APNs는 각각 해당 플랫폼을 사용한다. Windows 프로세스가 종료된 상태의 원격 배너는 현재 존재하지 않는 Windows push 경로가 필요하다. 따라서 종료 상태 push를 최종 동일 UX의 별도 설계 항목으로 기록하고, tray polling만으로 해결됐다고 주장하지 않는다. 해당 설계는 WNS 등록·서버 routing·무료 배포 제약을 검증한 뒤 진행한다. 첫 단계와 기존 backend 계약은 그 결정에 의존하지 않는다.

재생 큐는 알림 표시와 분리한다. 느린 영상 한 개가 후속 배너·대화를 막지 않는다. 계정별 ID ledger 및 재생 중 ID 집합을 공유해 live와 클릭이 같은 영상창을 중복 생성하지 않는다. 배너 표시·재생 준비·seen은 서로 다른 상태이며 실패한 배너를 미리 성공 처리하지 않는다.

자동 얼굴 회신은 후속 별도 설계에서 macOS 규칙을 그대로 옮긴다: 실행 중 fresh live 영상, 60초, 원 발신자 한 명, `is_auto_reply`, 재회신 금지, 중복 금지, sleep/display-off/busy camera에서 건너뛰기, 비활성 녹화 indicator. shared camera owner 없이 구현하지 않는다. 기기 handoff는 현재 공유 token contract와 운영 refresh reuse 전제를 보존하며 token이나 QR payload를 진단 로그에 기록하지 않는다.

## 6. 첫 구현 범위: 연결·대화 상태 보존

첫 subsystem은 모든 후속 UI의 기반인 **세션과 연결 복구, 대화 상태 보존**이다. 전체 디자인을 한 번에 바꾸기 전에 다음 범위만 완결한다. 나머지 subsystem은 전체 전략을 이어가되 각 단계의 설계·구현·검증을 별도로 수행한다.

### 6.1 오류 분류

세션 refresh의 오류를 상태 코드 및 Auth 응답 코드로 분류한다.

- 복구 가능: 네트워크 단절, timeout, HTTP 408/429/5xx. cancellation은 오류 상태로 취급하지 않는다.
- 영구 거부: Supabase Auth가 기존 refresh token을 거부했다고 명시한 응답. HTTP status만으로 무조건 만료라고 결정하지 않는다.
- 구성 오류: 설정 파일 누락·잘못된 URL/key. 무한 자동 재시도하지 않고 구체적 설정 상태로 표시한다.
- 손상/읽기 실패: 기존 세션 파일의 JSON 오류·I/O 실패. 새로운 익명 계정으로 자동 전환하지 않고 원본 파일을 보존해 복구 안내한다.

`SupabaseSessionExpiredException`은 영구 세션 거부에만 사용한다. HTTP layer는 오류 분류에 필요한 status와 code를 제공하되 raw token, 인증 헤더, 세션 JSON을 노출하지 않는다.

### 6.2 세션 저장

기존 `%LOCALAPPDATA%\Ping\SupabaseSession.json`과 identity를 유지한다. 같은 디렉터리의 임시 파일에 쓰고 flush·close 후 원자 교체한다. 기존 정상 파일은 backup으로 보존한다. 취소나 중간 실패는 정상 저장본을 부분 JSON으로 만들지 않는다.

세션 없음과 기존 파일 읽기 실패는 별도 결과다. 새 설치에서 파일이 없을 때만 기존 anonymous signup 동작을 허용한다. 손상된 primary의 자동 backup 복원은 parse된 user ID가 명확하고 복원이 검증 가능한 경우만 허용한다. 최초 도입으로 백업이 없으면 원본 보존·명시적 복구 상태를 사용한다. 자동 계정 삭제·초기화는 없다.

### 6.3 연결 supervisor

순수 C# 상태 machine과 UI adapter를 둔다. 상태는 Connecting / Connected / Retrying / SessionRejected / ConfigurationRequired / Stopped이다. 마지막 정상 룸·프로필은 Retrying에서도 유지한다.

- 한 시점에 bootstrap 시도는 하나뿐이다.
- backoff는 1, 2, 5, 10, 30, 60초로 늘리고 최댓값 60초 및 jitter를 둔다. 서버 Retry-After가 있으면 존중한다.
- 네트워크 복구·resume 신호 또는 수동 재시도는 기존 대기를 깨우고 단일 시도를 요청한다.
- 성공 시 backoff를 초기화하고 incoming observers를 한 벌만 유지한다.
- 영구 거부·잘못된 구성은 재시도 사다리에서 빠진다.
- 앱 종료 시 delay·request·observer를 취소·정리한다.

delay·clock·bootstrap 함수는 주입해 테스트에서 실제 시간이나 운영 네트워크에 의존하지 않는다. Windows network/power events는 별도 adapter에서 수명 관리한다.

### 6.4 타임라인 snapshot과 읽음

룸 ID와 load generation을 캡처한다. 영상·채팅·반응의 새 snapshot을 준비하고 성공한 현재 generation만 UI thread에서 적용한다. 다른 룸 선택 뒤 이전 요청의 결과는 적용하지 않는다. 일시적 로드 실패는 기존 영상·텍스트·선택·답장 draft를 보존하고 연결 배너만 바꾼다.

서로 독립인 영상·채팅 fetch는 함께 요청한다. 반응·미디어 등 의존 fetch는 그 이후에 수행한다. 이미지·링크 미리보기 하나의 실패는 텍스트 snapshot 전체를 없애지 않는다.

읽음과 알림 정리는 창이 보이고 실제 foreground이며 선택 룸이 맞을 때만 실행한다. 단지 창 객체나 선택 룸 ID가 존재하는 것으로 읽음 처리하지 않는다. 계정 전환 및 종료 시 stale 결과를 적용하지 않는 계약을 유지한다.

### 6.5 최신 삭제 계약

서버와 같은 5분 삭제 window를 순수 정책으로 구현하고 시간 공급자를 주입한다. 본인이 보낸 영상·채팅은 window 안에서만 삭제 메뉴를 노출한다. 서버가 경계에서 거절하면 row를 유지하고 현재 권한을 갱신한다.

받은 영상 숨김은 receiver ID가 현재 사용자일 때만 허용한다. 룸에서 보이는 제3자의 회신 영상에는 숨김 메뉴를 표시하지 않는다. `ping_remove_video_message`의 missing/deleted/hidden 결과를 처리하고, 영상 복제 rows/Storage 정리는 서버의 shared video 계약에 맞게 처리한다. 존재하는 wrapper RPC를 무작정 삭제하거나 SQL 이름을 바꾸지 않는다.

## 7. 첫 단계 검증

| 검사 | 통과 조건 |
|---|---|
| 기존 테스트 | Core 50 / App 224 기준을 복원하고 실패 원인 분류. 관련 기존 tests 유지 |
| 인증 | 408/429/5xx/network 오류는 expired로 바뀌지 않음, 명시적 token 거부는 재시도 중단 |
| 저장 | 새 파일 없음 / 정상 / 손상 / I/O 실패 구별, 중단된 쓰기에도 정상 파일 보존 |
| 복구 | 오프라인 시작 → 온라인 복구, 한 bootstrap/observer, 종료 중 cancel, resume 복구 |
| 타임라인 | 실패 중 이전 메시지·draft 유지, 늦은 A 룸 응답이 B 룸에 표시되지 않음 |
| 읽음 | hidden/background room은 읽음 RPC·알림 정리 없음, foreground 선택 시 반영 |
| 삭제 | 5분 경계, 발신/수신/제3자, 서버 거부 후 row 유지 |
| 컴파일 | x64 packaged app + native capture DLL 빌드 통과 |
| 실제 확인 | 오프라인/온라인 및 트레이 숨김에서 계정·룸 유지. 실제 capture가 아닌 상태 검증도 packaged 앱에서 실행 |

소스 문자열 검사만으로 behavioral acceptance를 대체하지 않는다. 실패 분기에는 fake HTTP/RPC와 clock을 사용한다. SDK 준비 후 로컬 .NET tests와 실제 WinUI build를 실행한다. macOS build는 Mac이 없으므로 이 PC에서 검증됐다고 말하지 않는다.

## 8. 환경과 설치·배포 전략

이 PC는 OS 조건을 만족하지만 .NET SDK가 없고 Windows SDK 26100이 없다. 첫 단계는 .NET 10 및 적절한 MSBuild/Windows SDK 환경을 마련해 baseline을 재현하는 일로 시작한다. SDK를 핑계로 제품 target이나 기존 기능을 다운그레이드하지 않는다. 설치 도구의 관리자 권한·필요 용량 등 실제 제한이 있으면 원인을 특정한다.

최종 EXE는 x64/ARM64 MSIX와 필요한 Windows App Runtime payload, 공개 backend config, public signing certificate를 포함한다. 런타임·설정 다운로드를 일반 사용자에게 따로 요구하지 않는다. 패키지 identity와 Publisher, 기존 signer 관계는 업데이트 연속성을 위해 유지한다.

설치는 필요한 작업만 상승 권한으로 수행하고 Ping 실행은 로그인한 사용자·일반 권한에서 이루어져야 한다. 진행률과 오류는 실제 작업을 반영한다. self-signed 방식은 SmartScreen 무경고를 보장하지 못한다. 이번 작업의 기본은 기존 인증 경로이며 유료 public signing/Store 가입을 전제하지 않는다.

새 버전 검증 → 사용자 업데이트 동의 → 서명/무결성 검증 → 설치 → 기존 계정/룸/설정 재사용을 구현한다. 정상 제거와 사용자 데이터 제거는 분리한다. 기존 데이터의 삭제는 명시적으로 선택한 경우만 수행한다. CI artifact와 테스트 로그를 보존하고 실제 장치 매트릭스 통과 후 release candidate를 전달한다.

## 9. 후속 단계의 수락 기준

최종 매트릭스는 Mac→Windows, Windows→Mac, Windows→Windows에서 얼굴/화면 영상/채팅/사진/답장/반응/삭제/숨김/초대·초대 링크를 확인한다. 자동 회신에는 1:1·그룹·loop 차단·camera busy·sleep·catch-up·계정 전환을 포함한다. 설정은 저장 권한, 아카이브 30일 정리, 소리/외관, 기기 연결, 계정 전환, 업데이트 보존을 확인한다.

설치 매트릭스는 깨끗한 사용자 환경, 기존 0.3.46 업데이트, x64/ARM64, 취소·오류·재시도·제거·재설치, elevated installer 후 normal app 실행을 포함한다. ARM64 장치에서 실제 capture를 확인하지 못하면 ARM64 runtime QA는 미확인으로 남긴다.

부족한 Mac/ARM64 기기 또는 signing 권한이 전체 완성 주장에 영향을 주면 구체적으로 보고한다. 구현 완료, 빌드 완료, 실기 검증 완료를 각각 기록한다.

## 10. 이번 단계 산출물과 다음 절차

현재 산출물은 저장소 분석과 이 설계안이다. 제품 소스, backend 운영 설정, 공개 downloads는 아직 변경하지 않았다. 설계 검토 후 첫 구현 범위(6절)의 상세 실행 계획을 작성하고, 연결/상태 tests부터 구현한다. 후속 기능을 누락하지 않도록 전체 매트릭스를 같은 문서와 구현 기록에서 추적한다.
