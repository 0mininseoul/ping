# macOS 자동 시작 + 자동 복구(KeepAlive) — 설계 문서

- **작성일**: 2026-08-04
- **상태**: **구현 완료 + 실기기 검증 완료** (브랜치 `feat/macos-autostart-keepalive`). 검증 결과는 §10.
- **범위 산정 근거**: 브레인스토밍 세션에서 사용자와 확정한 결정 로그(§3).
- **초안 대비 변경**: §4.6(크래시 루프 차단)은 YAGNI로 구현하지 않음. §4.5(중복 실행 가드)는 한 번 잘라냈다가 실측에서 필수임이 확인돼 되살림. 파일 분할은 5개 → `Ping/Core/AutoStart.swift` 1개로 통합.

---

## 1. 문제와 한 줄 결론

증상: **"맥에서 잠자기 했다가 다시 열면 Ping 앱이 꺼져 있는 경우가 있다."**

> **앱이 스스로 꺼진 게 아니라 macOS가 죽였다.** 디스크 공간 회수 데몬 `com.apple.cache_delete`가 유휴/다크웨이크 구간에 Ping을 강제 종료하고 있다. 이 종료는 크래시 리포트를 남기지 않아서 흔적 없이 사라진 것처럼 보였다. 로그인 항목(`SMAppService.mainApp`)만으로는 못 막는다 — 로그인 항목은 로그인 시점에만 실행되지, 세션 도중에 죽은 앱을 되살리지 않는다. **앱 번들에 LaunchAgent를 넣고 launchd의 KeepAlive로 수명을 관리**해야 한다.

## 2. 진단 근거 (계측 결과, 추론 아님)

### 2.1 강제 종료의 직접 증거

`log show` 원문 (2026-08-04):

```
06:16:19.599  runningboardd  Received termination request from
              [osservice<com.apple.cache_delete(501)>:2299]
              on <RBSProcessBundleIdentifierPredicate "com.youngminpark.ping.Ping">
              with context <RBSTerminateContext| code:0xBADDD15C
              explanation:CacheDeleteAppContainerCaches requesting termination
                          assertion for com.youngminpark.ping.Ping
              reportType:None  maxTerminationResistance:NonInteractive>

06:16:19.628  runningboardd  [app<...ping.Ping(501)>:11759] Terminating with context: ...
06:16:19.663  runningboardd  [app<...ping.Ping(501)>:11759] terminate_with_reason() success
06:16:19.749  launchd        [gui/501/application.com.youngminpark.ping.Ping...[11759]:]
              exited with exit reason (namespace: 15 code: 0xbaddd15c)
              - OS_REASON_RUNNINGBOARD
06:16:19.776  runningboardd  Removing process: [app<...ping.Ping(501)>:11759]
```

읽는 법:

| 필드 | 값 | 의미 |
|---|---|---|
| 요청자 | `com.apple.cache_delete` | 디스크 공간 회수 데몬 |
| 이유 | `CacheDeleteAppContainerCaches` | 앱 컨테이너 캐시를 비우려고 앱을 내림 |
| 코드 | `0xBADDD15C` | cache_delete 종료 코드 ("BAD DISC") |
| `reportType` | `None` | **크래시 리포트를 생성하지 않음** → 흔적이 안 남던 이유 |
| `maxTerminationResistance` | `NonInteractive` | 창 없는 백그라운드 앱만 표적. Ping은 `LSUIElement`라 정확히 해당 |
| exit namespace | 15 (`OS_REASON_RUNNINGBOARD`) | 정상 종료가 **아님** → launchd 재실행 조건에 걸림 |

### 2.2 빈도와 환경

- **최근 24시간 동안 Ping이 4회** cache_delete에 종료됨.
- 같은 창에서 `com.apple.wallpaper.agent` 828회, `com.apple.weather` 826회. 시스템 전체가 디스크 압박 상태.
- 다른 서드파티 메뉴바 앱도 동일하게 피격: `com.kyome.RunCat`, `com.youngminpark.maccctv.mac`.
- **데이터 볼륨: 460 GiB 중 여유 6.2 GiB (99% 사용)** — cache_delete가 공격적으로 도는 근본 환경 조건.

