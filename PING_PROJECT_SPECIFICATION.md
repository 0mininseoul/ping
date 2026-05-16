# Ping — 실시간 2초 영상 메시지 macOS 앱 기획서 (v2.0)

## 📋 프로젝트 개요

### 프로젝트 이름
**Ping** — 시스템 단축키 한 번으로 즉시 2초 영상 메시지를 보내는 macOS 전용 앱.

### 초기 사용자
- 박영민 (M3 Pro Mac)
- 김나영 (M1 Pro Mac)

### 목표
- 두 사람 간의 즉석 영상 메시지로 새로운 소통 방식을 실험한다.
- MVP 검증 후 오픈소스 프로젝트로 공개 배포한다.
- 다중 파트너 관리(Setlog 스타일의 룸 생성/검색/초대)를 통해 향후 사용자 확장을 자연스럽게 지원한다.

### 핵심 컨셉
- **글로벌 단축키 `Option + P`** 한 번으로 화면에 200px 원형 거울이 떠오름.
- `Enter` 키로 정확히 2초 녹화 → Firebase에 업로드 → 상대방의 메뉴바 앱이 실시간으로 감지하여 macOS 알림 배너 표시 → 알림 클릭 시 발신자가 지정한 위치에 그대로 2초간 재생.
- 한 사용자가 여러 파트너 룸을 보유할 수 있으며, 발송 시 가장 최근 파트너가 기본 선택되고 Tab/숫자키로 빠르게 다른 파트너 또는 "전체 발송" 모드로 전환할 수 있다.

### 플랫폼 정책
- **macOS 전용 앱**입니다. iOS, iPadOS, Windows, Linux는 지원하지 않으며 향후 확장 계획도 없습니다.
- **Mac App Store 배포 계획 없음.** DMG 설치 파일로만 배포합니다.

---

## 🧱 시스템 요구사항

| 항목 | 요구사항 |
|---|---|
| 운영체제 | macOS 26 (Tahoe) 이상 |
| 아키텍처 | Apple Silicon (M1 이상) — Intel Mac 미지원 |
| 카메라 | 내장 FaceTime 카메라 (또는 외장 USB 카메라) |
| 마이크 | 내장 또는 외장 |
| 네트워크 | 인터넷 (Firebase 통신용) |

> macOS 26을 최저 요구사항으로 잡는 이유는 SwiftUI의 네이티브 `.glassEffect()` (Apple Liquid Glass material) API를 호환성 코드 없이 사용하기 위함입니다.

---

## 🎯 핵심 기능 명세

### 1. 시스템 레벨 통합

#### 글로벌 단축키
- **기본 트리거**: `Option + P` (시스템 전역)
- **구현**: `KeyboardShortcuts` Swift Package (Sindre Sorhus). Carbon API는 사용하지 않음.
- **사용자 재바인딩**: Settings → 단축키 탭에서 즉시 변경 가능 (`KeyboardShortcuts.Recorder` 컴포넌트 사용).
- **앱 샌드박스 호환**: `KeyboardShortcuts`는 sandboxed 앱에서도 동작 (별도 접근성 권한 불필요).

#### 백그라운드 실행
- **실행 형태**: 메뉴바 상주 앱 (`NSStatusItem`).
- **Dock 아이콘 표시 안 함**: `Info.plist`의 `LSUIElement = true`.
- **로그인 시 자동 시작 (선택)**: `SMAppService` API로 토글. 첫 실행 후 Settings에서 활성화.

#### 필요한 시스템 권한
| 권한 | 필수도 | 거부 시 동작 |
|---|---|---|
| 카메라 | 필수 | 송신 불가, Settings 안내 |
| 마이크 | 필수 | 음성 없는 영상으로 fallback 옵션 제공 |
| 알림 | 필수 | 수신 동작은 가능하나 배너 미표시, 메뉴바에 경고 배지 |
| 자동 시작 | 옵션 | 수동 실행 |

> 글로벌 단축키 등록에는 별도 접근성(Accessibility) 권한이 필요 없습니다. `KeyboardShortcuts`가 Carbon `RegisterEventHotKey` API를 내부적으로 사용하기 때문입니다.

### 2. 1:1 다중 파트너 모델 (Setlog 스타일)

#### 룸 개념
- 모든 메시지 송수신은 **룸(Room)** 단위로 일어남.
- 각 룸은 정확히 **두 명**의 멤버를 가짐 (1:1).
- 한 사용자는 **여러 룸**에 참여할 수 있음 (= 여러 파트너 보유).

#### 룸 만들기
1. 사용자가 룸 이름 입력 (예: "박영민 ↔ 김나영").
2. Firestore `rooms` 컬렉션에 문서 생성 — `status: "open"`, `memberUids: [본인 UID]`, `ownerUid: 본인 UID`.
3. 룸은 "내 룸" 목록에 추가되며, 상대방 가입 전까지 대기 상태.

#### 룸 찾기 (검색)
- 검색창은 **룸 이름 + 사용자 닉네임**을 동시에 prefix 검색.
- 결과는 두 그룹으로 표시:
  - 📁 **룸 결과** — `status: "open"` 인 룸만 노출. "참여 요청" 버튼.
  - 👤 **사용자 결과** — 본인 제외 모든 사용자. "초대 보내기" 버튼.
