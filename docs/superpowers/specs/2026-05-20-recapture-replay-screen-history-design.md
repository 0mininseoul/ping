# 다시 찍기 · 다시 재생 · 화면 캡쳐 · 룸 히스토리 — 디자인 명세

- **작성일**: 2026-05-20
- **상태**: 브레인스토밍 완결, 구현 계획 작성 대기
- **버전**: v0.2 (PING_PROJECT_SPECIFICATION.md v2.2 위에 누적)

## 0. 배경

현재 Ping(v0.1.4)은 다음 약점을 가진다.

- **컨텐츠 monotony** — 2초 얼굴 셀카만. 반복 사용 시 빠른 fatigue.
- **휘발성** — 24시간 후 서버 삭제, 회상 자산이 누적되지 않음.
- **단방향 단발** — receiver의 자연스러운 답장 흐름이 부족함.
- **모바일 부재** — Mac에서 끝나, 외부 바이럴 루프가 없음.
- **컨텍스트 부재** — "왜 보냈는지" 단서가 없음.

이번 v0.2 업데이트는 위 약점 중 3개를 풀고, 동시에 Ping의 강점 — spatial overlay, instant Option+P, Liquid Glass — 을 보존한다. 단순 setlog 클론이 아니라 "spatial Ping + setlog의 장점 흡수" 방향이다.

네 개 spec으로 나눈다.

| Spec | 범위 | 푸는 약점 |
|---|---|---|
| **A** | 다시 찍기 + 다시 재생 UX 재설계 | 결정성 보강 (raw 보존) |
| **B** | 전체화면+얼굴 PIP 캡쳐 모드 + 받는쪽 Space 확대 | 컨텐츠 monotony |
| **C** | 룸 히스토리 피드 (30일 보관) | 휘발성, 회상 자산 |
| **D** | 메뉴바 정리 (파트너 제거) + 응답성 개선 | 체감 품질 |

본 문서는 이 네 spec의 디자인을 단일 진실 출처로 정리한다. 후속 spec (모바일 export, 데일리 컴파일, 실시간 챗 등)은 별도 브레인스토밍 세션 대상이다.

---

## Spec A — 다시 찍기 + 다시 재생

### A1. 송신측 상태 머신

기존:
```
idle → recording → uploading → close
       ↘ failed
```

신규:
```
idle → recording → reviewing → uploading → close
       ↘ failed       ↕
                  (Backspace로 recording 재진입)
```

`MirrorViewModel.State`에 `reviewing` 케이스 추가.

| 상태 | 트리거 | 동작 |
|---|---|---|
| idle | Option+P, 또는 reviewing/failed에서 reset | 카메라 라이브 프리뷰, 파트너 칩 표시 |
| recording | Enter | 카메라 캡쳐 시작, 카운트다운 2 → 1 |
| reviewing | recording 2초 완료 | 캡쳐 클립 mute 무한 루프, 키 입력 대기 |
| uploading | reviewing에서 Enter | 업로드 진행, 회전 보더 |
| failed | 카메라/업로드 오류 | 노란 보더 + 인라인 에러 문구, Enter로 재시도 |

### A2. 키 매핑 (reviewing 상태)

| 키 | 동작 |
|---|---|
| Enter | uploading 전이, 업로드 시작 |
| Backspace (keyCode 51) | 임시 파일 삭제 후 즉시 recording 재진입 |
| Esc | 임시 파일 삭제, 윈도우 닫기 |

다시 찍기 횟수 무제한 — 사용자가 만족할 때까지.

### A3. reviewing 상태 시각 표현

| 요소 | 처리 |
|---|---|
| Outer 보더 | `Color.white.opacity(0.30)` 1pt (idle과 동일, 안정감) |
| 카메라 프리뷰 | hidden. 그 자리에 캡쳐 클립 mute 무한 루프 재생 |
| 우상단 hint | 작은 capsule "↵ 보내기 · ⌫ 다시" 표시 2초 후 fade-out (한국어 문구 유지) |
| 하단 | PartnerPicker 유지. reviewing 중에도 파트너 변경 가능 |
| Audio | reviewing 중 muted (반복 루프 사운드 노이즈 방지). 보내고 받는 쪽에선 정상 재생 |

### A4. 업로드 타이밍

**Enter 직후에만 업로드 시작.** reviewing 동안 prefetch 업로드는 하지 않는다. 다시 찍기 시 서버에 garbage 파일 잔존 방지 + 코드 단순성.