### 2.3 별개로 발견된 실제 크래시 (본 스펙 범위 밖)

`~/Library/Logs/DiagnosticReports/`에 크래시 2건 (2026-07-29, 2026-07-31). 둘 다 동일 지점:

```
EXC_BAD_ACCESS (SIGSEGV), KERN_INVALID_ADDRESS
  → possible pointer authentication failure
Thread (triggered): com.apple.CFNetwork.LoaderQ
  libdispatch  _dispatch_source_set_runloop_timer_4CF
  CFNetwork    URLConnectionLoader::loadWithWhatToDo(...)
  CFNetwork    URLConnectionLoader::continueWithCacheLookupResult(...)
```

이미 사라진 런루프에 CFNetwork 타임아웃 타이머를 다는 전형적 패턴. **원인 규명은 별도 작업으로 분리한다**(결정 D5). 다만 본 스펙의 KeepAlive가 들어가면 이 크래시가 나도 수 초 안에 복구되므로 사용자 체감 급성도는 낮아진다.

### 2.4 현재 코드 상태

- `Ping/UI/Setup/SettingsScene.swift:321` `updateAutoLaunch(_:)` — `SMAppService.mainApp.register()/unregister()`. **기본값 OFF**, 사용자가 토글해야 등록됨.
- `Ping/Info.plist` — `LSUIElement: true`. 창 없는 메뉴바 앱.
- 수명 관리/재실행/웨이크 감지 코드 없음. `AppDelegate`에 `NSWorkspace` 슬립·웨이크 옵저버 없음.

## 3. 확정된 결정 로그

| # | 결정 | 값 |
|---|---|---|
| D1 | 복구 메커니즘 | **번들 LaunchAgent + launchd KeepAlive** (`SMAppService.agent`) |
| D2 | 기본값 | **기본 ON** + 기존 사용자 자동 마이그레이션 |
| D3 | 마이그레이션 | 기존 `mainApp` 로그인 항목은 해제하고 agent로 이관 |
| D4 | 설정 UI | **현행 유지.** 문구·레이아웃 변경 없음. 토글이 호출하는 대상만 교체 |
| D5 | CFNetwork SIGSEGV | **본 스펙 범위 밖.** 별도 작업 |
| D6 | Windows 클라이언트 | 범위 밖 |

## 4. 설계

### 4.1 LaunchAgent plist

경로: `Ping.app/Contents/Library/LaunchAgents/com.youngminpark.ping.Ping.keepalive.plist`

```xml
<key>Label</key>                     <string>com.youngminpark.ping.Ping.keepalive</string>
<key>BundleProgram</key>             <string>Contents/MacOS/Ping</string>
<key>RunAtLoad</key>                 <true/>
<key>KeepAlive</key>
  <dict><key>SuccessfulExit</key>    <false/></dict>
<key>ThrottleInterval</key>          <integer>30</integer>
<key>AssociatedBundleIdentifiers</key>
  <array><string>com.youngminpark.ping.Ping</string></array>
```

키 선택 근거:

- **`BundleProgram`** — 번들 상대 경로. `/Applications/Ping.app/...` 절대 경로를 쓰면 사용자가 앱을 다른 위치에 두거나 옮겼을 때 깨진다.
  - *검증 완료(§10)*: `launchctl print`가 `program identifier = Contents/MacOS/Ping (mode: 2)`를 출력했다. 폴백은 불필요하다.
- **`KeepAlive = { SuccessfulExit: false }`** — 이 설계의 핵심. 비정상 종료일 때만 재실행한다.
- **`ThrottleInterval: 30`** — launchd가 30초에 한 번보다 자주 띄우지 않는다. 정상 운영 중(수 시간 실행 후 사망)에는 스로틀 창이 이미 지나 즉시 재실행되고, 기동 즉시 죽는 병리 상태에서만 30초 간격이 된다.
- **`AssociatedBundleIdentifiers`** — 시스템 설정 › 로그인 항목에 raw label 대신 "Ping"으로 표시된다.

### 4.2 종료 경로별 동작