- 룸 참여: Firestore 트랜잭션으로 `memberUids` 배열에 본인 UID 추가하고 `status: "full"` 로 변경 (동시 가입 race condition 방지).

#### 초대 (사용자 검색 결과로 룸 만들기)
1. 사용자가 "김나영" 검색 → 사용자 결과 카드의 "초대 보내기" 클릭.
2. 새 룸을 자동 생성 (이름: "박영민 ↔ 김나영" 자동 제안, 수정 가능).
3. `invitations/{inviteId}` 문서 생성 (`fromUid`, `toUid`, `roomId`, `expiresAt: 7일 후`).
4. 김나영의 앱은 invitations listener로 즉시 감지 → "박영민님이 룸에 초대했습니다" 알림 배너 (수락/거부 액션 버튼 포함).
5. 수락 시 트랜잭션으로 룸의 `memberUids` 보강 + `status: "full"` + 초대 문서 삭제.

### 3. 사용자 인터페이스

#### 거울 UI (송신용)
- **형태**: 200px 지름 완벽한 원형, 메인 스크린(`NSScreen.main`)에 표시.
- **윈도우**: borderless, floating(`.floating` window level), 투명 배경, `isMovableByWindowBackground = true`.
- **초기 위치**: 마지막 사용 위치(`UserDefaults`)가 있으면 그 위치, 없으면 메인 스크린 중앙 근방 임의 위치.
- **이동**: 마우스 드래그로 자유롭게 이동. 새 위치는 즉시 저장.
- **글래스모피즘**: SwiftUI 네이티브 `.glassEffect()` (macOS 26+) 적용. 글로벌 마지막 위치 1개만 저장 (파트너별 위치 저장은 v0.2 이후).

#### 거울 UI 상태 전이
| 상태 | 시각 표현 |
|---|---|
| 대기 | 글래스 보더(투명도 60%), 카메라 실시간 프리뷰, 하단 컴팩트 파트너 칩 |
| 녹화 | 보더가 빨간색(2px)으로 전환, 우측 상단에 카운트다운 "2 / 1" (tabular numeric) |
| 업로드 | 보더가 회전하는 그라데이션으로 전환, 하단에 "전송 중…" 마이크로 텍스트 |
| 완료 | 0.3초 fade-out 후 윈도우 닫힘. **별도 안내 문구/토스트를 표시하지 않음.** |
| 실패 | 보더가 노란색으로 바뀌고 "전송 실패 — 다시 시도?" 짧은 인라인 표시. Enter로 재시도, Esc로 닫기. |

#### 파트너 선택 (송신 타겟)
- **기본 타겟**: `lastUsedRoomId`에 해당하는 룸의 파트너 1명.
- **하단 컴팩트 칩**: 거울 하단에 작은 글래스 칩으로 현재 타겟 표시 (`👤 김나영 ▾`). 호버 시 강조.
- **칩 클릭**: 드롭다운이 펼쳐지며 모든 파트너 목록 + 최상단에 "🌐 모두에게" 옵션.
- **키보드 단축키**:
  - `Tab` — 다음 파트너로 순환
  - `1`~`9` — N번째 파트너 직접 선택
  - `0` 또는 `A` — "전체 발송" 모드 (보더가 무지개 그라데이션으로 전환되어 모드 차별화)
  - `Enter` — 녹화 시작
  - `Esc` — 송신 취소 및 거울 닫기

#### 재생 UI (수신용)
- **위치**: 발신자가 지정한 정규화 좌표(0.0~1.0)를 수신자 메인 스크린에 곱하여 절대 좌표 계산. 화면 밖이면 safe area(상단 메뉴바/하단 Dock 제외 영역) 안으로 클램핑.
- **크기**: 200px 원형 (송신 시와 동일).
- **재생**: 정확히 2초 (원본 영상 그대로), 음소거 옵션 없음.
- **종료**: 재생 완료 후 fade-out, 자동 사라짐. 메시지 `status: "seen"`으로 업데이트.
- **반복 재생 불가**: 보안 및 UX 단순화 차원에서 1회성.

#### Settings 화면
macOS 표준 Settings 윈도우(`Settings` SwiftUI Scene), 5개 탭으로 구성.

| 탭 | 내용 |
|---|---|
| **일반** | 로그인 시 자동 시작 토글, 닉네임 변경, 알림 소리 선택 (기본/없음) |
| **단축키** | Ping 호출 단축키 재바인딩 (`KeyboardShortcuts.Recorder`) |
| **룸** | 내 룸 목록(테이블), 룸 나가기, 이름 변경(소유자만), 새 룸 만들기/룸 찾기 진입점 |
| **저장** | 로컬 저장 경로 표시(`~/Documents/Ping/`), Finder에서 열기 버튼, 모든 영상 로컬 저장 토글 |
| **정보** | 버전 표시(`Ping v0.1.0`), GitHub 링크, 라이선스 |

#### 메뉴바 메뉴
```
🟢 Ping
─────────────────
파트너: 김나영 (가장 최근)
온라인 ✅
─────────────────
영상 보내기      ⌥P
내 룸…
설정…           ⌘,
─────────────────
종료
```

