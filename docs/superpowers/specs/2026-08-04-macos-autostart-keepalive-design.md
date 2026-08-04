# macOS 자동 시작 + 자동 복구(KeepAlive) — 설계 문서

- **작성일**: 2026-08-04
- **상태**: 설계 — 구현 전. 본 문서 승인 후 writing-plans로 구현 플랜 작성.
- **범위 산정 근거**: 브레인스토밍 세션에서 사용자와 확정한 결정 로그(§3).

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
  - *구현 시 검증 필요*: `BundleProgram`이 SMAppService agent에서 기대대로 해석되는지 실제 등록 후 `launchctl print`로 확인한다. 해석에 실패하면 폴백은 `ProgramArguments` 절대 경로 + "앱은 /Applications에 있어야 함" 제약이며, 이 경우 `AppInstallLocationTests`가 다루는 설치 위치 규약과 함께 재검토한다.
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
| `nil` | 미등록 | `.enabled` / `.requiresApproval` | `.migrateFromMainApp` = `mainApp.unregister()` → agent 등록 → `userChoice = true` |
| `true` | `.enabled` | — | `.none` |
| `true` | `.notFound` (앱을 옮겼거나 번들이 교체됨) | — | `.registerAgent` — 자가 치유 |
| `true` | `.requiresApproval` | — | `.none`. 사용자가 시스템 설정에서 껐다는 뜻이므로 존중 |
| `false` | 무엇이든 | — | `.unregisterAgent` |

`mainAppStatus`는 `userChoice == nil`일 때만 본다. 한 번 마이그레이션이 끝나면 `userChoice`가 채워지므로 다시 조회되지 않는다.

**`userChoice == false`를 코드가 뒤집는 경로는 없다.** 자동 마이그레이션은 `nil`일 때만 일어난다. 사용자가 껐는데 업데이트 때마다 다시 켜지면 그건 악성 동작이다.

`mainApp` 해제와 agent 등록이 둘 다 성공해야 한다. `mainApp`을 남긴 채 agent를 등록하면 로그인 시 두 번 실행된다. 해제 실패 시 agent 등록을 진행하지 않고 다음 실행에서 재시도한다.

### 4.5 중복 실행 가드 — `SingleInstanceGuard`

launchd가 띄운 인스턴스가 떠 있는데 사용자가 Ping.app을 더블클릭하는 경우. LaunchServices가 보통 기존 인스턴스를 활성화하지만, 실패하면 메뉴바 아이콘 2개 · realtime 구독 2벌 · 알림 2배가 된다.

`applicationWillFinishLaunching`(`AppDelegate.swift:57`)에서:

1. 같은 번들 ID의 러닝 앱을 조회한다.
2. 자기 자신 말고 더 있으면 → 먼저 뜬 쪽을 `activate`하고 **`exit(0)`**.

`exit(0)`이어야 launchd가 이걸 비정상 종료로 보고 재실행하지 않는다.

러닝 앱 조회는 프로토콜(`RunningApplicationsProviding`)로 주입해 테스트 가능하게 한다.

### 4.6 크래시 루프 차단 — `LaunchLedger`

앱이 기동 즉시 죽는 상태(깨진 업데이트, 손상된 설정 파일 등)면 launchd가 30초마다 영원히 되살린다. 사용자가 끄려면 설정 UI가 필요한데 그 앱이 크래시 루프 중이다.

**"짧은 수명"만 센다:**

1. 기동 시 현재 시각을 원장(`UserDefaults` 키 `ping.autostart.launchLedger`, 타임스탬프 배열)에 append.
2. 기동 후 **60초 생존하면 원장을 비운다** — 건강한 실행은 카운터를 리셋한다.
3. 원장이 **5개**에 도달하면(= 60초를 못 넘긴 기동이 연속 5회) agent를 스스로 등록 해제하고 로컬 알림을 띄운다: 자동 시작을 껐다는 사실과 설정에서 다시 켜는 방법.

"5분 안에 5회"가 아니라 "연속 5회 단명"으로 판정하는 이유: 사용자가 수동으로 껐다 켰다 하는 정상 사용을 크래시 루프로 오판하지 않는다.

임계값·시계를 주입 가능하게 만들어 테스트한다. 기존 `NotificationLedger`(`Ping/Notifications/NotificationLedger.swift`)와 `NotificationLedgerTests`의 패턴을 따른다.

**별도 탈출구**: 시스템 설정 › 일반 › 로그인 항목에서도 끌 수 있다. SMAppService agent는 여기 노출된다.

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

신규:

- `Resources/LaunchAgents/com.youngminpark.ping.Ping.keepalive.plist`
- `Ping/Core/AutoStart/AutoStartPolicy.swift`
- `Ping/Core/AutoStart/LaunchLedger.swift`
- `Ping/Core/AutoStart/SingleInstanceGuard.swift`
- `Ping/Core/AutoStart/AutoStartController.swift`
- `PingTests/AutoStartPolicyTests.swift`
- `PingTests/LaunchLedgerTests.swift`
- `PingTests/SingleInstanceGuardTests.swift`