| 종료 원인 | exit 상태 | launchd 동작 |
|---|---|---|
| `cache_delete` 강제 종료 (0xBADDD15C) | 비정상 (namespace 15) | **재실행** |
| SIGSEGV 등 크래시 | 시그널 종료 | **재실행** |
| 메뉴바 "종료" (`StatusMenuBuilder.swift:31` → `NSApplication.terminate`) | `exit(0)` | 재실행 안 함 |
| Sparkle 업데이트 설치 중 종료 | `exit(0)` | launchd는 관여 안 함. Sparkle이 자체 재실행 |
| 로그아웃 / 재부팅 | — | 다음 로그인에 `RunAtLoad`로 시작 |

메뉴바 "종료"가 `exit(0)`으로 끝난다는 점이 전제다. `NSApplication.terminate` 기본 경로가 그렇고, `applicationWillTerminate`(`AppDelegate.swift:91`)는 태스크 취소·카메라 정지·구독 해제만 하므로 종료 코드를 바꾸지 않는다. 구현 시 실측으로 확인한다(§7 수동 검증).

### 4.3 빌드 통합

`project.yml`의 `Ping` 타깃에 Copy Files 빌드 페이즈를 추가한다:

```yaml
sources:
  - path: Ping
  - path: Resources/LaunchAgents/com.youngminpark.ping.Ping.keepalive.plist
    buildPhase:
      copyFiles:
        destination: wrapper
        subpath: Contents/Library/LaunchAgents
```

**코드 서명 페이즈보다 앞에 실행돼야 한다.** 서명 후에 번들 안으로 파일을 끼워 넣으면 번들 서명이 깨지고, 서명이 깨진 번들의 LaunchAgent는 SMAppService가 등록을 거부한다. XcodeGen이 생성하는 표준 빌드 페이즈 순서에서 Copy Files는 서명보다 앞이지만, 구현 후 `codesign --verify --deep --strict Ping.app`으로 확인한다.

### 4.4 등록 상태 결정 로직 — `AutoStartPolicy`

`SMAppService` 호출을 UI/AppDelegate에 흩뿌리지 않고, **순수 결정 함수**로 분리한다. 입력 세 개:

- `userChoice: Bool?` — `UserDefaults` 키 `ping.autostart.userChoice`. `nil` = 사용자가 한 번도 선택한 적 없음
- `agentStatus: SMAppService.Status` — 새 KeepAlive agent의 상태
- `mainAppStatus: SMAppService.Status` — 구 로그인 항목의 상태 (마이그레이션 판정용)

출력: `AutoStartAction` — `.registerAgent` / `.unregisterAgent` / `.migrateFromMainApp` / `.none`

| userChoice | agentStatus | mainAppStatus | 동작 |
|---|---|---|---|
| `nil` | 미등록 | 미등록 | `.registerAgent` → `userChoice = true` 저장 |
| `nil` | 미등록 | `.enabled` / `.requiresApproval` | `.migrateFromMainApp` = agent 등록 → `mainApp.unregister()` → `userChoice = true` |
| `true` | `.enabled` | — | `.none` |
| `true` | `.notFound` (앱을 옮겼거나 번들이 교체됨) | — | `.registerAgent` — 자가 치유 |
| `true` | `.requiresApproval` | — | `.none`. 사용자가 시스템 설정에서 껐다는 뜻이므로 존중 |
| `false` | 무엇이든 | — | `.unregisterAgent` |

`mainAppStatus`는 `userChoice == nil`일 때만 본다. 한 번 마이그레이션이 끝나면 `userChoice`가 채워지므로 다시 조회되지 않는다.

**`userChoice == false`를 코드가 뒤집는 경로는 없다.** 자동 마이그레이션은 `nil`일 때만 일어난다. 사용자가 껐는데 업데이트 때마다 다시 켜지면 그건 악성 동작이다.

**마이그레이션 순서는 agent 등록이 먼저다.** `mainApp`을 먼저 해제하면 `register()`가 실패했을 때 둘 다 없는 상태로 남고 복구 경로가 없다 — 자동 시작이 되던 사용자가 조용히 잃는다. 이 순서면 최악의 경우가 "둘 다 등록됨"이고, 그건 §4.5 가드가 흡수하고 다음 기동이 정리한다.