### 4. 촬영 시스템

#### 촬영 트리거
- **키보드**: Enter 키 입력 시 즉시 녹화 시작.
- **타이머**: 정확히 2초 (`AVCaptureMovieFileOutput`의 `maxRecordedDuration`으로 보장).
- **카메라**: 시스템 기본 비디오 입력 디바이스 (전면 FaceTime 카메라 우선).

#### 영상 품질 설정
- **해상도**: 1920×1080 (`AVCaptureSession.Preset.hd1920x1080`).
- **프레임레이트**: 30fps.
- **비디오 코덱**: H.264.
- **오디오**: AAC, 44.1kHz, 스테레오.
- **컨테이너**: MP4.
- **예상 파일 크기**: 약 4~8MB (Storage 업로드 상한 20MB).

#### 촬영 중 UX
- **시각적 피드백**: 빨간 보더 + 우측 상단 카운트다운.
- **취소 불가**: 녹화 시작 후에는 중단 불가 (UX 단순화).

### 5. 전송/수신 시스템

#### 백엔드 아키텍처
- **인증**: Firebase Anonymous Authentication.
- **데이터베이스**: Cloud Firestore (실시간 listener 기반).
- **파일 저장소**: Firebase Cloud Storage.
- **푸시 알림 인프라 없음**: APNs/FCM 미사용. 메뉴바 상주 앱이 Firestore listener로 새 메시지를 감지하면 `UNUserNotificationCenter`로 로컬 알림 발생 → macOS 알림 배너는 푸시 알림과 동일하게 우측 상단에 표시.
- **Cloud Functions 없음**: 모든 로직은 클라이언트 측 + Firestore 보안 규칙으로 처리.

#### Firebase 비용
- **Spark 플랜(무료)** 안에서 모두 동작. 두 사용자 트래픽 기준 무료 한도(Firestore 50K reads/일, Storage 5GB)의 1% 미만 사용.
- 신용카드 등록 불필요. Apple Developer Program 가입 불필요.

#### Firestore 스키마
```
users/{anonymousUid}/
  nickname: "박영민"
  searchableNickname: "박영민"            # lowercase 정규화, 검색용
  rooms: ["roomId1", "roomId2", ...]      # 본인이 속한 룸 ID 목록
  lastUsedRoomId: "roomId1"               # Option+P 기본 타겟 결정
  createdAt: serverTimestamp

rooms/{roomId}/
  name: "박영민 ↔ 김나영"                  # 사용자 입력 룸 이름
  searchableName: "박영민김나영"            # lowercase, no-space, prefix 검색용
  ownerUid: "{creatorUid}"
  memberUids: ["uidA", "uidB"]             # 정확히 2명
  memberNicknames: {uidA: "박영민", uidB: "김나영"}
  status: "open" | "full"                  # open=초대 대기, full=두 명 다 참가
  createdAt: serverTimestamp

messages/{messageId}/
  roomId: "{roomId}"
  senderUid: "{uid}"
  receiverUid: "{partnerUid}"
  senderNickname: "박영민"                  # denormalized for receiver convenience
  videoUrl: "gs://.../videos/{senderUid}/{messageId}.mp4"
  durationMs: 2000
  mirrorPosition: { xRatio: 0.78, yRatio: 0.62 }   # 0.0~1.0 정규화 좌표
  status: "uploaded" | "seen"
  createdAt: serverTimestamp
  expiresAt: serverTimestamp + 24h         # Firestore TTL 정책으로 자동 삭제

invitations/{inviteId}/
  fromUid: "{senderUid}"
  toUid: "{receiverUid}"
  roomId: "{roomId}"
  fromNickname: "박영민"
  roomName: "박영민 ↔ 김나영"
  createdAt: serverTimestamp
  expiresAt: serverTimestamp + 7d          # TTL 자동 삭제
```

#### Firestore 보안 규칙
```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{db}/documents {

    // users: 검색용 read는 인증된 사용자 모두 허용, 본인만 write
    match /users/{userId} {
      allow read: if request.auth != null;
      allow write: if request.auth.uid == userId;
    }

    // rooms: 멤버이거나 open 룸은 read 가능 (검색용),
    //        owner 또는 멤버는 write 가능
    match /rooms/{roomId} {
      allow read: if request.auth != null
                  && (resource.data.status == "open"
                      || request.auth.uid in resource.data.memberUids);
      allow create: if request.auth.uid == request.resource.data.ownerUid;
      allow update: if request.auth.uid in resource.data.memberUids
                    || request.auth.uid == request.resource.data.ownerUid;
    }

    // messages: sender 또는 receiver만 read, sender만 create,
    //           receiver는 status 필드만 update 가능
    match /messages/{messageId} {
      allow read: if request.auth.uid in
                  [resource.data.senderUid, resource.data.receiverUid];
      allow create: if request.auth.uid == request.resource.data.senderUid;
      allow update: if request.auth.uid == resource.data.receiverUid
                    && request.resource.data.diff(resource.data)
                       .changedKeys().hasOnly(['status']);
    }

    // invitations: 받는 사람만 read/delete, 보내는 사람만 create
    match /invitations/{inviteId} {
      allow read, delete: if request.auth.uid == resource.data.toUid;
      allow create: if request.auth.uid == request.resource.data.fromUid;
    }
  }
}
```