### A5. 다시 찍기 동작

Backspace 입력 시:
1. `viewModel.state = .recording`, `viewModel.countdown = 2`
2. `try? FileManager.default.removeItem(at: previousURL)` (이전 임시 파일 즉시 삭제)
3. `AVCaptureMovieFileOutput.startRecording`을 다시 호출
4. 카운트다운 1초 후 1로, 2초 후 자동 정지 → reviewing 재진입

### A6. 수신측 상태 머신

기존: 자동 재생 → end notification → `fadeOutAndClose` → markSeen.

신규:
```
playing → paused-on-last-frame → (key wait, 10s timeout) → fadeout/close
              ↕
           Enter로 playing 재진입
              ↓
           Esc로 fadeout/close
```

상세:
- `AVPlayerItemDidPlayToEndTime`에서 `fadeOutAndClose` 직접 호출 제거.
- 대신 player를 paused 상태로 두고 (마지막 프레임이 자동 freeze), `markSeen()`를 이 시점에 호출.
- 10초 타이머 시작. 키 입력 없으면 `fadeOutAndClose`.
- 키 입력:
  - **Enter** → 타이머 reset, `player.seek(to: .zero)` + `player.play()`. 끝나면 다시 paused-on-last-frame + 새 10초 타이머.
  - **Esc** → 즉시 `fadeOutAndClose`.
- 다시 재생 횟수 무제한. 두 번째 이후 재생에서도 markSeen은 다시 안 부른다.

### A7. paused-on-last-frame 시각 표현

| 요소 | 처리 |
|---|---|
| Outer 보더 | `Color.white.opacity(0.30)` 1pt (idle과 동일) |
| 우상단 hint | 작은 capsule "↵ 다시 · esc 닫기" 표시 2초 후 fade-out |
| 10초 잔여 시각화 | 없음 (시각 노이즈 방지) |

### A8. PlaybackWindow 키 모니터

현재 `PlaybackWindow`는 `ignoresMouseEvents = true`고 키 모니터가 없다. 변경:
- `ignoresMouseEvents = true` 유지.
- 키 모니터는 `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` + 자기 윈도우 필터.
- `makeKeyAndOrderFront`로 key window 보장 (기존 코드 그대로).

### A9. 에러 처리

| 상황 | 처리 |
|---|---|
| 다시 찍기 도중 카메라 disconnect | `failed("카메라 끊김")` |
| 재생 중 파일 손상 | 자동 재생도 못 끝남 → markSeen 안 부름, 토스트 없이 fadeout |
| 업로드 실패 (reviewing → uploading 후) | `failed` 전이, 임시 파일 보존, Enter로 재시도 |

### A10. 테스트 전략

- `MirrorViewModel` 상태 전이 → 단위 테스트.
- `VideoRecorder`는 AVCapture 의존 → 통합 테스트.
- 키 매핑 → 수동 smoke test.

---

## Spec B — 전체화면+얼굴 PIP 캡쳐 모드

### B1. 두 가지 모드

| 모드 | 트리거 | Outer 형태 | 컨텐츠 |
|---|---|---|---|
| 얼굴 only | Option+P → `F` 토글, 또는 권한 거부 fallback | 200×200 원형 (기존) | 카메라 풀 |
| 전체화면+얼굴 (default) | Option+P (default) | 거울 위치 모니터 비율의 라운드 사각형 (16pt radius) | 모니터 전체 캡쳐 + 우하단 72×72 원형 얼굴 PIP |

전체화면 모드 박스 사이즈 규칙:
- 모니터 비율 그대로 (예: 16:9, 16:10)
- 긴 변 **480**, 짧은 변은 비율로 계산 (16:9 → 480×270, 16:10 → 480×300)
- 얼굴 PIP는 박스 안 우하단 **72×72 원형 fixed** (비례 계산 없음)

### B2. 송신 거울 라이브 프리뷰

- 배경: 거울이 위치한 모니터의 `SCStream` 라이브 프리뷰 (30fps)
- PIP: 카메라 라이브 프리뷰가 우하단 72px 원형 마스크 안
- 상단에 작은 capsule (예: "16:9 모니터") — 어느 모니터가 캡쳐될지 안내. 모니터가 하나면 생략 가능.

### B3. 모드 토글 — `F` 키