**`setEnabled`는 OS 호출보다 `userChoice` 저장이 먼저다.** 나중에 저장하면 `unregister()`가 실패했을 때 "끄겠다"는 의사가 유실되고, 다음 기동에서 정책이 여전히 켜진 상태로 판단해 영구히 켜진 채 남는다. 먼저 저장해 두면 실패해도 다음 기동에서 정책이 양방향으로 자가 치유한다.

**개발 빌드는 등록하지 않는다.** `AppInstallLocation.canUseSparkleUpdates()`가 false면(DerivedData, `.dmg` 마운트 등) `applyPolicyAtLaunch()`는 아무것도 하지 않는다. 등록하면 Xcode의 Stop(SIGKILL)이 비정상 종료로 잡혀 KeepAlive가 개발 빌드를 되살리고, DerivedData를 지우면 시스템 설정에 죽은 로그인 항목이 남는다.

### 4.5 중복 실행 가드 — `SingleInstanceGuard`

**필수 구성 요소다.** 한 번 YAGNI로 잘라냈다가 실측에서 필요성이 확인돼 되살렸다.

`SMAppService.register()`는 잡을 즉시 로드하고 `RunAtLoad`가 true라 launchd가 그 자리에서 `Contents/MacOS/Ping`을 exec한다. **즉 실행 중인 앱이 자기 자신을 등록하면 두 번째 프로세스가 뜬다** — 업데이트 후 첫 실행마다, 그리고 설정 토글을 켤 때마다. launchd의 exec는 LaunchServices를 거치지 않으므로 "LaunchServices가 중복을 막는다"는 통념은 여기 적용되지 않는다(그건 더블클릭 방향에만 맞다). 실측에서 등록 직후 `runs = 1`이 찍혀 두 번째 프로세스가 실제로 떴음이 확인됐다.

가드가 없으면 메뉴바 아이콘 2개 · realtime 구독 2벌 · 알림 2배가 된다.

`applicationWillFinishLaunching`(`AppDelegate.swift:57`)에서:

1. 같은 번들 ID의 러닝 앱을 조회한다(`NSRunningApplication`).
2. 자기 자신 말고 더 있으면 **`exit(0)`**.

`exit(0)`이어야 launchd가 비정상 종료로 보지 않는다. 0이 아니면 KeepAlive가 곧바로 다시 띄워 무한 루프가 된다.

판정은 순수 함수(`SingleInstanceGuard.shouldYield(runningPIDs:currentPID:)`)라 pid 목록만 넘겨 테스트한다. 기동 직후에만 호출되므로 "목록의 다른 pid = 나보다 먼저 뜬 인스턴스"가 성립한다.

### 4.6 크래시 루프 차단 — **구현하지 않음**

앱이 기동 즉시 죽으면 launchd가 30초마다 영원히 되살린다는 시나리오에 대비해 단명 기동을 세는 원장을 두려 했으나, **YAGNI로 잘라냈다**(사용자 지시: 최소 변경).

근거: `ThrottleInterval 30`이 재시도 주기의 하한을 주고, 시스템 설정 › 일반 › 로그인 항목이라는 OS 차원의 탈출구가 이미 있다(SMAppService agent는 여기 노출된다). 실제로 관측된 적 없는 실패에 파일 1개 + 테스트 6개 + 알림 1종 + UserDefaults 키를 붙이는 값을 하지 못한다.

실제로 크래시 루프가 관측되면 그때 추가한다. §4.5와 달리 이건 되살릴 근거가 아직 없다.

### 4.7 설정 UI — 현행 유지 (D4)

`SettingsScene.swift`의 토글 문구("로그인 시 자동 시작"), 레이아웃, 상태 텍스트 문자열은 **바꾸지 않는다.**

바꾸는 것은 배선뿐이다:

- `updateAutoLaunch(_:)` — `SMAppService.mainApp.register()/unregister()` → `AutoStartController`(agent 대상) 호출 + `ping.autostart.userChoice` 저장
- `isAutoLaunchEnabled()` / `autoLaunchStatusText()` — `SMAppService.mainApp.status` → agent status

기존 status → 문구 매핑(`.enabled` → "켜져 있음" 등)은 그대로 재사용한다.

### 4.8 컴포넌트 경계