수정:

- `project.yml` — Copy Files 빌드 페이즈
- `Ping/AppDelegate.swift` — `applicationWillFinishLaunching`에 중복 가드, `applicationDidFinishLaunching`에 정책 적용 + 원장 기록/60초 리셋
- `Ping/UI/Setup/SettingsScene.swift` — 토글 배선 교체 (문구 불변)
- `Ping/Core/UserPreferences.swift` — `PingPreferenceKeys`에 `autostartUserChoice`, `autostartLaunchLedger` 추가

## 6. 에러 처리

| 상황 | 처리 |
|---|---|
| `agent.register()` throw | 사용자 토글로 인한 것이면 기존 `autoLaunchError` 경로로 표시(문구 그대로). 자동 마이그레이션 중이면 조용히 실패하고 `userChoice`를 저장하지 않아 다음 실행에서 재시도 |
| `mainApp.unregister()` throw | agent 등록을 진행하지 않는다. 중복 실행보다 미등록이 낫다 |
| status `.requiresApproval` | 사용자가 시스템 설정에서 껐다는 뜻. 존중하고 아무것도 하지 않는다 |
| status `.notFound` + `userChoice == true` | 재등록 (자가 치유) |
| 크래시 루프 감지 | agent 등록 해제 + 로컬 알림. `userChoice`는 `false`로 저장 |

## 7. 테스트

### 자동 (PingTests)

- **`AutoStartPolicyTests`** — (userChoice ∈ {nil, true, false}) × (agentStatus ∈ {enabled, requiresApproval, notRegistered, notFound}) × (mainAppStatus 동일 4종) 전수 매핑. 특히 두 가지를 못박는다: `userChoice == false`는 어떤 status 조합에서도 `.registerAgent`를 내지 않는다. `userChoice != nil`이면 `mainAppStatus`가 결과를 바꾸지 않는다.
- **`LaunchLedgerTests`** — 시계 주입. 단명 4회는 미발동, 5회에 발동. 중간에 60초 생존이 끼면 리셋.
- **`SingleInstanceGuardTests`** — 러닝앱 0/1/2개일 때의 판정.

### 수동 검증 (SMAppService는 단위 테스트 불가)

```sh
# 1. 등록 확인
launchctl print gui/501/com.youngminpark.ping.Ping.keepalive

# 2. 서명 무결성 (plist가 번들 서명에 포함됐는지)
codesign --verify --deep --strict /Applications/Ping.app

# 3. 비정상 종료 → 재실행되는가
kill -9 $(pgrep -f "Ping.app/Contents/MacOS/Ping")
#   → 30초 안에 새 pid로 재기동

# 4. 정상 종료 → 재실행 안 되는가
#   메뉴바 › 종료  → 재기동하지 않아야 함

# 5. cache_delete 경로 실측 (재현 가능하면)
log stream --predicate 'eventMessage CONTAINS "youngminpark.ping"' \
  | grep -i "terminat\|exited"
```

## 8. 범위 밖

- **CFNetwork SIGSEGV 크래시** (§2.3) — 별도 작업 (D5)
- **Windows 클라이언트의 동등 기능** (D6)
- **설정 UI 개선** — `.requiresApproval` 상태에서 시스템 설정을 여는 버튼 등은 넣지 않는다 (D4)
- **디스크 공간** — 근본 환경 조건이지만 제품이 손댈 영역이 아니다

## 9. 리스크와 트레이드오프

**cache_delete와의 핑퐁.** cache_delete는 캐시를 비우려고 앱을 죽이는데 우리는 수 초 뒤 되살린다. 디스크가 계속 꽉 차 있으면 이 사이클이 반복된다. 다만 실측 빈도가 24시간에 4회(약 6시간에 1회)라 무한 루프가 아니라 간헐적 재기동이다. 상주형 메뉴바 앱의 일반적 선택이며, `ThrottleInterval: 30`이 최악의 경우에도 하한을 준다. cache_delete는 종료 직후 캐시를 회수하므로 우리 재기동이 회수 자체를 무효화하지도 않는다.

**launchd 관리 하에 들어가는 것의 부작용.** 앱이 launchd 잡이 되면 사용자가 "종료"해도 시스템 설정 로그인 항목에는 계속 남는다. 이건 의도된 동작이고, 완전히 끄는 경로는 설정 토글과 시스템 설정 두 군데다.

**`BundleProgram` 불확실성.** §4.1에 적은 대로 실등록 검증이 필요하다. 실패 시 폴백 경로가 있고, 구현 플랜의 첫 단계로 배치한다.