거울 안에서 `F` (keyCode 3) 입력:
- 전체화면+얼굴 → 얼굴 only로 전환: outer 박스 라운드 사각형 → 200 원형 0.25초 morph (불가능 시 cross-fade fallback)
- 얼굴 only → 전체화면+얼굴 전환: 권한 있으면 outer가 모니터 비율 라운드 사각형으로 morph. 권한 없으면 토글 무시 + 짧은 shake 애니메이션.
- 마지막 모드는 `UserPreferences`에 저장. 다음 Option+P에서 그 모드로 복원.

### B4. 녹화·합성·인코딩

기술 스택:
- `ScreenCaptureKit` `SCStream` + `SCContentFilter(display:excludingApplications:exceptingWindows:)`
- 카메라는 기존 `AVCaptureSession` 유지
- 두 stream을 `CIImage` 단계에서 PIP 합성 (화면 frame 위에 카메라 frame을 원형 mask + 우하단 위치)
- `AVAssetWriter`로 H.264 mp4 인코딩 (긴 변 720으로 normalize, 짧은 변 비율 유지)
- 2초 후 자동 stop

`VideoRecorder`를 두 컴포넌트로 분리:
- `FaceOnlyRecorder` (기존 `VideoRecorder` 리네임)
- `ScreenFaceRecorder` (신규)
- mode에 따라 router에서 선택

### B5. 데이터 모델 변경

`messages` 테이블에 두 컬럼 추가:
- `capture_mode` text (`face_only` / `screen_face`)
- `aspect_ratio` real (예: 16:9 = 1.778, 1:1 = 1.0)

기존 `x_ratio`/`y_ratio`는 박스 중심점 위치로 의미 일관 유지. 박스 dimension은 mode + aspect_ratio에서 derive.

마이그레이션: 두 컬럼 모두 nullable. 기존 row는 null → face_only로 해석.

### B6. 수신 spatial overlay

`PlaybackWindow` 변경:
- `capture_mode`와 `aspect_ratio`를 받아 형태 결정
- 얼굴 only면 기존 200 원형
- 전체화면+얼굴이면 모니터 비율의 라운드 사각형 (송신 거울과 동일 규칙)
- Spec A의 다시 재생 키 매핑 (Enter/Esc) **동일 적용** + **Space로 확대 토글**

### B7. 확대 모달 (받는 쪽)

- 새 borderless NSWindow, 화면 중앙
- 사이즈: 화면 짧은 변의 80%, 영상 원본 비율 유지
- 같은 `AVPlayer` 재사용 (영상 새로 로드 X, playerItem 공유)
- spatial overlay는 hidden 상태로 유지. Space 다시 누르면 spatial 복귀, 확대 모달 사라짐.
- 확대 모달 안에서도 Enter/Esc/Space 동일 동작
- hint: 우상단 작은 capsule "↵ 다시 · ␣ 작게 · esc 닫기" 2초 후 fade-out

### B8. 권한 흐름

`ScreenCaptureKit`은 macOS Screen Recording 권한 필요.

- 첫 전체화면+얼굴 모드 진입 시 권한 prompt.
- 거부 시: 거울에 노란 보더 + "화면 녹화 권한 필요" + "시스템 설정 열기" 버튼 (deeplink: `x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture`).
- 권한 영구 거부 + 전체화면 모드 시도 → 자동으로 얼굴 only 모드로 fallback (소리 없이).
- Settings에 "기본 캡쳐 모드" 라디오 추가 — 사용자가 default를 얼굴 only로도 고정 가능.

### B9. 거울 자기 자신 제외

- 송신 거울 `NSWindow.sharingType = .none`.
- `SCContentFilter`의 `excludingApplications`에 자기 PID 추가.
- 이를 통해 거울 안에 거울이 무한 반복되는 현상 방지.

### B10. 다중 모니터

- 거울이 위치한 모니터만 캡쳐 (`NSScreen.main` 대신 거울의 `screen` 사용).
- 다른 모니터 캡쳐하려면 사용자가 거울을 그 모니터로 옮긴다.
- spatial overlay의 위치 좌표 (`x_ratio`/`y_ratio`) 의미와 자연스럽게 일치.

### B11. 시스템 사운드

v1엔 마이크만 (현재와 동일). `ScreenCaptureKit`의 시스템 사운드 캡쳐는 후속 폴리시에서 옵션으로 추가.

### B12. Spec A 기능 호환

reviewing 상태 (Spec A) 동작이 Spec B 모드에서도 동일:
- 다시 찍기 (Backspace): 합성된 클립을 mute loop, Backspace로 두 stream 재캡쳐.
- 다시 재생 (Enter), 닫기 (Esc), 확대 (Space): 모두 동일.