| 유닛 | 하는 일 | 의존 |
|---|---|---|
| `AutoStartPolicy` | (userChoice, agentStatus, mainAppStatus) → action. **순수 함수, 부작용 없음** | 없음 |
| `LaunchLedger` | 단명 기동 카운트, 임계값 판정 | 주입된 시계 · 저장소 |
| `SingleInstanceGuard` | 중복 인스턴스 판정 | 주입된 러닝앱 provider |
| `AutoStartController` | 위 셋을 엮고 실제 `SMAppService`를 호출하는 유일한 지점 | ServiceManagement |

`SMAppService`를 만지는 곳을 `AutoStartController` 한 곳으로 모은다. 나머지 셋은 프레임워크 의존이 없어 전부 단위 테스트가 된다.

## 5. 변경 파일 목록

실제로 구현된 목록이다(초안의 5파일 분할은 YAGNI로 1파일로 합쳤다).

신규:

- `Resources/LaunchAgents/com.youngminpark.ping.Ping.keepalive.plist`
- `Ping/Core/AutoStart.swift` — `AutoStartStatus` · `AutoStartAction` · `AutoStartPolicy`(순수 판정) · `SingleInstanceGuard` · `AutoStartController`(`SMAppService` 호출 유일 지점)
- `PingTests/AutoStartAgentPlistTests.swift`
- `PingTests/AutoStartPolicyTests.swift`
- `PingTests/AutoStartLaunchGuardTests.swift`
- `PingTests/AutoStartSettingsWiringTests.swift`

수정:

- `project.yml` — Copy Files 빌드 페이즈 + 테스트 fixture(cp / inputFiles / outputFiles)
- `Ping/AppDelegate.swift` — `applicationWillFinishLaunching`에 중복 가드, `applicationDidFinishLaunching`에 정책 적용
- `Ping/UI/Setup/SettingsScene.swift` — 토글 배선 교체 (문구 불변)
- `Ping/Core/UserPreferences.swift` — `PingPreferenceKeys`에 `autostartUserChoice` 추가

## 6. 에러 처리

| 상황 | 처리 |
|---|---|
| `agent.register()` throw (토글) | `userChoice`는 이미 저장된 뒤다. 기존 `autoLaunchError` 문구를 그대로 표시하고, 다음 기동에서 정책이 자가 치유 |
| `agent.register()` throw (기동 시) | 조용히 로그만 남기고 `userChoice`를 저장하지 않아 다음 기동에서 재시도 |
| `mainApp.unregister()` throw | agent는 이미 등록된 상태로 남는다. 둘 다 등록된 상태는 §4.5 가드가 흡수하고, `userChoice`가 저장되지 않아 다음 기동이 해제를 재시도 |
| status `.requiresApproval` | 사용자가 시스템 설정에서 껐다는 뜻. 존중하고 아무것도 하지 않는다 (`userChoice`가 `nil`이든 `true`든 동일) |
| status `.notFound` / `.notRegistered` + `userChoice == true` | 재등록 (자가 치유) |
| status `.unknown` | 우리가 모르는 상태다. 아무것도 하지 않는다 |

## 7. 테스트

### 자동 (PingTests)

- **`AutoStartAgentPlistTests`** — 번들된 plist를 실제로 읽어 `SuccessfulExit=false` · `RunAtLoad` · `BundleProgram` 상대 경로 · Label · `ThrottleInterval`을 못박는다. 값이 틀리면 진짜로 실패한다.
- **`AutoStartPolicyTests`** — (userChoice ∈ {nil, true, false}) × (agentStatus 5종) × (mainAppStatus 5종) 전수 매핑. 못박는 것 셋: `userChoice == false`는 어떤 조합에서도 `.registerAgent`/`.migrateFromMainApp`을 내지 않는다. `userChoice != nil`이면 `mainAppStatus`가 결과를 바꾸지 않는다. **첫 실행 분기와 자가 치유 분기가 같은 `agentStatus`에 같은 판단을 내린다** — 이 대칭성 테스트가 실제로 `.unknown` 비대칭을 잡아냈다.
- **`AutoStartLaunchGuardTests`** — 러닝앱 0/1/2개일 때의 가드 판정 + `AppDelegate`가 가드와 `applyPolicyAtLaunch()`를 실제로 호출하는지 소스 계약.
- **`AutoStartSettingsWiringTests`** — 토글이 `mainApp`이 아닌 agent를 조작하는지, 화면 문구 7종이 그대로인지.

