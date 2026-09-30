# Windows 연결 기반 구현·검증 기록 — 2026-09-30

## 현재 판정

승인한 Windows parity 설계의 **6절 연결·상태 기반 구현**을 마쳤다. Windows/macOS 전체 기능·디자인 동등성이나 배포용 EXE 완성을 의미하지 않는다. 로컬 브랜치는 `codex/windows-parity`, 기준은 `origin/main`의 `5b21c1962de83d1e0d6c08ba8619802cbd53280b`다.

기존 WinUI 3 / .NET 10 / C++ 캡처 구조를 유지했다. macOS 코드, 운영 DB, 공개 다운로드, 패키지 identity와 버전은 변경하지 않았다. 기존 Windows 0.3.46 릴리스와 구분되는 정식 버전 번호는 배포 단계에서 올린다.

## 구현한 동작

- 네트워크·HTTP 408/429/5xx 오류는 기존 익명 계정을 만료로 취급하지 않는다. 명시적 refresh 거부와 파일 손상은 계정 복구 상태로 전환하고 자동 가입하지 않는다.
- 세션 파일은 같은 디렉터리의 임시 파일을 flush한 뒤 원자적으로 교체하며 이전 정상 파일을 `.bak`로 보존한다. 쓰기 실패 후 갱신된 토큰은 메모리에 유지하고 다음 시도에서 저장한다. 손상된 파일을 근거 없이 다른 계정으로 복구하지 않는다.
- bootstrap은 하나의 supervisor가 직렬 실행한다. 자동 재시도 간격은 1/2/5/10/30/60초, jitter와 서버 Retry-After를 반영한다. 네트워크 복구·절전 복귀·수동 재시도로 깨울 수 있다. 설정 누락과 계정 거부에는 수동 복구를 기다린다.
- 연결 후 수신 중 발생한 계정 거부도 supervisor에 전달한다. HTTP timeout은 수신 작업 전체를 종료하지 않는다. 영구 거부 시 영상·채팅 요청을 중단하고 복구 성공 시 다시 시작한다.
- 대화의 영상·채팅을 함께 가져와 현재 선택에만 적용한다. 실패 시 기존 대화·선택·답장 draft를 보존하며, 늦은 영상 응답과 늦은 방 목록이 새 선택을 덮어쓰지 않는다. 다른 방의 예전 메시지가 새 방 아래 표시되지 않는다.
- 실제 표시된 foreground 창의 선택 방만 읽음 처리한다. 알림 클릭도 같은 검사를 거친다. 자동 갱신은 UI dispatcher를 통해 바인딩된 상태를 수정한다.
- 보낸 영상·채팅 삭제는 5분까지, 받은 영상 숨김은 실제 receiver만 허용한다. 제3자의 그룹 영상 숨김은 제공하지 않는다. 열린 창에서 1초마다 메뉴 만료를 반영하고, 실행 시에도 시간을 다시 검사한다.
- 서버의 `deleted` / `hidden` / `missing` 결과를 구분한다. 서버 거부 시 메시지를 보존하고, `deleted`에서는 같은 영상 경로의 복제 행과 Storage 원본을 정리한다. Storage 정리는 best-effort이며 숨김·이미 없는 메시지에는 적용하지 않는다. 최신 `is_auto_reply` 필드도 디코딩한다.

## 검증 결과

| 검사 | 결과 |
|---|---|
| 최초 Core / App baseline | 50 / 224 통과 |
| 최종 Release Core tests | 89 통과, 실패·skip 0 |
| 최종 Release App portable tests | 241 통과, 실패·skip 0 |
| 총 테스트 | 330 통과 |
| x64 C++ Release 캡처 DLL | 빌드 성공 |
| x64 WinUI Release 앱 | 빌드 성공, 경고·오류 0 |
| x64 Release MSIX | 생성 성공, 마지막 빌드 경고·오류 0 |
| 패키지 내부 점검 | 네이티브 DLL 809,472 bytes 포함, .NET self-contained 확인 |
| `git diff --check` | 통과 |
| 독립 코드 리뷰 | Important 5건 및 UI thread 경계 지적 반영 |
| 설치한 앱의 런타임 smoke | **미실행** — 배포 서명 키·backend 설정 없음 |
| Mac 간 송수신 / 실제 캡처 / ARM64 장치 | **미확인** |