#### Cloud Storage 보안 규칙
```javascript
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /videos/{senderUid}/{messageId} {
      // 업로드: 본인만, 20MB 상한
      allow write: if request.auth.uid == senderUid
                   && request.resource.size < 20 * 1024 * 1024;
      // 다운로드: 인증된 사용자 (메시지 문서 권한으로 한 번 더 게이팅)
      allow read: if request.auth != null;
    }
  }
}
```

#### 데이터 자동 삭제 (TTL/Lifecycle)
| 데이터 | 보관 기간 | 삭제 방식 |
|---|---|---|
| Storage 영상 파일 | 24시간 | Firebase Storage Lifecycle Rule (`age > 1day → delete`) |
| Firestore `messages` 문서 | 24시간 | Firestore TTL 정책 (`expiresAt` 필드) |
| Firestore `invitations` | 7일 | Firestore TTL 정책 (`expiresAt` 필드) |
| 로컬 영상 (`~/Documents/Ping/`) | 무제한 | 사용자가 직접 관리 |

> Cloud Functions 없이 Firebase 콘솔 설정만으로 자동 삭제됩니다.

#### 송신 플로우
1. Option+P → 거울 등장 → 파트너 선택 → Enter.
2. 2초 녹화 → 로컬 임시 파일 (`~/Documents/Ping/sent/{timestamp}_to_{nickname}.mp4`) 저장.
3. Firebase Storage에 영상 업로드 (`videos/{myUid}/{messageId}.mp4`).
4. 업로드 완료 시 Firestore `messages` 문서 생성.
   - **단일 파트너**: 메시지 1개 생성.
   - **전체 발송**: 영상은 한 번만 업로드, 각 룸별로 `messages` 문서를 N개 생성 (Storage 중복 없음).
5. 거울 윈도우 fade-out & 닫힘. **별도 안내 문구 표시 없음.**

#### 수신 플로우
1. 메뉴바 앱이 항상 실행 중 → Firestore `messages` 컬렉션에 본인이 `receiverUid` 인 문서 listener 등록 (`status == "uploaded"`).
2. 새 문서 도착 → `UNUserNotificationCenter`로 로컬 알림 발생.
   - 제목: "{senderNickname}님이 영상을 보냈습니다"
   - 액션: "보기"
3. 알림 클릭 또는 "보기" 액션 → 영상 다운로드 → 발신자의 `mirrorPosition` (정규화) → 본인 메인 스크린 좌표 변환 → safe area 클램핑.
4. 해당 위치에 200px 원형 재생 윈도우 fade-in → 2초 재생 → fade-out.
5. 메시지 `status: "seen"` 업데이트.
6. 받은 영상은 `~/Documents/Ping/received/{timestamp}_from_{nickname}.mp4` 에 자동 저장.

#### 오프라인 시나리오
- 상대방 앱이 오프라인이어도 송신자는 평소처럼 영상을 녹화/업로드.
- Firestore 문서는 그대로 존재하며, 상대방 앱이 다시 켜지는 순간 listener가 catch up하여 알림 표시.
- **별도 안내 문구는 표시하지 않음** (사용자가 의식할 필요 없는 동작).

### 6. 로컬 저장 시스템

#### 저장 위치
- **기본 경로**: `~/Documents/Ping/`
- **하위 폴더**:
  - `sent/` — 본인이 보낸 영상
  - `received/` — 본인이 받은 영상

#### 파일명 규칙
```
sent/2026-05-17_14-30-25_to_김나영.mp4
received/2026-05-17_14-32-18_from_박영민.mp4
```
- 전체 발송의 경우 `sent/2026-05-17_14-30-25_to_all.mp4` 형식으로 한 번만 저장.

#### 저장 설정
- **기본**: 모든 영상 자동 저장 (Settings에서 토글로 비활성화 가능).
- **보관 기간**: 무제한 (v0.2 이후 정책 옵션화 검토).
- **용량 모니터링**: v0.2 이후 (MVP 제외).

---

## 👥 사용자 시나리오

### 초기 설정 (첫 실행)

#### 1단계: 환영 화면
- 앱 소개 + "시작하기" 버튼.

#### 2단계: 권한 요청 (순차)
- 카메라 → 마이크 → 알림 순으로 시스템 권한 다이얼로그.
- 각 단계 거부 시 안내 + System Settings 링크 제공.

#### 3단계: 닉네임 입력
- 예: "박영민" — Firebase Anonymous Auth가 백그라운드에서 실행되어 UID 발급 후 `users/{uid}` 문서 생성.

#### 4단계: 첫 룸 만들기 또는 룸 찾기 (분기)
- **만들기**: 룸 이름 입력 → 즉시 생성, 상대방 가입 대기 상태.
- **찾기**: 검색창에 상대방 닉네임 또는 룸 이름 입력 → 결과에서 선택 → 참여 요청 또는 초대 보내기.

#### 5단계: 완료
- 메뉴바에 Ping 아이콘 등장.
- 첫 사용법 안내 토스트 ("Option+P를 눌러보세요").

### 일상적 사용