### 수동 검증 (SMAppService는 단위 테스트 불가)

**Debug 빌드로는 검증할 수 없다.** ad-hoc 서명(`TeamIdentifier=not set`)이라 `SMAppService` 등록이 실패한다. Developer ID로 서명한 Release 빌드를 `/Applications` 또는 `~/Applications`에 두고 해야 한다(`AppInstallLocation.canUseSparkleUpdates()`가 통과하는 위치여야 등록을 시도한다).

```sh
U=$(id -u)

# 1. 등록과 BundleProgram 해석 확인
launchctl print "gui/$U/com.youngminpark.ping.Ping.keepalive"
#   → program identifier = Contents/MacOS/Ping (mode: 2)

# 2. 등록 직후 인스턴스가 1개인가 (가드 동작)
#   runs = 1 이 찍히고 살아있는 프로세스는 1개여야 한다

# 3. launchd 감시 하에 올리기 (로그인 시점 재현)
launchctl kickstart "gui/$U/com.youngminpark.ping.Ping.keepalive"

# 4. 비정상 종료 → 재실행
kill -9 <launchctl print가 보여주는 pid>
#   → 30초 안에 runs 증가 + 새 pid

# 5. 정상 종료 → 미재실행
osascript -e 'tell application id "com.youngminpark.ping.Ping" to quit'
#   → last exit code = 0, runs 유지, state = not running

# 6. 원복
launchctl bootout "gui/$U/com.youngminpark.ping.Ping.keepalive"
defaults delete com.youngminpark.ping.Ping ping.autostart.userChoice
```

**주의**: launchd가 띄운 프로세스는 `argv[0]`이 상대 경로(`Contents/MacOS/Ping`)라 `pgrep -f "Ping.app/Contents/MacOS/Ping"`에 잡히지 않는다. pid는 `launchctl print`에서 읽어야 한다.

## 8. 범위 밖

- **CFNetwork SIGSEGV 크래시** (§2.3) — 별도 작업 (D5)
- **Windows 클라이언트의 동등 기능** (D6)
- **설정 UI 개선** — `.requiresApproval` 상태에서 시스템 설정을 여는 버튼 등은 넣지 않는다 (D4)
- **디스크 공간** — 근본 환경 조건이지만 제품이 손댈 영역이 아니다

## 9. 리스크와 트레이드오프

**cache_delete와의 핑퐁.** cache_delete는 캐시를 비우려고 앱을 죽이는데 우리는 수 초 뒤 되살린다. 디스크가 계속 꽉 차 있으면 이 사이클이 반복된다. 다만 실측 빈도가 24시간에 4회(약 6시간에 1회)라 무한 루프가 아니라 간헐적 재기동이다. 상주형 메뉴바 앱의 일반적 선택이며, `ThrottleInterval: 30`이 최악의 경우에도 하한을 준다. cache_delete는 종료 직후 캐시를 회수하므로 우리 재기동이 회수 자체를 무효화하지도 않는다.

**launchd 관리 하에 들어가는 것의 부작용.** 앱이 launchd 잡이 되면 사용자가 "종료"해도 시스템 설정 로그인 항목에는 계속 남는다. 이건 의도된 동작이고, 완전히 끄는 경로는 설정 토글과 시스템 설정 두 군데다.

**`BundleProgram` 불확실성 — 해소됨.** 2026-08-04 실측에서 `launchctl print`가 `program identifier = Contents/MacOS/Ping (mode: 2)`를 출력했다. 번들 상대 경로가 정상 해석된다. 폴백(`ProgramArguments` 절대 경로)은 불필요하다.

**등록 즉시 두 번째 인스턴스가 뜬다.** `SMAppService.register()`는 잡을 즉시 로드하고 `RunAtLoad`가 true라 launchd가 그 자리에서 `Contents/MacOS/Ping`을 exec한다. launchd의 exec는 LaunchServices를 거치지 않아 중복 제거가 되지 않는다. 실측에서 등록 직후 `runs = 1`이 찍혔다 — 두 번째 프로세스가 실제로 떴다는 뜻이다. §4.5의 중복 실행 가드는 이 때문에 **필수**이며, YAGNI로 잘라냈다가 되살렸다. 가드가 `exit(0)`으로 물러나므로 살아남는 프로세스는 1개다.