중요 실패 테스트를 먼저 재현했다: 일시적인 인증 실패, 손상 세션, 세션 저장 재시도, 대화 갱신 실패, 늦은 방 응답·방 목록, 만료된 발신 삭제, 제3자 숨김, 서버 삭제 거부, 누락 설정, HTTP timeout 후 수신, 연결 후 영구 거부, 삭제 후 Storage 정리. 시간·HTTP·RPC·UI queue를 주입하여 운영 데이터 없이 검사했다. UI queue 단위 테스트는 실제 WinUI 창 검증을 대체하지 않는다.

## 이 PC에서 재현

사용한 도구: 사용자 로컬 .NET SDK **10.0.401**, Windows SDK **10.0.26100.7705**, 기존 VS 2022 Community **17.9.3** / v143 C++ 도구. 플랫폼 target은 낮추지 않았다.

```powershell
$pingDotnet = "$env:LOCALAPPDATA\PingDevelopment\dotnet\dotnet.exe"
& $pingDotnet test windows/tests/Ping.Windows.Core.Tests -c Release --nologo
& $pingDotnet test windows/tests/Ping.Windows.App.Tests -c Release --nologo
& ./windows/scripts/build-local.ps1 -Configuration Release -Package
git diff --check
```

`build-local.ps1`은 full-framework VS MSBuild로 C++를 먼저 빌드한 다음 .NET SDK로 Core와 WinUI를 빌드한다. .NET MSBuild에서 C++ 추적 작업을 실행하면 발생하던 TypeLoadException을 피한다. 패키지는 매번 새 `windows/artifacts/local-<platform>-<guid>/`에 생성하므로 이전 결과를 최신 빌드로 오인하지 않는다. `-DotnetPath`로 별도 SDK 위치를 지정할 수 있다.

검증 MSIX:
`windows/artifacts/local-x64-e4ec364a2f2c4754804d343e04c2376c/Ping.Windows.App_0.3.46.0_x64_Test/Ping.Windows.App_0.3.46.0_x64.msix`

크기 65,319,015 bytes. **서명 없음, Supabase.json 없음**. 일반 사용자에게 설치·사용 가능한 배포물로 전달하지 않는다. 기존 인증서의 공개 `.cer`만으로 릴리스를 서명할 수 없다. 이 PC에는 기존 Publisher에 대응하는 배포 개인키가 없다. 인증서 신뢰 저장소나 사용자의 Ping 계정 파일은 수정하지 않았다.

## 이어서 진행할 제품 작업

1. 메신저 중심의 단일 셸: 방 목록·타임라인·작성 영역, macOS 디자인 토큰, 연결 배너, 트레이 동작.
2. 실시간 수신과 영상 자동 재생: 알림 중복 방지, 원형/화면 영상 플레이어, 위치·다중 모니터·DPI, catch-up 정책.
3. 캡처 crop/zoom/pan과 화면+얼굴 리뷰, 최신 macOS의 600 DIP 히스토리 재생 동작.
4. 자동 얼굴 회신, 계정·기기·QR 연결, 소리·외관·저장 설정. 자동 회신에는 fresh frame·loop 방지·카메라 busy·sleep 검증이 필요하다.
5. x64/ARM64 앱과 런타임을 포함하는 EXE 설치, 기존 signer 연속성, 정상 사용자 권한 실행, 업데이트·제거·재설치 테스트.
6. 실제 Mac/Windows 송수신과 장치 매트릭스. 프로세스가 종료된 Windows로 원격 push를 제공하려면 별도의 WNS 설계·백엔드 작업이 필요하다.

다음 단계는 위 1–2번이다. 현재 source의 UI는 아직 macOS 전체 디자인으로 바뀌지 않았고 자동 얼굴 회신·원격 push도 구현하지 않았다. 전체 목표와 수락 기준은 `2026-09-30-windows-parity-design.ko.md`에 계속 유지한다.