#### 영상 보내기 (단일 파트너)
1. 작업 중 Option+P 입력.
2. 거울 등장 → 하단 칩에 "김나영" 표시.
3. (선택) Enter 누르거나 다른 파트너로 전환 후 Enter.
4. 2초 녹화 → 자동 업로드 → 윈도우 닫힘.

#### 영상 보내기 (전체 발송)
1. Option+P → 거울 등장.
2. `0` 또는 `A` 키 → 보더가 무지개 그라데이션으로 전환 (전체 발송 모드).
3. Enter → 2초 녹화 → 영상 1회 업로드 후 모든 파트너에게 메시지 N개 발송.

#### 영상 받기
1. 우측 상단 알림 배너 표시.
2. 알림 클릭 → 발신자가 지정한 위치에 영상 2초간 재생.
3. 자동 닫힘. 원하면 즉시 Option+P로 답장.

#### 새 파트너 추가
1. 메뉴바 → "내 룸…" 클릭.
2. "룸 찾기" 탭 → 상대방 닉네임 검색 → "초대 보내기".
3. 상대방이 수락하면 룸이 양쪽에 추가됨.

---

## 🛠 기술 구현 세부사항

### 개발 환경
- **언어**: Swift 6.0+
- **최소 지원 OS**: macOS 26 (Tahoe)
- **개발 도구**: Claude Code CLI 또는 Codex CLI — **Xcode IDE는 선택사항**
- **빌드 도구**: Xcode Command Line Tools (`xcode-select --install`)
- **프로젝트 생성**: XcodeGen (`project.yml` → `.xcodeproj` 자동 생성)
- **의존성 관리**: Swift Package Manager
- **DMG 생성**: `create-dmg`

> Xcode IDE 없이 CLI만으로 전체 개발/빌드/서명/배포가 가능합니다. SwiftUI는 Interface Builder가 필요 없어 IDE 의존성이 매우 낮습니다.

### 핵심 프레임워크
| 프레임워크 | 용도 |
|---|---|
| SwiftUI + AppKit | UI 구현 (`NSWindow` 직접 제어 일부 포함) |
| AVFoundation | 카메라 캡처 및 비디오 인코딩 |
| KeyboardShortcuts (SPM) | 글로벌 단축키 |
| UserNotifications | macOS 로컬 알림 |
| Firebase SDK (firebase-ios-sdk) | Auth + Firestore + Storage |
| ServiceManagement (`SMAppService`) | 로그인 시 자동 시작 |

### 아키텍처 패턴
- **MVVM + ObservableObject**: 단일 `AppState`가 현재 룸/파트너/연결 상태/단축키 등록 등을 보유.
- **Async/await**: Firebase 콜백을 async wrapper로 통일.
- **NSWindow 직접 제어**: borderless + floating + drag 처리를 위해 `NSWindow` 서브클래스 + `NSHostingView`로 SwiftUI 콘텐츠 임베드.

### 폴더 구조
```
ping/
├── project.yml                  # XcodeGen 스펙
├── Package.swift                # SPM 의존성
├── Ping/
│   ├── PingApp.swift            # @main, NSApplicationDelegateAdaptor
│   ├── AppDelegate.swift        # Dock 숨김, 메뉴바 아이콘
│   ├── Core/
│   │   ├── Models.swift
│   │   ├── AppState.swift
│   │   └── ScreenCoordinates.swift
│   ├── Hotkey/HotkeyManager.swift
│   ├── Capture/
│   │   ├── CameraManager.swift
│   │   └── VideoRecorder.swift
│   ├── Backend/
│   │   ├── FirebaseClient.swift
│   │   ├── RoomService.swift
│   │   ├── MessageService.swift
│   │   └── StorageService.swift
│   ├── Notifications/LocalNotificationCenter.swift
│   └── UI/
│       ├── Glass/               # 공통 글래스모피즘 컴포넌트
│       ├── Mirror/              # MirrorWindow, MirrorView, PartnerPicker
│       ├── Playback/PlaybackWindow.swift
│       └── Setup/               # PairingView, RoomListView, SettingsScene
├── Resources/
│   ├── GoogleService-Info.plist # git ignore
│   └── Assets.xcassets/
├── Ping.entitlements
└── Info.plist
```

### Info.plist 필수 키
```xml
<key>NSCameraUsageDescription</key>
<string>Ping은 2초 영상 메시지 촬영을 위해 카메라를 사용합니다.</string>

<key>NSMicrophoneUsageDescription</key>
<string>Ping은 영상 메시지의 음성 녹음을 위해 마이크를 사용합니다.</string>

<key>LSUIElement</key>
<true/>

<key>LSMinimumSystemVersion</key>
<string>26.0</string>
```

### Entitlements (`Ping.entitlements`)
```xml
<key>com.apple.security.app-sandbox</key><true/>
<key>com.apple.security.device.camera</key><true/>
<key>com.apple.security.device.microphone</key><true/>
<key>com.apple.security.network.client</key><true/>
<key>com.apple.security.files.user-selected.read-write</key><true/>
```

---

## 🎨 UI 디자인 시스템 (Liquid Glass)