**등록한 세션은 launchd 감시 밖이다.** 위 결과의 부수 효과다. 가드가 물러난 뒤 잡은 `state = not running`(정상 종료라 KeepAlive가 되살리지 않음)이 되고, 계속 떠 있는 것은 사용자가 띄운 프로세스다. 그 프로세스는 launchd의 자식이 아니므로 이 세션 동안은 강제 종료돼도 되살아나지 않는다. 다음 로그인에 `RunAtLoad`로 launchd가 직접 띄우면서 감시가 시작된다.

**Sparkle 업데이트 후에도 감시 밖이다.** 같은 원리다. Sparkle은 설치 중 앱을 정상 종료(`exit(0)`)시키고 — 그래서 KeepAlive가 끼어들지 않는 것은 옳다 — LaunchServices로 재실행한다. 그 프로세스도 launchd의 자식이 아니다. 즉 업데이트 직후부터 다음 로그인까지는 보호가 적용되지 않는데, 설정 화면은 "켜져 있음"이라고 표시한다(그 문구는 *등록* 상태이지 *감시* 상태가 아니다). Ping은 Sparkle로 자주 업데이트하므로 드문 경우가 아니다. 즉시 교정하려면 실행 중인 인스턴스를 죽이고 launchd로 다시 띄워야 하는데, 그 부작용이 이득보다 크다고 판단해 받아들인다.

**수동 재실행 인스턴스도 마찬가지다.** 사용자가 메뉴바에서 "종료"하면 launchd 잡도 멈춘다(정상 종료). 그 상태에서 Ping.app을 직접 실행하면 LaunchServices가 띄운 것이라 역시 감시 대상이 아니다. 다음 로그인에 정상화된다.

**기동 시 동기 XPC 3회.** `applyPolicyAtLaunch()`가 `agent.status`, `SMAppService.mainApp.status`, 그리고 register/unregister를 메인 스레드에서 동기로 호출한다. 상대는 background-task-management 데몬이고, 이 기능이 겨냥하는 환경이 바로 디스크 압박 상태의 머신이다. 체감 지연이 보고되면 다음 런루프로 미루면 된다 — 이 호출이 완료되기를 기다리는 코드는 없다.

---

## 10. 실기기 검증 결과 (2026-08-04)

Developer ID로 서명한 Release 빌드를 `~/Applications`에 설치해 실측했다. Debug 빌드는 ad-hoc 서명(`TeamIdentifier=not set`)이라 `SMAppService` 등록이 불가능하므로 검증에 쓸 수 없다.

| 항목 | 결과 |
|---|---|
| `codesign --verify --deep --strict` | **통과.** Sparkle을 Developer ID로 재서명하는 릴리스 경로에서는 문제없다 (Debug 빌드에서만 실패) |
| LaunchAgent plist 봉인 | `Contents/_CodeSignature/CodeResources`에 해시 존재 |
| `BundleProgram` 해석 | `program identifier = Contents/MacOS/Ping (mode: 2)` — **정상** |
| 등록 시 중복 인스턴스 | `runs = 1` — 두 번째 프로세스가 실제로 떴고, 가드가 `exit(0)`으로 흡수. 살아남은 프로세스 1개 |
| `kill -9` → 재실행 | pid 50155 → 52924, `runs` 2→3. **35초 내 복구** |
| 정상 종료 → 미재실행 | `last exit code = 0`, `runs` 3 유지, `state = not running`. **되살아나지 않음** |

검증 후 `launchctl bootout`, `~/Applications/Ping.app` 삭제, `ping.autostart.userChoice` 삭제로 원복했다.

참고: launchd가 띄운 프로세스는 `argv[0]`이 상대 경로(`Contents/MacOS/Ping`)라 `pgrep -f "Ping.app/Contents/MacOS/Ping"` 같은 절대 경로 패턴에 잡히지 않는다. 운영 스크립트를 쓸 때 주의할 것.