키 패러다임 일관 → 사용자 학습 부담 0.

### B13. 에러 처리

| 상황 | 처리 |
|---|---|
| 권한 영구 거부 | 얼굴 only로 자동 fallback, Settings에서 권한 다시 요청 가능 |
| `SCStream` 시작 실패 | failed 상태, "화면 캡쳐 실패" 메시지, Enter로 재시도 |
| 권한 갑자기 회수 (런타임) | 다음 발사 시도 시 권한 재확인 + 안내 |
| 합성 실패 (`AVAssetWriter` 오류) | failed 상태, 임시 파일 정리, Enter로 재시도 |
| 캡쳐 중 모니터 disconnect | best-effort로 그 시점까지의 클립 사용, failed로 전이하지 않음 |

### B14. 호환성 / 마이그레이션

- v0.2 이전 메시지 (`capture_mode` null) → face_only로 해석, 200 원형 표시.
- v0.1.4 이하 클라이언트는 새 컬럼 무시. 영상은 face_only로 재생되어 형태 깨지지 않음.
- Sparkle 자동 업데이트로 자연 마이그레이션.

### B15. 테스트 전략

- `ScreenCaptureKit` 단위 테스트 어려움 → 통합 테스트 + 수동 smoke.
- `PIPCompositor` (합성 로직)는 두 mock buffer → 합성 output 검증 단위 테스트.
- `MirrorViewModel` 모드 전환 상태 머신 → 단위 테스트.
- 권한 흐름은 mock authorization status → 단위 테스트.

---

## Spec C — 룸 히스토리 피드

### C1. 진입점

- 메뉴바 메뉴에 "히스토리 열기" 추가.
- 글로벌 단축키 **Option+O**로 히스토리 윈도우 토글 (`KeyboardShortcuts` 패키지로 정의, Option+P와 동일 패턴).
- 표준 NSWindow (close/min/zoom 버튼 있음), borderless 아님.
- 최소 사이즈 640×480.

### C2. 윈도우 레이아웃

좌측 사이드바 (240px, 룸 list) + 우측 메인 (선택된 룸 타임라인) 2-pane.

### C3. 사이드바 (룸 list)

각 룸 row 구성요소:
- 룸 이름
- 최근 메시지 상대시각 ("3분 전", "어제")
- 안 본 카운트 배지 (있을 때만)

- 룸 list는 `last_message_at` 내림차순 (방금 활동한 룸이 위).
- 현재 활성 룸 highlight.
- 룸 클릭 = 메인이 그 룸 타임라인으로 전환.

### C4. 메인 — 타임라인

- **날짜 헤더 (sticky)**: "오늘", "어제", "5/18 (월)" 식.
- **메시지 row**: iMessage 패턴 — 보낸 건 우측 정렬, 받은 건 좌측 정렬.
- Row 구성요소:
  - 썸네일 60×60 (모드별 형태 유지 — 얼굴 only 원형 / 전체화면+얼굴 비율 라운드 사각형)
  - 발신자 닉네임 (룸 멤버 3명 이상일 때만)
  - 시각 (HH:mm)
  - 모드 아이콘 (face / screen+face)
- 호버 시 row 살짝 highlight + 우측에 액션 버튼 (저장, 삭제) fade-in.

### C5. 인라인 재생

- 메시지 클릭 → 그 row가 큰 프레임으로 expand (180×180 원형 또는 360×202 라운드 사각형, 모드 따라).
- **자동 재생, 사운드 on** (첫 받은 경험과 일치).
- 재생 끝나면 paused-on-last-frame.
- **Enter**: 다시 재생.
- **Esc**: collapse to thumbnail.
- **Space**: 확대 모달 (Spec B의 확대 모달 재사용).
- 10초 timeout으로 자동 collapse (Spec A 정책 일치).
- 다른 메시지 클릭 시 현재 expanded 자동 collapse.
- 화살표 위/아래로 row 이동, expanded 상태면 옮긴 row도 expanded.

### C6. 메시지 액션

| 액션 | 동작 |
|---|---|
| 저장 | `LocalArchive.saveReceived` 또는 `saveSent` 호출 (기존 코드 재사용) |
| 삭제 | receiver는 본인 측에서만 (`hidden_for_receiver` 플래그). sender는 양쪽 모두 삭제 (`ping_delete_message` RPC 신규) |
| 다시 보내기 | v1 skip — 후속 spec에서 검토 |