### 디자인 토큰
- **Material**: SwiftUI 네이티브 `.glassEffect()` (macOS 26+) — Apple Liquid Glass material.
- **모서리**: 거울/재생창 = 완벽한 원형, 카드/패널 = 16pt 라운드.
- **그림자**: 부드러운 ambient shadow (radius 24, opacity 0.15).
- **보더**: 1pt, white 30% opacity, 내부 highlight 1pt white 10% opacity.

### 색상 팔레트
- 메인은 macOS 시스템 컬러를 그대로 활용해 다크/라이트 모드에 자동 대응.
- 강조색(녹화/실패 상태)만 명시 정의:
  - 녹화 빨간색: `#FF3B30` (시스템 red)
  - 실패 노란색: `#FFCC00` (시스템 yellow)
  - 전체 발송 그라데이션: linear gradient (red → orange → yellow → green → blue → purple)

### 타이포그래피 (시스템 폰트)
- **폰트 패밀리**: macOS 시스템 폰트 — **SF Pro**(영문) / **Apple SD Gothic Neo**(한글) 자동 fallback. 별도 폰트 번들링 없음.
- **스케일**:

| 용도 | 크기 / weight | 사용처 |
|---|---|---|
| Display | 28 / 700 | Onboarding 헤드라인 |
| Title | 20 / 600 | 룸 카드 제목, Settings 탭 헤더 |
| Body | 14 / 500 | 본문 일반 |
| Label | 13 / 500 | 파트너 칩, 버튼 텍스트 |
| Caption | 12 / 400 | 메뉴바 메뉴 보조 정보, 마지막 활동 시간 |
| Numeric | 24 / 600 tabular | 거울 카운트다운 ("2 / 1") |

### 화면 인벤토리
| # | 화면 | 윈도우 형태 | 호출 시점 |
|---|---|---|---|
| 1 | Onboarding/Pairing | 일반 NSWindow (480×600 고정) | 최초 실행 |
| 2 | Mirror (송신) | borderless 원형 floating | Option+P |
| 3 | Playback (수신) | borderless 원형 floating | 알림 클릭 |
| 4 | Room Manager | 일반 NSWindow (600×700 고정) | 메뉴바 → "내 룸" |
| 5 | Settings | macOS 표준 Settings 윈도우 | 메뉴바 → "설정…" 또는 `⌘ ,` |
| 6 | 메뉴바 메뉴 | `NSStatusItem` 메뉴 | 메뉴바 아이콘 클릭 |

### 디자인 산출물 흐름 (Day 1)
- **frontend-design 스킬**로 글래스모피즘 디자인 시스템 HTML mockup 생성 → 색상/투명도/블러 강도/보더 두께/타이포그래피 파라미터 시각적으로 확정.
- 확정된 mockup을 기준으로 SwiftUI 공통 컴포넌트 (`GlassPanel`, `GlassButton`, `GlassChip`, `PartnerChip` 등) 작성.

---

## 📦 빌드 & 배포

### 개발 사이클
```bash
# project.yml 수정 후
$ xcodegen generate

# 디버그 빌드 + 실행
$ xcodebuild -scheme Ping -configuration Debug build
$ open ./build/Debug/Ping.app
```

### 배포 사이클 (ad-hoc 서명)
```bash
# Release 빌드
$ xcodebuild -scheme Ping -configuration Release \
             -derivedDataPath build clean build

# ad-hoc 서명 (Apple Developer 계정 없이도 가능)
$ codesign --force --deep --sign - \
           --options runtime \
           --entitlements Ping.entitlements \
           build/Build/Products/Release/Ping.app

# DMG 생성
$ create-dmg --volname "Ping Installer" \
             --window-size 500 300 \
             --icon-size 100 \
             --icon "Ping.app" 125 150 \
             --app-drop-link 375 150 \
             Ping-v0.1.0.dmg \
             build/Build/Products/Release/Ping.app
```

### 수신자 측 설치 (Gatekeeper 우회)
1. DMG 다운로드 → Ping.app을 Applications 폴더로 드래그.
2. 첫 실행: 우클릭 → "열기" → 경고 다이얼로그에서 "열기" 확인.
3. 이후 일반 실행 가능.

> 정식 코드 서명(Developer ID) + Apple Notarization은 v0.2(공개 배포 시점) 검토 사항입니다. MVP에서는 ad-hoc 서명만 사용합니다.

### 배포 채널
1. **MVP**: 직접 DMG 공유 (박영민 ↔ 김나영).
2. **v0.2 이후**: GitHub Releases 공개 + 정식 코드 서명/공증 검토.
3. **Mac App Store 배포 계획 없음.**

---

## 📅 개발 일정 (1주)

### 전제
- 단일 개발자 (Claude Code CLI 주도).
- macOS 26 Tahoe 환경, Xcode Command Line Tools 설치 완료.
- 박영민 Mac = 메인 개발기, 김나영 Mac = 통합 테스트 기기.
- Day 1에 사용자가 Firebase 콘솔에서 프로젝트 생성.