### C7. 데이터 모델 & 보관 정책

- `messages` 테이블 유지 (sender·receiver·video_path·position·status 그대로).
- 새 컬럼: `hidden_for_receiver` boolean default false.
- `ping_cleanup_expired_data()` TTL **24h → 30d** 로 변경.
- Storage 객체도 30d 보관.
- 새 RPC: `ping_room_messages(room_uuid, before_ts, limit)` — 룸별 메시지 페이징.
- 새 RPC: `ping_delete_message(message_uuid)` — sender만 호출 가능, RLS 정책으로 강제.
- 새 RPC: `ping_hide_message_for_receiver(message_uuid)` — receiver만 호출 가능.

### C8. 캐싱

- 룸 선택되면 그 룸의 **최근 7일 영상 background prefetch** (현재 `playbackPrefetchTasks` 패턴 확장).
- 스크롤하면 lazy load (page 50개씩).
- 캐시 폴더: `~/Documents/Ping/cache/<roomId>/<messageId>.mp4`.
- 30일 지난 캐시 자동 cleanup (`CleanupService` 확장).
- 캐시 폴더 총 사이즈 제한 500MB → 오래된 것부터 LRU evict.

### C9. 단축키 (히스토리 윈도우 내부)

| 키 | 동작 |
|---|---|
| Option+O | 윈도우 토글 (글로벌) |
| ↑/↓ | 메시지 행 이동 |
| Enter | 선택 메시지 재생 (또는 다시 재생) |
| Esc | 인라인 재생 collapse, 다시 누르면 윈도우 닫기 |
| Space | 확대 모달 |
| Cmd+W | 윈도우 닫기 |
| Cmd+F | 검색 (post-v1) |

### C10. UX 디테일

- 히스토리 윈도우는 LSUIElement (메뉴바 앱) 컨텍스트에서 일반 윈도우. Dock에 잠시 아이콘이 표시될 수 있다 — 정상 동작.
- 윈도우 위치는 마지막 위치 기억 (`UserPreferences`에 저장).
- 빈 룸 (메시지 없음) → 메인에 "아직 메시지가 없어요" placeholder + Option+P 안내.

### C11. 호환성

- v0.1.4 이하 메시지 (mode/aspect 컬럼 null) → face_only/200 원형으로 fallback 표시.
- 0.1.4 이하 클라이언트 사용자는 히스토리 기능이 없어 영향 없음.

### C12. 검색

v1 skip. 후속 spec에서 발신자/모드/날짜 필터 추가 검토.

### C13. 테스트 전략

- `RoomService.fetchRoomMessages` 페이징 → 단위 테스트.
- 메시지 row 호버/클릭/expand 상태 → SwiftUI snapshot 또는 수동 smoke.
- `CleanupService` 30d TTL → 단위 테스트.
- 캐시 LRU evict → 단위 테스트.

---

## Spec D — 메뉴바 정리 & 응답성 개선

이번 v0.2와 함께 묶어서 출시. 작은 작업이지만 사용자 체감 품질에 직결.

### D1. 파트너 표시 제거

룸 기반 다중 룸 사용으로 가는 v0.2에선 메뉴바의 단일 파트너 표시 의미 없음.

제거 대상:
- `StatusMenuBuilder.swift:6,15-18` — `partnerItemTag` 상수, partner 메뉴 아이템 추가 코드
- `AppDelegate.swift:670-681` — `updateMenuPartner()` 함수 자체
- 호출 지점 5곳 (`AppDelegate:129,161,634` 등) — 호출 라인 제거
- `partnerName(in:)` (`AppDelegate:312`)는 archive 파일명 등에 쓰이므로 유지

### D2. 메뉴 응답성 — 진단 후 fix

#### D2.1 가설

가장 유력한 원인은 **메인 액터 점유에 의한 menu open hop 지연**. AppDelegate의 polling task 3개 (`roomObserverTask`, `invitationObserverTask`, `incomingMessageTask`)가 모두 `@MainActor` for-await 루프에서 2초 간격 JSON decode + `appState` 변경 + `updateMenuPartner` 같은 side effect를 동기 처리. 사용자 클릭 순간이 한 cycle 진행 중이면 NSStatusItem이 메인 액터를 기다려야 함.

부수 가설:
- NSStatusItem icon이 template 아님 (`AppDelegate.swift:70` `isTemplate = false`) — 상태바 캐싱 최적화 회피, 영향 미미
- NSMenu validation pass의 target callback이 메인 액터 점유와 겹침 — 가설 1과 같은 뿌리

#### D2.2 측정 (root cause 확인)

추측 fix를 막기 위해 실측 선행:
- **Instruments Time Profiler**: Ping 실행, attach, 메뉴 5-10회 open/close. main thread sample 분포 확인. polling task가 main thread 점유 중인지 검증.
- **`os_signpost` 인스트루멘테이션**: `NSStatusItem` button action handler 직전·직후 + polling task 안에 signpost 찍어 overlap 정량 측정.

#### D2.3 해결 방향 (가설 1 기준 우선순위)

1. **해결 A — Polling을 메인 액터에서 분리 (1순위)**
   - 현재 `RoomService.observeMyRooms` 등 AsyncStream yield가 메인 액터에서 진행. 네트워크 호출과 JSON decode는 detached Task 또는 specific actor로 옮기고, 결과만 메인 액터로 hop하여 `appState` 업데이트.
   - 메인 액터 점유 비율을 cycle당 ~100ms → ~10ms 미만으로 감소 목표.

2. **해결 B — 메뉴 표시 직전 polling 일시정지 (보강)**
   - AppDelegate에 `NSMenuDelegate` 채택. `menuWillOpen(_:)`에서 polling task `cancel()`, `menuDidClose(_:)`에서 재시작.
   - 해결 A로 충분하면 skip 가능. 잔여 지연 있을 때만 적용.

3. **해결 C — Status icon template 옵션화 (선택)**
   - `isTemplate = true`로 변경 검토. 시스템 통합감 ↑ + 다크/라이트 자동 처리. 단 컬러 정체성 손실. 디자인 선호에 따라 결정.

4. **해결 D — 첫 polling cycle 늦추기 (보조)**
   - `bootstrapBackend` 완료 후 3-5초 grace period 두고 polling 시작. 앱 launch 직후 메뉴 클릭하는 사용자 패턴에 도움.

### D3. 작업 순서

1. D1 파트너 제거 — 즉시 가능, 코드 변경 작음.
2. D2.2 측정 — Instruments + signpost로 가설 1 확인.
3. D2.3 해결 A 적용 — service layer 리팩터.
4. 측정 재시행 — 개선 정량 확인.
5. 잔여 지연 있으면 해결 B 추가.

### D4. 테스트 전략

- Polling service 리팩터 후 `RoomService`/`InvitationService`/`MessageService`는 actor isolation 단위 테스트 추가.
- 메뉴 응답성은 자동화 어려움 — 측정값(signpost) before/after 비교를 PR description에 첨부.

---

## 후속 spec (이번 작업 외 큐잉)

| Spec | 범위 | 약점 푸는 부분 |
|---|---|---|
| E | 모바일 export (히스토리 영상을 웹/모바일에서 보기) | 외부 바이럴 루프 |
| F | 데일리 컴파일 (하루치 영상 자동 합성) | setlog 시그니처 |
| G | 실시간 텍스트 챗 | turn-taking 보완 |

각 후속 spec은 독립 브레인스토밍 세션에서 풀어낸다.

---

## 핵심 결정 요약

이번 v0.2의 디자인 철학:
- **결정성 보존** — 다시 찍기/재생은 도입하되 raw·즉시성·spatial overlay 가치를 유지.
- **단순성 우선** — 전체화면 캡쳐 일괄로 박스 비율 가변, 세로 panning, ultrawide PIP 비례 등 복잡도를 제거.
- **흘끔 + 확대 패러다임** — 받는 사람은 default로 작게 보고, Space로 의도해서 깊이 인지.
- **모드별 시각 분리** — 얼굴 only는 200 원형, 전체화면+얼굴은 모니터 비율 라운드 사각형. 두 모드의 시각 차이가 빠른 mental model 단서.
- **iMessage 패턴 활용** — 히스토리는 친밀한 채팅 형태로, 보낸/받은 정렬 분리.

키 매핑 일관성:
- **Enter**: 발사 / 다시 재생.
- **Backspace**: 다시 찍기 (송신측 reviewing).
- **Esc**: 닫기 (모든 컨텍스트).
- **Space**: 확대 토글 (수신측 + 히스토리).
- **F**: 모드 토글 (송신측 거울 안에서).
- **Option+O**: 히스토리 윈도우 토글 (글로벌).