### Day 1 — 프로젝트 스캐폴딩 & 글래스 디자인 시스템
- `project.yml` 작성 → XcodeGen 으로 `.xcodeproj` 생성.
- Firebase 콘솔: 프로젝트 생성, Apple platforms 앱 등록, `GoogleService-Info.plist` 다운로드, Anonymous Auth 활성화, Firestore/Storage 활성화, TTL 정책 설정.
- SPM으로 `firebase-ios-sdk`, `KeyboardShortcuts` 추가.
- `AppDelegate`에서 `NSStatusItem` 메뉴바 아이콘 표시.
- **frontend-design 스킬**로 글래스모피즘 디자인 시스템 HTML mockup 생성 (거울/재생창/룸 카드/검색 결과/설정 패널).
- 확정된 mockup을 기준으로 SwiftUI 공통 글래스 컴포넌트 작성.

### Day 2 — 카메라 & 거울 윈도우
- `KeyboardShortcuts` 통합, Option+P 기본 바인딩.
- `MirrorWindow` (borderless, floating, transparent, 200×200, 원형 마스크).
- `CameraManager` (`AVCaptureSession` 1080p 30fps + 마이크).
- 라이브 프리뷰 → `AVCaptureVideoPreviewLayer` → `NSView` → `NSViewRepresentable` → SwiftUI 임베드, 원형 클립.
- `VideoRecorder` — 정확히 2초 녹화 → `~/Documents/Ping/sent/` 임시 저장.
- 드래그 이동 + 마지막 위치 `UserDefaults` 저장.
- 보더 상태 전이 (대기/녹화/실패).

### Day 3 — Firebase 백엔드 통합
- `FirebaseClient`: Anonymous Auth → `users/{uid}` 문서 upsert.
- `RoomService.createRoom`, `searchRooms(prefix:)`, `searchUsers(prefix:)`, `joinRoom(transaction)`, `sendInvitation`, `acceptInvitation`.
- `MessageService.send(toRoomIds:, videoURL:, mirrorPosition:)` — Storage 업로드 후 룸별 메시지 문서 N개 생성.
- `MessageService.observeIncoming()` — AsyncStream으로 새 메시지 emit.
- Firestore 보안 규칙 배포 (`firebase deploy --only firestore:rules,storage`).
- CLI 통합 테스트: 두 anonymous 세션이 같은 룸에 가입 → 메시지 1건 송수신.

### Day 4 — 송수신 end-to-end + 로컬 알림 + 재생창
- Day 2 거울 UI + Day 3 백엔드 결합: 녹화 완료 → 업로드 → message 문서 생성 → 윈도우 자동 닫힘.
- `LocalNotificationCenter`: incoming message listener가 새 문서 받으면 `UNUserNotificationCenter`로 배너 (액션 "보기").
- `PlaybackWindow`: borderless 원형 윈도우 + AVPlayerLayer + 발신자의 정규화 좌표를 본인 화면 좌표로 변환.
- 재생 완료 후 `status: "seen"` 업데이트 + 윈도우 fade-out.
- 두 Mac으로 첫 통합 smoke test.

### Day 5 — 페어링/온보딩 + 룸 매니저 + 검색
- `PairingView` 5단계 (환영 → 권한 → 닉네임 → 첫 룸 → 완료).
- `RoomListView` (NSWindow), 룸 카드 그리드, 나가기/이름 변경.
- `RoomSearchView` 탭 (룸 / 사용자), 실시간 검색 (debounce 300ms).
- `InvitationCard` + 알림 액션 (수락/거부).
- 메뉴바 메뉴 완성.

### Day 6 — 다중 파트너 송신 UI + Settings + 글래스 폴리시
- 거울 하단 컴팩트 `PartnerChip` + 클릭 시 드롭다운.
- Tab/1~9/0 키 핸들링 (`NSEvent.addLocalMonitor`).
- "전체 발송" 모드 — 무지개 그라데이션 보더 + 멀티 룸 메시지 생성.
- `SettingsScene` (SwiftUI Settings) 5탭 모두 구현.
- `SMAppService` 자동 시작 토글.
- 글래스 컴포넌트 미세 조정 (그림자, 보더 highlight, 안티에일리어싱).

### Day 7 — QA, 빌드, 서명, DMG, 마이그레이션
- 시나리오 QA 체크리스트 실행 (아래).
- 발견된 버그 우선순위 fix.
- Release 빌드 + ad-hoc `codesign` + entitlements 적용.
- `create-dmg`로 DMG 생성, 김나영 Mac에서 클린 설치 시 첫 실행 흐름 검증.
- README 1페이지 (설치 방법 + 우클릭→열기 안내).
- 두 사람이 함께 30분간 실사용 → critical bug만 fix.

---

## 🧪 Day 7 QA 체크리스트

| # | 시나리오 | 통과 기준 |
|---|---|---|
| 1 | 첫 실행 권한 거부 | 카메라 거부 시 안내 + Settings 링크 동작 |
| 2 | 룸 검색 (이름) | "박영민 ↔ 김나영" prefix 검색 1초 내 결과 |
| 3 | 룸 검색 (닉네임) | "김나영" 검색 시 사용자 결과 노출 |
| 4 | 초대 보내기/받기 | 5초 내 알림, 수락 시 양쪽에 룸 추가 |
| 5 | Option+P (포커스 다른 앱) | 거울 0.3초 내 등장 |
| 6 | 녹화 → 전송 | 7초 내 윈도우 닫힘 (녹화 2s + 업로드 ~5s) |
| 7 | 알림 클릭 → 재생 | 발신자 위치 그대로 재생, 2초 후 자동 닫힘 |
| 8 | 다른 해상도 화면 | 김나영 Mac이 다른 해상도여도 safe area 내 표시 |
| 9 | "전체 발송" 모드 | 모든 파트너에게 동시 도착 |
| 10 | Settings 단축키 변경 | `Cmd+Shift+P` 등으로 변경 시 즉시 반영 |
| 11 | 자동 시작 토글 | 재로그인 후 자동 실행 |
| 12 | 오프라인 송신 | 상대방 앱이 켜진 순간 listener가 즉시 catch up |
| 13 | DMG 클린 설치 | 우클릭→열기 후 정상 동작 |
| 14 | 송신 완료 안내 부재 | 윈도우만 닫히고 별도 토스트/문구 미표시 |

---

## ⚠️ 리스크 & 대응

| 리스크 | 영향 | 대응 |
|---|---|---|
| AVFoundation 원형 프리뷰가 무겁거나 깜빡임 | 거울 UX 손상 | Day 2에 prototype, 안 되면 CALayer mask로 fallback |
| `.glassEffect()` macOS 26 API 변경/버그 | UI 깨짐 | Day 1 mockup 단계에서 검증 |
| Firestore listener 첫 연결 지연 | 알림 늦음 | 앱 시작 직후 warm-up query |
| Anonymous Auth UID 변경 (앱 재설치) | 룸 멤버십 잃음 | UID를 Keychain에 백업 + 첫 실행 시 복원 |
| 두 Mac 시계 차이 | timestamp 정렬 깨짐 | Firestore serverTimestamp 사용 |
| Sandbox + 글로벌 단축키 충돌 | 일부 단축키 등록 실패 | Option+P 유지, Settings 재바인딩 안내 |

---

## 🔒 보안 및 프라이버시

### 데이터 보호
- 전송 암호화: Firebase 기본 TLS.
- 서버 영상은 24시간 후 자동 삭제 (Storage Lifecycle + Firestore TTL).
- 로컬 영상은 사용자 디바이스에서만 영구 저장.
- Firebase 보안 규칙으로 송신자/수신자만 메시지 접근.
- 검색은 닉네임/룸 이름 prefix만 허용 — 전체 사용자 디렉터리 노출 X.

### 프라이버시 원칙
- `GoogleService-Info.plist`는 `.gitignore` 등록 (사용자별 다운로드).
- 데이터 수집 최소화: 영상 + 기본 메타데이터만 처리.
- 제3자 공유 금지.
- 녹화 중 시각적 신호(빨간 보더 + 카운트다운)로 누가 보더라도 녹화 중임을 인지 가능.

---

## 🚀 향후 로드맵 (v0.2+)

| 항목 | 내용 |
|---|---|
| 정식 코드 서명 + Notarization | Apple Developer Program 가입 후 Developer ID로 서명 |
| GitHub Releases 공개 배포 | 오픈소스 첫 공개 버전 |
| 거울 위치 파트너별 저장 | 룸마다 다른 기본 위치 기억 |
| 다중 모니터 정밀 처리 | 마우스 커서가 있는 모니터에 거울 표시 |
| Settings 고급 옵션 | 영상 보관 기간, 용량 모니터링, 자동 정리 |
| 영상 품질 옵션 | 720p/1080p 선택, 비트레이트 조정 |
| 그룹 룸 | 3명 이상 1:N 룸 지원 |
| 간단한 반응(emoji) | 받은 영상에 emoji 반응 회신 |
| 이펙트/필터 | 간단한 비디오 필터 또는 AR 이펙트 |

---

## 📚 참고 문서 및 리소스

### Apple
- [AVFoundation Programming Guide](https://developer.apple.com/documentation/avfoundation)
- [User Notifications Framework](https://developer.apple.com/documentation/usernotifications)
- [App Sandboxing Guide](https://developer.apple.com/documentation/security/app_sandbox)
- [ServiceManagement (`SMAppService`)](https://developer.apple.com/documentation/servicemanagement)
- [SwiftUI Liquid Glass (`.glassEffect()`)](https://developer.apple.com/documentation/swiftui)

### Firebase
- [Firebase Apple Platforms Setup](https://firebase.google.com/docs/ios/setup)
- [Firestore iOS Guide](https://firebase.google.com/docs/firestore/quickstart)
- [Cloud Storage iOS Guide](https://firebase.google.com/docs/storage/ios/start)
- [Firestore Security Rules](https://firebase.google.com/docs/firestore/security/get-started)
- [Firestore TTL Policies](https://firebase.google.com/docs/firestore/ttl)

### 오픈소스
- [KeyboardShortcuts (Sindre Sorhus)](https://github.com/sindresorhus/KeyboardShortcuts)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- [create-dmg](https://github.com/create-dmg/create-dmg)

### 디자인
- [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)
- [macOS Design Principles](https://developer.apple.com/design/human-interface-guidelines/macos)

---

**문서 버전**: 2.0
**작성일**: 2026-05-17
**최종 수정일**: 2026-05-17
**상태**: 설계 합의 완료, 구현 플랜 작성 중
