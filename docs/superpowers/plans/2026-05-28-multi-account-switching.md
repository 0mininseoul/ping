# 다중 계정 전환 (macOS, 오너 전용) 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** macOS Ping 앱이 한 기기에서 여러 익명 Supabase 계정을 보관하고 앱 안에서 전환하며, 전환 시 비활성 동안 밀린 알림(영상·초대·채팅)을 모아 보여준다. 활성 닉네임이 `영민`일 때만 노출된다.

**Architecture:** 다중 계정 저장소(`AccountStore` + `Accounts.json`) + 활성 세션 교체 + 옵저버 재시작. 한 번에 한 세션만 라이브. 기존 `bootstrap → startObservers` 머신을 재사용하고, 전환은 옵저버 정리 → 새 uid로 재-bootstrap → 캐치업 유입으로 처리한다. 활성 세션은 기존 `SupabaseSession.json` + UserDefaults에 계속 미러되어 구버전 다운그레이드와 토큰 갱신 경로가 그대로 동작한다.

**Tech Stack:** Swift 6 / SwiftUI / AppKit, XcodeGen(`project.yml`), Supabase Anonymous Auth(REST), `UNUserNotificationCenter`, XCTest(실 단위 테스트 + 소스-컨트랙트 테스트).

---

## 파일 구조

| 파일 | 책임 | 신규/수정 |
|---|---|---|
| `Ping/Backend/AccountStore.swift` | `StoredAccount`, `AccountsFile`(+순수 전이 함수·마이그레이션), 영속 클래스 `AccountStore`(주입 가능 디렉터리/UserDefaults, `Accounts.json` 읽기·쓰기 + 레거시 미러) | 신규 |
| `Ping/Backend/SupabaseClient.swift` | 다중 계정 발행 상태/메서드, `configureIfNeeded`/`save(session:)` 통합, 레거시 미러는 `AccountStore`로 위임. `SupabaseSession`을 internal로 공개 | 수정 |
| `Ping/Core/PingError.swift` | `accountNotFound` 에러 추가 | 수정 |
| `Ping/Notifications/NotificationLedger.swift` | 계정별 알림 dedup 원장(영상/초대/채팅, UserDefaults 키 격리 + 캡) | 신규 |
| `Ping/Core/MultiAccountGate.swift` | `영민` 게이트(기기 로컬 unlock 플래그) | 신규 |
| `Ping/Core/AccountNotifications.swift` | UI→AppDelegate 인텐트용 `Notification.Name` | 신규 |
| `Ping/Notifications/LocalNotificationCenter.swift` | 채팅 묶음 캐치업 알림 헬퍼 `notifyChatCatchUp` | 수정 |
| `Ping/AppDelegate.swift` | 계정별 ledger dedup, `reloadForActiveAccount`, 전환 가드, 채팅 캐치업, 인텐트 핸들러, 닉네임/게이트 갱신 | 수정 |
| `Ping/UI/Setup/SettingsScene.swift` | 일반 탭 "계정" 섹션(게이트 조건부): 목록/전환/추가/삭제 | 수정 |
| `PingTests/AccountsFileTests.swift` | `AccountsFile` 순수 전이 함수 단위 테스트 | 신규 |
| `PingTests/AccountStoreTests.swift` | `AccountStore` 직렬화/마이그레이션/레거시 미러(임시 디렉터리 실 IO) | 신규 |
| `PingTests/NotificationLedgerTests.swift` | 키 격리·종류 격리·캡 | 신규 |
| `PingTests/MultiAccountGateTests.swift` | 게이트 unlock/유지 | 신규 |
| `PingTests/MultiAccountSwitchingContractTests.swift` | SupabaseClient/AppDelegate/SettingsScene/LocalNotificationCenter 배선 컨트랙트 | 신규 |

### 테스트 전략 메모
- 코드베이스는 두 가지 테스트 패턴을 쓴다: ① `@testable import Ping` 실 단위 테스트(순수 로직), ② `readSourceFile(...)`로 소스 문자열을 검사하는 **컨트랙트 테스트**(네트워크/싱글턴/UI 등 단위화가 어려운 코드).
- 컨트랙트 테스트는 `PingTests` 타깃의 `postCompileScripts`가 복사한 소스 파일을 읽는다. **이 계획의 컨트랙트 테스트는 이미 복사 목록에 있는 파일만 읽는다**: `SupabaseClient.swift`, `AppDelegate.swift`, `SettingsScene.swift`, `LocalNotificationCenter.swift`, `PingError.swift`. → `project.yml` 복사 스크립트 수정 불필요.
- `AccountStore`/`NotificationLedger`/`MultiAccountGate`/`AccountsFile`은 실 단위 테스트로 검증(컨트랙트 대상 아님 → 복사 목록 추가 불필요). `PingTests/`는 디렉터리 글롭이므로 새 테스트 파일은 `xcodegen generate` 후 자동 포함된다.
- 새 소스 파일을 타깃에 포함시키려면 **반드시** `xcodegen generate`를 먼저 실행한다. 모든 테스트 실행 명령은 `xcodegen generate`를 선행한다.

### 공통 테스트 명령
```bash
xcodegen generate >/dev/null
xcodebuild test -project Ping.xcodeproj -scheme Ping -destination 'platform=macOS' \
  -only-testing:PingTests/<클래스>/<메서드> 2>&1 | tail -30
```
전체 실행은 `-only-testing` 없이.

---

## Task 1: 계정 모델 + 순수 전이 함수

기기에 보관되는 계정의 데이터 모델과, 추가/전환/삭제/갱신을 순수 함수로 표현한다(네트워크·설정 불필요 → 완전 단위 테스트 가능).

**Files:**
- Modify: `Ping/Backend/SupabaseClient.swift:97` (`SupabaseSession`을 internal로)
- Create: `Ping/Backend/AccountStore.swift` (이 태스크에서는 모델 + 전이 함수까지)
- Test: `PingTests/AccountsFileTests.swift`

- [ ] **Step 1: `SupabaseSession`을 internal로 공개**

`AccountStore.swift`(별도 파일)가 `SupabaseSession`과 변환하려면 internal 이어야 한다.

Edit `Ping/Backend/SupabaseClient.swift` — 다음을 찾아서:

```swift
private struct SupabaseSession: Codable {
```

다음으로 교체:

```swift
struct SupabaseSession: Codable {
```

- [ ] **Step 2: 실패하는 테스트 작성 (`AccountsFileTests`)**

Create `PingTests/AccountsFileTests.swift`:

```swift
import XCTest
@testable import Ping

final class AccountsFileTests: XCTestCase {
    private func session(_ uid: String, token: String = "t") -> SupabaseSession {
        SupabaseSession(
            accessToken: "\(token)-access-\(uid)",
            refreshToken: "\(token)-refresh-\(uid)",
            expiresAt: Date(timeIntervalSince1970: 10_000),
            userId: uid
        )
    }

    private func account(_ uid: String, nickname: String = "") -> StoredAccount {
        StoredAccount(session: session(uid), nickname: nickname, addedAt: Date(timeIntervalSince1970: 1))
    }

    func testMigratingFromNilIsEmpty() {
        XCTAssertEqual(AccountsFile.migrating(from: nil), .empty)
    }

    func testMigratingFromSessionCreatesSingleActiveAccount() {
        let file = AccountsFile.migrating(from: session("u1"))
        XCTAssertEqual(file.accounts.map(\.userId), ["u1"])
        XCTAssertEqual(file.activeUserId, "u1")
        XCTAssertEqual(file.activeAccount?.nickname, "")
    }

    func testAddingActivatesNewAccountAndIsIdempotentOnUserId() {
        var file = AccountsFile.empty
        file = file.adding(account("a"), activate: true)
        file = file.adding(account("b"), activate: true)
        XCTAssertEqual(file.accounts.map(\.userId), ["a", "b"])
        XCTAssertEqual(file.activeUserId, "b")

        // Re-adding same userId replaces, does not duplicate.
        file = file.adding(account("a", nickname: "renamed"), activate: false)
        XCTAssertEqual(file.accounts.map(\.userId), ["b", "a"])
        XCTAssertEqual(file.activeUserId, "b")
        XCTAssertEqual(file.accounts.first(where: { $0.userId == "a" })?.nickname, "renamed")
    }

    func testRemovingActiveAccountSelectsFirstRemainingAsActive() {
        var file = AccountsFile(accounts: [account("a"), account("b")], activeUserId: "a")
        file = file.removing(userId: "a")
        XCTAssertEqual(file.accounts.map(\.userId), ["b"])
        XCTAssertEqual(file.activeUserId, "b")
    }

    func testRemovingLastAccountClearsActive() {
        var file = AccountsFile(accounts: [account("a")], activeUserId: "a")
        file = file.removing(userId: "a")
        XCTAssertTrue(file.accounts.isEmpty)
        XCTAssertNil(file.activeUserId)
    }

    func testRemovingInactiveAccountKeepsActive() {
        var file = AccountsFile(accounts: [account("a"), account("b")], activeUserId: "a")
        file = file.removing(userId: "b")
        XCTAssertEqual(file.activeUserId, "a")
    }

    func testSwitchingToKnownAccountUpdatesActive() {
        let file = AccountsFile(accounts: [account("a"), account("b")], activeUserId: "a")
        let switched = file.switching(to: "b")
        XCTAssertEqual(switched?.activeUserId, "b")
    }

    func testSwitchingToUnknownAccountReturnsNil() {
        let file = AccountsFile(accounts: [account("a")], activeUserId: "a")
        XCTAssertNil(file.switching(to: "ghost"))
    }

    func testUpdatingNicknameOnlyChangesTarget() {
        let file = AccountsFile(accounts: [account("a", nickname: "x"), account("b", nickname: "y")], activeUserId: "a")
        let updated = file.updatingNickname("영민", for: "a")
        XCTAssertEqual(updated.accounts.first(where: { $0.userId == "a" })?.nickname, "영민")
        XCTAssertEqual(updated.accounts.first(where: { $0.userId == "b" })?.nickname, "y")
    }

    func testUpsertingExistingSessionRefreshesTokensInPlace() {
        var file = AccountsFile(accounts: [account("a")], activeUserId: "a")
        let refreshed = SupabaseSession(
            accessToken: "new-access",
            refreshToken: "new-refresh",
            expiresAt: Date(timeIntervalSince1970: 99_999),
            userId: "a"
        )
        file = file.upserting(session: refreshed, activateIfFirst: true)
        XCTAssertEqual(file.accounts.count, 1)
        XCTAssertEqual(file.accounts[0].accessToken, "new-access")
        XCTAssertEqual(file.accounts[0].expiresAt, Date(timeIntervalSince1970: 99_999))
        XCTAssertEqual(file.activeUserId, "a")
    }

    func testUpsertingNewSessionAppendsAndActivatesWhenNoneActive() {
        let file = AccountsFile.empty.upserting(session: session("first"), activateIfFirst: true)
        XCTAssertEqual(file.accounts.map(\.userId), ["first"])
        XCTAssertEqual(file.activeUserId, "first")
    }
}
```

- [ ] **Step 3: 테스트 실패 확인**

Run:
```bash
xcodegen generate >/dev/null
xcodebuild test -project Ping.xcodeproj -scheme Ping -destination 'platform=macOS' \
  -only-testing:PingTests/AccountsFileTests 2>&1 | tail -30
```
Expected: 컴파일 실패 — `StoredAccount`/`AccountsFile` 미정의.

- [ ] **Step 4: 모델 + 전이 함수 구현**

Create `Ping/Backend/AccountStore.swift`:

```swift
import Foundation

/// 한 기기에 보관되는 익명 계정 하나. UI 표시용 nickname 캐시를 포함한다.
struct StoredAccount: Codable, Identifiable, Equatable {
    let userId: String
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var nickname: String
    let addedAt: Date

    var id: String { userId }

    init(
        userId: String,
        accessToken: String,
        refreshToken: String,
        expiresAt: Date,
        nickname: String,
        addedAt: Date
    ) {
        self.userId = userId
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.nickname = nickname
        self.addedAt = addedAt
    }

    init(session: SupabaseSession, nickname: String, addedAt: Date = Date()) {
        self.init(
            userId: session.userId,
            accessToken: session.accessToken,
            refreshToken: session.refreshToken,
            expiresAt: session.expiresAt,
            nickname: nickname,
            addedAt: addedAt
        )
    }

    var session: SupabaseSession {
        SupabaseSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            userId: userId
        )
    }
}

/// 디스크에 직렬화되는 다중 계정 상태.
struct AccountsFile: Codable, Equatable {
    var accounts: [StoredAccount]
    var activeUserId: String?

    static let empty = AccountsFile(accounts: [], activeUserId: nil)

    var activeAccount: StoredAccount? {
        accounts.first { $0.userId == activeUserId }
    }

    /// 레거시 단일 세션을 계정 #1로 이전한다.
    static func migrating(from legacy: SupabaseSession?) -> AccountsFile {
        guard let legacy else { return .empty }
        return AccountsFile(
            accounts: [StoredAccount(session: legacy, nickname: "")],
            activeUserId: legacy.userId
        )
    }

    /// 계정 추가. 같은 userId는 교체(중복 방지). activate=true면 활성으로.
    func adding(_ account: StoredAccount, activate: Bool) -> AccountsFile {
        var copy = self
        copy.accounts.removeAll { $0.userId == account.userId }
        copy.accounts.append(account)
        if activate { copy.activeUserId = account.userId }
        return copy
    }

    /// 계정 삭제. 활성 계정을 지우면 남은 첫 계정을 활성으로(없으면 nil).
    func removing(userId: String) -> AccountsFile {
        var copy = self
        copy.accounts.removeAll { $0.userId == userId }
        if copy.activeUserId == userId {
            copy.activeUserId = copy.accounts.first?.userId
        }
        return copy
    }

    /// 활성 계정 전환. 모르는 userId면 nil.
    func switching(to userId: String) -> AccountsFile? {
        guard accounts.contains(where: { $0.userId == userId }) else { return nil }
        var copy = self
        copy.activeUserId = userId
        return copy
    }

    /// 특정 계정의 표시용 닉네임 갱신.
    func updatingNickname(_ nickname: String, for userId: String) -> AccountsFile {
        var copy = self
        if let index = copy.accounts.firstIndex(where: { $0.userId == userId }) {
            copy.accounts[index].nickname = nickname
        }
        return copy
    }

    /// 세션의 토큰/만료를 반영. 없는 계정이면 추가. activateIfFirst면 활성이 비었을 때 활성으로.
    func upserting(session: SupabaseSession, activateIfFirst: Bool) -> AccountsFile {
        var copy = self
        if let index = copy.accounts.firstIndex(where: { $0.userId == session.userId }) {
            copy.accounts[index].accessToken = session.accessToken
            copy.accounts[index].refreshToken = session.refreshToken
            copy.accounts[index].expiresAt = session.expiresAt
        } else {
            copy.accounts.append(StoredAccount(session: session, nickname: ""))
        }
        if activateIfFirst, copy.activeUserId == nil {
            copy.activeUserId = session.userId
        }
        return copy
    }
}
```

- [ ] **Step 5: 테스트 통과 확인**

Run:
```bash
xcodegen generate >/dev/null
xcodebuild test -project Ping.xcodeproj -scheme Ping -destination 'platform=macOS' \
  -only-testing:PingTests/AccountsFileTests 2>&1 | tail -30
```
Expected: PASS (전 케이스).

- [ ] **Step 6: 커밋**

```bash
git add Ping/Backend/AccountStore.swift PingTests/AccountsFileTests.swift Ping/Backend/SupabaseClient.swift Ping.xcodeproj
git commit -m "feat(macos): account models + pure account-file transitions"
```

---

## Task 2: `AccountStore` 영속 계층 (직렬화·마이그레이션·레거시 미러)

`Accounts.json` 읽기/쓰기와, `Accounts.json`이 없을 때 레거시 `SupabaseSession.json`/UserDefaults에서의 마이그레이션, 활성 세션의 레거시 미러 기록을 담당한다. 디렉터리·UserDefaults를 주입받아 임시 디렉터리에서 실 IO 단위 테스트한다.

**Files:**
- Modify: `Ping/Backend/AccountStore.swift` (클래스 `AccountStore` 추가)
- Test: `PingTests/AccountStoreTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성 (`AccountStoreTests`)**

Create `PingTests/AccountStoreTests.swift`:

```swift
import XCTest
@testable import Ping

final class AccountStoreTests: XCTestCase {
    private var tempDir: URL!
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AccountStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        suiteName = "AccountStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeStore() -> AccountStore {
        AccountStore(directoryURL: tempDir, defaults: defaults)
    }

    private func session(_ uid: String) -> SupabaseSession {
        SupabaseSession(
            accessToken: "access-\(uid)",
            refreshToken: "refresh-\(uid)",
            expiresAt: Date(timeIntervalSince1970: 50_000),
            userId: uid
        )
    }

    func testLoadReturnsEmptyWhenNothingStored() {
        let file = makeStore().load()
        XCTAssertTrue(file.accounts.isEmpty)
        XCTAssertNil(file.activeUserId)
    }

    func testSaveAndLoadRoundTrip() {
        let store = makeStore()
        let a = StoredAccount(session: session("u1"), nickname: "영민", addedAt: Date(timeIntervalSince1970: 100))
        let b = StoredAccount(session: session("u2"), nickname: "second", addedAt: Date(timeIntervalSince1970: 200))
        store.save(AccountsFile(accounts: [a, b], activeUserId: "u2"))

        let loaded = makeStore().load()
        XCTAssertEqual(loaded.accounts.map(\.userId), ["u1", "u2"])
        XCTAssertEqual(loaded.activeUserId, "u2")
        XCTAssertEqual(loaded.activeAccount?.nickname, "second")
    }

    func testMigratesLegacyFileSessionWhenNoAccountsFile() throws {
        let data = try JSONEncoder().encode(session("legacy-uid"))
        try data.write(to: tempDir.appendingPathComponent("SupabaseSession.json"))

        let loaded = makeStore().load()
        XCTAssertEqual(loaded.accounts.map(\.userId), ["legacy-uid"])
        XCTAssertEqual(loaded.activeUserId, "legacy-uid")
        // 마이그레이션은 Accounts.json을 생성해 둔다.
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("Accounts.json").path))
    }

    func testMigratesLegacyDefaultsSessionWhenNoFiles() throws {
        let data = try JSONEncoder().encode(session("defaults-uid"))
        defaults.set(data, forKey: "ping.supabase.session")

        let loaded = makeStore().load()
        XCTAssertEqual(loaded.activeUserId, "defaults-uid")
    }

    func testAccountsFileTakesPrecedenceOverLegacy() throws {
        // Accounts.json 존재 시 레거시 무시.
        let store = makeStore()
        store.save(AccountsFile(accounts: [StoredAccount(session: session("real"), nickname: "n", addedAt: Date())], activeUserId: "real"))
        let legacyData = try JSONEncoder().encode(session("stale-legacy"))
        try legacyData.write(to: tempDir.appendingPathComponent("SupabaseSession.json"))

        let loaded = makeStore().load()
        XCTAssertEqual(loaded.activeUserId, "real")
    }

    func testSaveWritesLegacyMirrorForActiveAccount() throws {
        let store = makeStore()
        let other = StoredAccount(session: session("other"), nickname: "x", addedAt: Date())
        let active = StoredAccount(session: session("active"), nickname: "영민", addedAt: Date())
        store.save(AccountsFile(accounts: [other, active], activeUserId: "active"))

        let mirrorData = try Data(contentsOf: tempDir.appendingPathComponent("SupabaseSession.json"))
        let mirror = try JSONDecoder().decode(SupabaseSession.self, from: mirrorData)
        XCTAssertEqual(mirror.userId, "active")

        let defaultsData = try XCTUnwrap(defaults.data(forKey: "ping.supabase.session"))
        let defaultsMirror = try JSONDecoder().decode(SupabaseSession.self, from: defaultsData)
        XCTAssertEqual(defaultsMirror.userId, "active")
    }
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run:
```bash
xcodegen generate >/dev/null
xcodebuild test -project Ping.xcodeproj -scheme Ping -destination 'platform=macOS' \
  -only-testing:PingTests/AccountStoreTests 2>&1 | tail -30
```
Expected: 컴파일 실패 — `AccountStore` 미정의.

- [ ] **Step 3: `AccountStore` 클래스 구현**

Edit `Ping/Backend/AccountStore.swift` — 파일 맨 끝에 추가:

```swift

/// 다중 계정 영속 계층. Accounts.json을 소유하고, 활성 세션을 레거시
/// SupabaseSession.json + UserDefaults에 미러해 다운그레이드/토큰 갱신 경로와 호환된다.
final class AccountStore {
    private let directoryURL: URL
    private let defaults: UserDefaults

    private let accountsFileName = "Accounts.json"
    private let legacyFileName = "SupabaseSession.json"
    private let legacyDefaultsKey = "ping.supabase.session"

    init(directoryURL: URL, defaults: UserDefaults = .standard) {
        self.directoryURL = directoryURL
        self.defaults = defaults
    }

    static func makeDefault() -> AccountStore {
        if let support = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) {
            let directory = support.appendingPathComponent("Ping", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return AccountStore(directoryURL: directory)
        }
        return AccountStore(directoryURL: FileManager.default.temporaryDirectory)
    }

    func load() -> AccountsFile {
        if let file = readAccountsFile() {
            return file
        }
        let migrated = AccountsFile.migrating(from: loadLegacySession())
        if !migrated.accounts.isEmpty {
            save(migrated)
        }
        return migrated
    }

    func save(_ file: AccountsFile) {
        writeAccountsFile(file)
        if let active = file.activeAccount {
            writeLegacyMirror(active.session)
        }
    }

    // MARK: - Accounts.json

    private var accountsFileURL: URL { directoryURL.appendingPathComponent(accountsFileName) }

    private func readAccountsFile() -> AccountsFile? {
        guard let data = try? Data(contentsOf: accountsFileURL) else { return nil }
        return try? JSONDecoder().decode(AccountsFile.self, from: data)
    }

    private func writeAccountsFile(_ file: AccountsFile) {
        guard let data = try? JSONEncoder().encode(file) else { return }
        try? data.write(to: accountsFileURL, options: .atomic)
    }

    // MARK: - 레거시 미러 (다운그레이드 호환)

    private var legacyFileURL: URL { directoryURL.appendingPathComponent(legacyFileName) }

    private func loadLegacySession() -> SupabaseSession? {
        if let data = try? Data(contentsOf: legacyFileURL),
           let session = try? JSONDecoder().decode(SupabaseSession.self, from: data) {
            return session
        }
        if let data = defaults.data(forKey: legacyDefaultsKey),
           let session = try? JSONDecoder().decode(SupabaseSession.self, from: data) {
            return session
        }
        return nil
    }

    private func writeLegacyMirror(_ session: SupabaseSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        try? data.write(to: legacyFileURL, options: .atomic)
        defaults.set(data, forKey: legacyDefaultsKey)
    }
}
```

> 미러 포맷은 기존 `SupabaseSessionStore.save`와 동일하게 기본 `JSONEncoder()`로 `SupabaseSession` 값을 인코딩하므로 바이트 호환된다.

- [ ] **Step 4: 테스트 통과 확인**

Run:
```bash
xcodegen generate >/dev/null
xcodebuild test -project Ping.xcodeproj -scheme Ping -destination 'platform=macOS' \
  -only-testing:PingTests/AccountStoreTests 2>&1 | tail -30
```
Expected: PASS.

- [ ] **Step 5: 커밋**

```bash
git add Ping/Backend/AccountStore.swift PingTests/AccountStoreTests.swift Ping.xcodeproj
git commit -m "feat(macos): AccountStore persistence with legacy migration + mirror"
```

---

## Task 3: `SupabaseClient` 다중 계정 API

`SupabaseClient`가 `AccountStore`를 사용해 다중 계정 상태를 발행하고 추가/전환/삭제/닉네임갱신 메서드를 노출한다. 기존 단일 세션 로드/저장 경로를 `AccountStore`로 통합하되, 컨트랙트 테스트가 검사하는 `SupabaseSessionStore` 심볼과 갱신/리프레시 동작은 그대로 유지한다.

**Files:**
- Modify: `Ping/Core/PingError.swift:16` (case 추가) 및 `errorDescription`
- Modify: `Ping/Backend/SupabaseClient.swift` (발행 상태/프로퍼티/init/configure/save/신규 메서드)
- Test: `PingTests/MultiAccountSwitchingContractTests.swift` (이 태스크 분량)

- [ ] **Step 1: 실패하는 컨트랙트 테스트 작성**

Create `PingTests/MultiAccountSwitchingContractTests.swift`:

```swift
import XCTest

final class MultiAccountSwitchingContractTests: XCTestCase {
    func testSupabaseClientExposesMultiAccountState() throws {
        let source = try readSourceFile("Ping/Backend/SupabaseClient.swift")
        XCTAssertTrue(source.contains("@Published private(set) var accounts: [StoredAccount]"))
        XCTAssertTrue(source.contains("@Published private(set) var activeUserId: String?"))
        XCTAssertTrue(source.contains("private let accountStore: AccountStore"))
        XCTAssertTrue(source.contains("accountStore: AccountStore = .makeDefault()"))
    }

    func testSupabaseClientConfigureLoadsAccountsFile() throws {
        let source = try readSourceFile("Ping/Backend/SupabaseClient.swift")
        XCTAssertTrue(source.contains("let file = accountStore.load()"))
        XCTAssertTrue(source.contains("session = file.activeAccount?.session"))
    }

    func testSupabaseClientHasMultiAccountMethods() throws {
        let source = try readSourceFile("Ping/Backend/SupabaseClient.swift")
        XCTAssertTrue(source.contains("func addAccount() async throws -> String"))
        XCTAssertTrue(source.contains("func switchTo(userId: String) throws"))
        XCTAssertTrue(source.contains("func removeAccount(userId: String)"))
        XCTAssertTrue(source.contains("func updateActiveNickname(_ nickname: String)"))
        XCTAssertTrue(source.contains("throw PingError.accountNotFound"))
    }

    func testSaveSessionPersistsThroughAccountStore() throws {
        let source = try readSourceFile("Ping/Backend/SupabaseClient.swift")
        XCTAssertTrue(source.contains("accountStore.save(accountsSnapshot())")
            || source.contains("accountStore.save(updated)"))
        XCTAssertTrue(source.contains("upserting(session: session, activateIfFirst: true)"))
    }

    func testLegacyStoreSymbolsRetainedForDowngradeAndRefresh() throws {
        // 기존 세션 컨트랙트가 의존하는 심볼이 사라지지 않았는지 회귀 방어.
        let source = try readSourceFile("Ping/Backend/SupabaseClient.swift")
        XCTAssertTrue(source.contains("private static let fileName = \"SupabaseSession.json\""))
        XCTAssertTrue(source.contains("withRefreshLock"))
        XCTAssertTrue(source.contains("reloadStoredSessionForRefresh"))
        XCTAssertTrue(source.contains("throw PingError.supabaseSessionExpired"))
    }

    private func readSourceFile(_ relativePath: String) throws -> String {
        let fileName = URL(fileURLWithPath: relativePath).lastPathComponent
        let fileURL = try XCTUnwrap(Bundle(for: Self.self).resourceURL?.appendingPathComponent(fileName))
        return try String(contentsOf: fileURL, encoding: .utf8)
    }
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run:
```bash
xcodegen generate >/dev/null
xcodebuild test -project Ping.xcodeproj -scheme Ping -destination 'platform=macOS' \
  -only-testing:PingTests/MultiAccountSwitchingContractTests/testSupabaseClientHasMultiAccountMethods 2>&1 | tail -20
```
Expected: FAIL (메서드 문자열 부재).

- [ ] **Step 3: `PingError.accountNotFound` 추가**

Edit `Ping/Core/PingError.swift` — `case roomUnavailable` 다음 줄에 추가:

```swift
    case roomUnavailable
    case accountNotFound
```

그리고 `errorDescription`의 `case .roomUnavailable:` 블록 다음에 추가:

```swift
        case .accountNotFound:
            return "선택한 계정을 찾을 수 없습니다."
```

- [ ] **Step 4: 발행 상태 + accountStore 프로퍼티 + init**

Edit `Ping/Backend/SupabaseClient.swift` — 다음을 찾아서:

```swift
    @Published private(set) var currentUid: String?
    @Published private(set) var isConfigured = false

    private var configuration: SupabaseConfiguration?
    private var session: SupabaseSession?
    private var authSessionTask: Task<SupabaseSession, Error>?
    private let urlSession: URLSession

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }
```

다음으로 교체:

```swift
    @Published private(set) var currentUid: String?
    @Published private(set) var isConfigured = false
    @Published private(set) var accounts: [StoredAccount] = []
    @Published private(set) var activeUserId: String?

    private var configuration: SupabaseConfiguration?
    private var session: SupabaseSession?
    private var authSessionTask: Task<SupabaseSession, Error>?
    private let urlSession: URLSession
    private let accountStore: AccountStore

    init(urlSession: URLSession = .shared, accountStore: AccountStore = .makeDefault()) {
        self.urlSession = urlSession
        self.accountStore = accountStore
    }

    private func accountsSnapshot() -> AccountsFile {
        AccountsFile(accounts: accounts, activeUserId: activeUserId)
    }

    private func applyAccountsFile(_ file: AccountsFile, swapSession: Bool) {
        accounts = file.accounts
        activeUserId = file.activeUserId
        if swapSession {
            session = file.activeAccount?.session
            currentUid = activeUserId
        }
        accountStore.save(file)
    }
```

- [ ] **Step 5: `configureIfNeeded`를 다중 계정 로드로 교체**

Edit `Ping/Backend/SupabaseClient.swift` — 다음을 찾아서:

```swift
        configuration = try SupabaseConfiguration.load()
        session = SupabaseSessionStore.load()
        currentUid = session?.userId
        isConfigured = true
```

다음으로 교체:

```swift
        configuration = try SupabaseConfiguration.load()
        let file = accountStore.load()
        accounts = file.accounts
        activeUserId = file.activeUserId
        session = file.activeAccount?.session
        currentUid = session?.userId
        isConfigured = true
```

- [ ] **Step 6: `save(session:)`를 계정 인지형으로 교체**

Edit `Ping/Backend/SupabaseClient.swift` — 다음을 찾아서:

```swift
    private func save(session: SupabaseSession) {
        self.session = session
        currentUid = session.userId
        SupabaseSessionStore.save(session)
    }
```

다음으로 교체:

```swift
    private func save(session: SupabaseSession) {
        self.session = session
        currentUid = session.userId
        let updated = accountsSnapshot().upserting(session: session, activateIfFirst: true)
        accounts = updated.accounts
        activeUserId = updated.activeUserId
        accountStore.save(updated)
    }
```

- [ ] **Step 7: 다중 계정 메서드 추가**

Edit `Ping/Backend/SupabaseClient.swift` — `func bootstrap() async throws -> String { ... }` 블록 바로 다음에 추가:

```swift

    func addAccount() async throws -> String {
        try configureIfNeeded()
        let newSession = try await signInAnonymously()
        authSessionTask?.cancel()
        authSessionTask = nil
        let updated = accountsSnapshot().adding(
            StoredAccount(session: newSession, nickname: ""),
            activate: true
        )
        applyAccountsFile(updated, swapSession: true)
        return newSession.userId
    }

    func switchTo(userId: String) throws {
        guard let updated = accountsSnapshot().switching(to: userId) else {
            throw PingError.accountNotFound
        }
        authSessionTask?.cancel()
        authSessionTask = nil
        applyAccountsFile(updated, swapSession: true)
    }

    func removeAccount(userId: String) {
        let wasActive = activeUserId == userId
        if wasActive {
            authSessionTask?.cancel()
            authSessionTask = nil
        }
        let updated = accountsSnapshot().removing(userId: userId)
        applyAccountsFile(updated, swapSession: wasActive)
    }

    func updateActiveNickname(_ nickname: String) {
        guard let uid = activeUserId else { return }
        let updated = accountsSnapshot().updatingNickname(nickname, for: uid)
        guard updated != accountsSnapshot() else { return }
        accounts = updated.accounts
        accountStore.save(updated)
    }
```

> 참고: `signInAnonymously()`는 `private`이지만 같은 타입 내부 호출이라 접근 가능하다. `switchTo`는 동기(throws)이며, 전환 후 세션이 만료됐으면 다음 RPC 시 기존 `authenticatedSession`→`refreshSession` 경로가 레거시 미러(전환으로 갱신됨)를 읽어 자동 갱신한다.

- [ ] **Step 8: 컨트랙트 테스트 통과 + 기존 세션 컨트랙트 회귀 확인**

Run:
```bash
xcodegen generate >/dev/null
xcodebuild test -project Ping.xcodeproj -scheme Ping -destination 'platform=macOS' \
  -only-testing:PingTests/MultiAccountSwitchingContractTests \
  -only-testing:PingTests/SupabaseSessionContractTests 2>&1 | tail -30
```
Expected: 양쪽 클래스 모두 PASS (기존 `SupabaseSessionContractTests` 회귀 없음).

- [ ] **Step 9: 커밋**

```bash
git add Ping/Backend/SupabaseClient.swift Ping/Core/PingError.swift PingTests/MultiAccountSwitchingContractTests.swift Ping.xcodeproj
git commit -m "feat(macos): SupabaseClient multi-account add/switch/remove API"
```

---

## Task 4: `NotificationLedger` (계정별 알림 dedup)

영상/초대/채팅 알림의 재알림을 막는 계정별 영속 원장. UserDefaults 키를 `<base>:<uid>`로 격리하고 종류별로 분리, 캡으로 무한 증가를 막는다. 주입 가능한 UserDefaults로 단위 테스트.

**Files:**
- Create: `Ping/Notifications/NotificationLedger.swift`
- Test: `PingTests/NotificationLedgerTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

Create `PingTests/NotificationLedgerTests.swift`:

```swift
import XCTest
@testable import Ping

final class NotificationLedgerTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "NotificationLedgerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testRememberThenContains() {
        let ledger = NotificationLedger(defaults: defaults)
        XCTAssertFalse(ledger.contains(.video, uid: "u1", id: "m1"))
        ledger.remember(.video, uid: "u1", id: "m1")
        XCTAssertTrue(ledger.contains(.video, uid: "u1", id: "m1"))
    }

    func testAccountIsolation() {
        let ledger = NotificationLedger(defaults: defaults)
        ledger.remember(.video, uid: "u1", id: "shared")
        XCTAssertTrue(ledger.contains(.video, uid: "u1", id: "shared"))
        XCTAssertFalse(ledger.contains(.video, uid: "u2", id: "shared"))
    }

    func testKindIsolation() {
        let ledger = NotificationLedger(defaults: defaults)
        ledger.remember(.video, uid: "u1", id: "x")
        XCTAssertFalse(ledger.contains(.chat, uid: "u1", id: "x"))
        XCTAssertFalse(ledger.contains(.invite, uid: "u1", id: "x"))
    }

    func testCapBoundsStoredIds() {
        let ledger = NotificationLedger(defaults: defaults, cap: 5)
        for i in 0..<20 { ledger.remember(.chat, uid: "u1", id: "c\(i)") }
        XCTAssertEqual(ledger.ids(.chat, uid: "u1").count, 5)
        // 최신 항목은 남아있다.
        XCTAssertTrue(ledger.contains(.chat, uid: "u1", id: "c19"))
        // 가장 오래된 항목은 밀려났다.
        XCTAssertFalse(ledger.contains(.chat, uid: "u1", id: "c0"))
    }

    func testPersistsAcrossInstances() {
        NotificationLedger(defaults: defaults).remember(.invite, uid: "u1", id: "i1")
        XCTAssertTrue(NotificationLedger(defaults: defaults).contains(.invite, uid: "u1", id: "i1"))
    }
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run:
```bash
xcodegen generate >/dev/null
xcodebuild test -project Ping.xcodeproj -scheme Ping -destination 'platform=macOS' \
  -only-testing:PingTests/NotificationLedgerTests 2>&1 | tail -20
```
Expected: 컴파일 실패 — `NotificationLedger` 미정의.

- [ ] **Step 3: `NotificationLedger` 구현**

Create `Ping/Notifications/NotificationLedger.swift`:

```swift
import Foundation

/// 계정별·종류별로 격리된 알림 dedup 원장. 같은 알림을 전환마다 재발송하지 않도록
/// 이미 알린 ID를 UserDefaults에 영속한다.
struct NotificationLedger {
    enum Kind: String {
        case video
        case invite
        case chat

        var baseKey: String {
            switch self {
            case .video: return "ping.notifications.notifiedMessageIds"
            case .invite: return "ping.notifications.notifiedInviteIds"
            case .chat: return "ping.notifications.notifiedChatIds"
            }
        }
    }

    private let defaults: UserDefaults
    private let cap: Int

    init(defaults: UserDefaults = .standard, cap: Int = 300) {
        self.defaults = defaults
        self.cap = cap
    }

    private func key(_ kind: Kind, uid: String) -> String {
        "\(kind.baseKey):\(uid)"
    }

    func ids(_ kind: Kind, uid: String) -> Set<String> {
        Set(defaults.stringArray(forKey: key(kind, uid: uid)) ?? [])
    }

    func contains(_ kind: Kind, uid: String, id: String) -> Bool {
        ids(kind, uid: uid).contains(id)
    }

    func remember(_ kind: Kind, uid: String, id: String) {
        let storageKey = key(kind, uid: uid)
        var ordered = defaults.stringArray(forKey: storageKey) ?? []
        // 중복 제거하면서 최근 추가를 끝으로 유지.
        ordered.removeAll { $0 == id }
        ordered.append(id)
        if ordered.count > cap {
            ordered = Array(ordered.suffix(cap))
        }
        defaults.set(ordered, forKey: storageKey)
    }
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run:
```bash
xcodegen generate >/dev/null
xcodebuild test -project Ping.xcodeproj -scheme Ping -destination 'platform=macOS' \
  -only-testing:PingTests/NotificationLedgerTests 2>&1 | tail -20
```
Expected: PASS.

- [ ] **Step 5: 커밋**

```bash
git add Ping/Notifications/NotificationLedger.swift PingTests/NotificationLedgerTests.swift Ping.xcodeproj
git commit -m "feat(macos): per-account notification dedup ledger"
```

---

## Task 5: `MultiAccountGate` (`영민` 게이트)

활성 닉네임이 `영민`(트림 후 정확히 일치)이면 기기 로컬 unlock 플래그를 켠다. 한 번 켜지면 유지된다.

**Files:**
- Create: `Ping/Core/MultiAccountGate.swift`
- Test: `PingTests/MultiAccountGateTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

Create `PingTests/MultiAccountGateTests.swift`:

```swift
import XCTest
@testable import Ping

final class MultiAccountGateTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "MultiAccountGateTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testLockedByDefault() {
        XCTAssertFalse(MultiAccountGate.isUnlocked(defaults: defaults))
    }

    func testOwnerNicknameUnlocks() {
        MultiAccountGate.updateUnlock(forNickname: "영민", defaults: defaults)
        XCTAssertTrue(MultiAccountGate.isUnlocked(defaults: defaults))
    }

    func testOwnerNicknameWithWhitespaceUnlocks() {
        MultiAccountGate.updateUnlock(forNickname: "  영민 ", defaults: defaults)
        XCTAssertTrue(MultiAccountGate.isUnlocked(defaults: defaults))
    }

    func testNonOwnerDoesNotUnlock() {
        MultiAccountGate.updateUnlock(forNickname: "철수", defaults: defaults)
        XCTAssertFalse(MultiAccountGate.isUnlocked(defaults: defaults))
    }

    func testStaysUnlockedAfterSwitchingToNonOwner() {
        MultiAccountGate.updateUnlock(forNickname: "영민", defaults: defaults)
        MultiAccountGate.updateUnlock(forNickname: "철수", defaults: defaults)
        XCTAssertTrue(MultiAccountGate.isUnlocked(defaults: defaults))
    }
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run:
```bash
xcodegen generate >/dev/null
xcodebuild test -project Ping.xcodeproj -scheme Ping -destination 'platform=macOS' \
  -only-testing:PingTests/MultiAccountGateTests 2>&1 | tail -20
```
Expected: 컴파일 실패 — `MultiAccountGate` 미정의.

- [ ] **Step 3: `MultiAccountGate` 구현**

Create `Ping/Core/MultiAccountGate.swift`:

```swift
import Foundation

/// 다중 계정 스위처 노출 게이트. 활성 닉네임이 오너(`영민`)면 기기 로컬 플래그를 켠다.
/// 한 번 켜지면 유지되어, 비-오너 계정으로 전환해도 스위처가 사라져 갇히지 않는다.
enum MultiAccountGate {
    static let unlockedKey = "ping.multiAccount.unlocked"
    static let ownerNickname = "영민"

    static func isUnlocked(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: unlockedKey)
    }

    @discardableResult
    static func updateUnlock(forNickname nickname: String, defaults: UserDefaults = .standard) -> Bool {
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == ownerNickname {
            defaults.set(true, forKey: unlockedKey)
        }
        return isUnlocked(defaults: defaults)
    }
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run:
```bash
xcodegen generate >/dev/null
xcodebuild test -project Ping.xcodeproj -scheme Ping -destination 'platform=macOS' \
  -only-testing:PingTests/MultiAccountGateTests 2>&1 | tail -20
```
Expected: PASS.

- [ ] **Step 5: 커밋**

```bash
git add Ping/Core/MultiAccountGate.swift PingTests/MultiAccountGateTests.swift Ping.xcodeproj
git commit -m "feat(macos): owner-only multi-account unlock gate"
```

---

## Task 6: 채팅 캐치업 알림 헬퍼

전환 직후 미독 채팅을 룸별 묶음 알림 1건으로 게시하는 헬퍼. 기존 채팅 탭 핸들러(`type == "chat"` + `room_id`)와 호환되도록 userInfo를 맞춘다.

**Files:**
- Modify: `Ping/Notifications/LocalNotificationCenter.swift` (`notifyChatCatchUp` 추가)
- Test: `PingTests/MultiAccountSwitchingContractTests.swift` (메서드 추가)

- [ ] **Step 1: 실패하는 컨트랙트 테스트 추가**

Edit `PingTests/MultiAccountSwitchingContractTests.swift` — `testLegacyStoreSymbolsRetainedForDowngradeAndRefresh` 메서드 다음에 추가:

```swift
    func testLocalNotificationCenterHasChatCatchUpHelper() throws {
        let source = try readSourceFile("Ping/Notifications/LocalNotificationCenter.swift")
        XCTAssertTrue(source.contains("func notifyChatCatchUp(roomId: String, roomName: String, unreadCount: Int, latestPreview: String)"))
        XCTAssertTrue(source.contains("\"type\": \"chat\""))
        XCTAssertTrue(source.contains("chat-catchup-"))
    }
```

- [ ] **Step 2: 테스트 실패 확인**

Run:
```bash
xcodegen generate >/dev/null
xcodebuild test -project Ping.xcodeproj -scheme Ping -destination 'platform=macOS' \
  -only-testing:PingTests/MultiAccountSwitchingContractTests/testLocalNotificationCenterHasChatCatchUpHelper 2>&1 | tail -20
```
Expected: FAIL.

- [ ] **Step 3: `notifyChatCatchUp` 구현**

Edit `Ping/Notifications/LocalNotificationCenter.swift` — `notifyIncomingChat(_:roomName:)` 메서드의 닫는 `}` 다음에 추가:

```swift

    /// 전환 시 한 룸의 밀린 채팅을 묶어 1건으로 알린다. 탭하면 기존 채팅 핸들러가 룸을 연다.
    func notifyChatCatchUp(roomId: String, roomName: String, unreadCount: Int, latestPreview: String) {
        let content = UNMutableNotificationContent()
        content.title = "\(roomName) · 새 메시지 \(unreadCount)개"
        let body = latestPreview.isEmpty ? "사진을 보냈습니다" : latestPreview
        content.body = body.count > 200 ? String(body.prefix(200)) + "…" : body
        content.sound = notificationSound()
        content.userInfo = [
            "type": "chat",
            "chat_id": "",
            "room_id": roomId
        ]
        let request = UNNotificationRequest(
            identifier: "chat-catchup-\(roomId)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error { NSLog("notifyChatCatchUp failed: \(error)") }
        }
    }
```

> `chat_id`가 빈 문자열이어도 기존 탭 핸들러는 `room_id`로 룸을 포커스한다(`onViewChatMessage(chatId, roomId)` → `pendingRoomFocusId = roomId`).

- [ ] **Step 4: 테스트 통과 확인**

Run:
```bash
xcodegen generate >/dev/null
xcodebuild test -project Ping.xcodeproj -scheme Ping -destination 'platform=macOS' \
  -only-testing:PingTests/MultiAccountSwitchingContractTests/testLocalNotificationCenterHasChatCatchUpHelper 2>&1 | tail -20
```
Expected: PASS.

- [ ] **Step 5: 커밋**

```bash
git add Ping/Notifications/LocalNotificationCenter.swift PingTests/MultiAccountSwitchingContractTests.swift Ping.xcodeproj
git commit -m "feat(macos): grouped chat catch-up notification helper"
```

---

## Task 7: `AppDelegate` 전환 오케스트레이션 + 캐치업 + 인텐트

계정별 ledger dedup으로 영상/초대 알림을 분리하고, 전환 시 옵저버/리얼타임/창/상태를 정리한 뒤 재-bootstrap한다. 채팅 캐치업을 트리거하고, UI 인텐트(전환/추가/삭제)를 처리하며, bootstrap/온보딩 시 닉네임 캐시와 게이트를 갱신한다.

**Files:**
- Create: `Ping/Core/AccountNotifications.swift`
- Modify: `Ping/AppDelegate.swift`
- Test: `PingTests/MultiAccountSwitchingContractTests.swift` (AppDelegate 컨트랙트 추가)

- [ ] **Step 1: 실패하는 컨트랙트 테스트 추가**

Edit `PingTests/MultiAccountSwitchingContractTests.swift` — `testLocalNotificationCenterHasChatCatchUpHelper` 다음에 추가:

```swift
    func testAppDelegateUsesPerAccountLedgerAndReload() throws {
        let source = try readSourceFile("Ping/AppDelegate.swift")
        XCTAssertTrue(source.contains("private let ledger = NotificationLedger()"))
        XCTAssertTrue(source.contains("ledger.contains(.video, uid: uid"))
        XCTAssertTrue(source.contains("ledger.remember(.video, uid: uid"))
        XCTAssertTrue(source.contains("ledger.contains(.invite, uid: uid"))
        XCTAssertTrue(source.contains("func reloadForActiveAccount()"))
        XCTAssertTrue(source.contains("func teardownForAccountChange()"))
        XCTAssertTrue(source.contains("await chatRealtime.unsubscribeAll()"))
    }

    func testAppDelegateTriggersChatCatchUp() throws {
        let source = try readSourceFile("Ping/AppDelegate.swift")
        XCTAssertTrue(source.contains("func catchUpChatNotifications(uid: String)"))
        XCTAssertTrue(source.contains("chatMessageService.unreadChatCounts()"))
        XCTAssertTrue(source.contains("notifyChatCatchUp("))
        XCTAssertTrue(source.contains("ledger.contains(.chat, uid: uid"))
    }

    func testAppDelegateHandlesAccountIntents() throws {
        let source = try readSourceFile("Ping/AppDelegate.swift")
        XCTAssertTrue(source.contains("Notification.Name.pingSwitchAccount"))
        XCTAssertTrue(source.contains("Notification.Name.pingAddAccount"))
        XCTAssertTrue(source.contains("Notification.Name.pingRemoveAccount"))
        XCTAssertTrue(source.contains("try SupabaseClient.shared.switchTo(userId:"))
        XCTAssertTrue(source.contains("SupabaseClient.shared.addAccount()"))
        XCTAssertTrue(source.contains("SupabaseClient.shared.removeAccount(userId:"))
    }

    func testAppDelegateUpdatesNicknameAndGateOnBootstrap() throws {
        let source = try readSourceFile("Ping/AppDelegate.swift")
        XCTAssertTrue(source.contains("SupabaseClient.shared.updateActiveNickname("))
        XCTAssertTrue(source.contains("MultiAccountGate.updateUnlock(forNickname:"))
    }

    func testAppDelegateBlocksSwitchWhileSending() throws {
        let source = try readSourceFile("Ping/AppDelegate.swift")
        XCTAssertTrue(source.contains("private var isSwitchingAccount"))
        XCTAssertTrue(source.contains("mirrorViewModel.state != .idle"))
    }
```

- [ ] **Step 2: 테스트 실패 확인**

Run:
```bash
xcodegen generate >/dev/null
xcodebuild test -project Ping.xcodeproj -scheme Ping -destination 'platform=macOS' \
  -only-testing:PingTests/MultiAccountSwitchingContractTests/testAppDelegateUsesPerAccountLedgerAndReload 2>&1 | tail -20
```
Expected: FAIL.

- [ ] **Step 3: 인텐트 알림 이름 정의**

Create `Ping/Core/AccountNotifications.swift`:

```swift
import Foundation

/// 설정 UI → AppDelegate 계정 인텐트. UI는 인텐트만 보내고,
/// 옵저버/창/상태를 소유한 AppDelegate가 오케스트레이션을 수행한다.
extension Notification.Name {
    static let pingSwitchAccount = Notification.Name("ping.account.switch")
    static let pingAddAccount = Notification.Name("ping.account.add")
    static let pingRemoveAccount = Notification.Name("ping.account.remove")
}

enum AccountIntentKey {
    static let userId = "userId"
}
```

- [ ] **Step 4: 계정별 ledger 프로퍼티 + 서비스 + 가드 플래그 추가**

Edit `Ping/AppDelegate.swift` — 다음을 찾아서:

```swift
    private let chatRealtime = ChatRealtimeService()
    private let appStartTime = Date()
    private let notifiedMessageIdsKey = "ping.notifications.notifiedMessageIds"

    private var notifiedChatMessageIds: Set<String> = []
    private var cancellables: Set<AnyCancellable> = []
```

다음으로 교체:

```swift
    private let chatRealtime = ChatRealtimeService()
    private let chatMessageService = ChatMessageService()
    private let appStartTime = Date()
    private let ledger = NotificationLedger()

    private var notifiedChatMessageIds: Set<String> = []
    private var isSwitchingAccount = false
    private var cancellables: Set<AnyCancellable> = []
```

> `notifiedMessageIdsKey`는 제거된다(계정별 ledger가 대체). 다음 스텝에서 `notifiedMessageIds()`/`rememberNotifiedMessage`도 제거한다.

- [ ] **Step 5: 영상 옵저버를 계정별 ledger로 전환**

Edit `Ping/AppDelegate.swift` — `startObservers`의 `incomingMessageTask` 블록을 찾아서:

```swift
        incomingMessageTask = Task { @MainActor in
            for await message in messageService.observeIncoming(uid: uid) {
                guard let id = message.id, shouldNotify(messageId: id, message: message) else {
                    continue
                }
                prefetchMessageVideo(message)
                rememberNotifiedMessage(id)
                LocalNotificationCenter.shared.notifyIncomingMessage(
                    senderNickname: message.senderNickname,
                    messageId: id,
                    roomId: message.roomId
                )
            }
        }
    }
```

다음으로 교체:

```swift
        incomingMessageTask = Task { @MainActor in
            for await message in messageService.observeIncoming(uid: uid) {
                guard let id = message.id, shouldNotify(messageId: id, uid: uid, message: message) else {
                    continue
                }
                prefetchMessageVideo(message)
                ledger.remember(.video, uid: uid, id: id)
                LocalNotificationCenter.shared.notifyIncomingMessage(
                    senderNickname: message.senderNickname,
                    messageId: id,
                    roomId: message.roomId
                )
            }
        }

        catchUpChatNotifications(uid: uid)
    }
```

- [ ] **Step 6: 초대 옵저버를 계정별 ledger로 전환**

Edit `Ping/AppDelegate.swift` — `invitationObserverTask` 블록을 찾아서:

```swift
        invitationObserverTask = Task { @MainActor in
            for await invitations in invitationService.observeIncoming(uid: uid) {
                let previousIds = Set(appState.pendingInvitations.compactMap(\.id))
                for invitation in invitations {
                    guard let id = invitation.id, !previousIds.contains(id) else { continue }
                    LocalNotificationCenter.shared.notifyIncomingInvitation(invitation)
                }
                appState.pendingInvitations = invitations
            }
        }
```

다음으로 교체:

```swift
        invitationObserverTask = Task { @MainActor in
            for await invitations in invitationService.observeIncoming(uid: uid) {
                for invitation in invitations {
                    guard let id = invitation.id, !ledger.contains(.invite, uid: uid, id: id) else { continue }
                    ledger.remember(.invite, uid: uid, id: id)
                    LocalNotificationCenter.shared.notifyIncomingInvitation(invitation)
                }
                appState.pendingInvitations = invitations
            }
        }
```

- [ ] **Step 7: `shouldNotify` 시그니처/본문 갱신 + 레거시 dedup 헬퍼 제거**

Edit `Ping/AppDelegate.swift` — 다음 블록을 찾아서:

```swift
    private func shouldNotify(messageId: String, message: VideoMessage) -> Bool {
        if notifiedMessageIds().contains(messageId) {
            return false
        }

        if message.expiresAt < Date() {
            return false
        }

        guard let createdAt = message.createdAt else { return false }
        if createdAt >= appStartTime {
            return true
        }

        // Older uploaded messages are offline catch-up. Repeat notifications are
        // blocked by the persisted message-id set above.
        return true
    }

    private func notifiedMessageIds() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: notifiedMessageIdsKey) ?? [])
    }

    private func rememberNotifiedMessage(_ id: String) {
        var set = notifiedMessageIds()
        set.insert(id)
        var ids = Array(set)
        ids = Array(ids.suffix(300))
        UserDefaults.standard.set(ids, forKey: notifiedMessageIdsKey)
    }
```

다음으로 교체:

```swift
    private func shouldNotify(messageId: String, uid: String, message: VideoMessage) -> Bool {
        if ledger.contains(.video, uid: uid, id: messageId) {
            return false
        }

        if message.expiresAt < Date() {
            return false
        }

        // 새 메시지든 오프라인 캐치업이든 알린다. 재알림은 위의 계정별 ledger가 막는다.
        return message.createdAt != nil
    }
```

- [ ] **Step 8: 채팅 캐치업 메서드 추가**

Edit `Ping/AppDelegate.swift` — `private func runCleanup(uid:)` 메서드 바로 앞에 추가:

```swift
    private func catchUpChatNotifications(uid: String) {
        Task { @MainActor in
            do {
                let counts = try await chatMessageService.unreadChatCounts()
                for (roomId, unread) in counts where unread > 0 {
                    let messages = try await chatMessageService.roomChatMessages(roomId: roomId, limit: 20)
                    let newOnes = messages.filter { msg in
                        guard msg.senderUid != uid, let id = msg.id else { return false }
                        return !ledger.contains(.chat, uid: uid, id: id)
                    }
                    guard !newOnes.isEmpty else { continue }

                    for msg in newOnes {
                        if let id = msg.id { ledger.remember(.chat, uid: uid, id: id) }
                    }

                    let roomName = appState.rooms.first(where: { $0.id == roomId })?.name ?? "룸"
                    let latest = newOnes.max { lhs, rhs in
                        (lhs.createdAt ?? .distantPast) < (rhs.createdAt ?? .distantPast)
                    }
                    LocalNotificationCenter.shared.notifyChatCatchUp(
                        roomId: roomId,
                        roomName: roomName,
                        unreadCount: newOnes.count,
                        latestPreview: latest?.previewText ?? ""
                    )
                }
            } catch {
                NSLog("Chat catch-up failed: \(error)")
            }
        }
    }

```

- [ ] **Step 9: bootstrap/온보딩에서 닉네임 캐시 + 게이트 갱신**

Edit `Ping/AppDelegate.swift` — `bootstrapBackend()`의 다음 부분을 찾아서:

```swift
            if let existing {
                try await userService.upsert(uid: uid, nickname: existing.nickname)
                appState.currentUser = try await userService.get(uid: uid) ?? existing
                ClientEventService.shared.log("app_launched")
```

다음으로 교체:

```swift
            if let existing {
                try await userService.upsert(uid: uid, nickname: existing.nickname)
                appState.currentUser = try await userService.get(uid: uid) ?? existing
                SupabaseClient.shared.updateActiveNickname(existing.nickname)
                MultiAccountGate.updateUnlock(forNickname: existing.nickname)
                ClientEventService.shared.log("app_launched")
```

그리고 `showOnboarding`의 완료 클로저에서 다음을 찾아서:

```swift
                    try await self.userService.upsert(uid: uid, nickname: completion.nickname)
                    self.appState.currentUser = try await self.userService.get(uid: uid)
```

다음으로 교체:

```swift
                    try await self.userService.upsert(uid: uid, nickname: completion.nickname)
                    self.appState.currentUser = try await self.userService.get(uid: uid)
                    SupabaseClient.shared.updateActiveNickname(completion.nickname)
                    MultiAccountGate.updateUnlock(forNickname: completion.nickname)
```

- [ ] **Step 10: teardown + reload + 인텐트 핸들러 추가**

Edit `Ping/AppDelegate.swift` — `private func runCleanup(uid:)` 메서드의 닫는 `}` 다음(클래스 닫기 `}` 직전)에 추가:

```swift

    // MARK: - 계정 전환

    private func setupAccountSwitching() {
        let center = NotificationCenter.default
        center.addObserver(forName: .pingSwitchAccount, object: nil, queue: .main) { [weak self] note in
            let userId = note.userInfo?[AccountIntentKey.userId] as? String
            Task { @MainActor in
                guard let self, let userId else { return }
                await self.handleSwitchAccount(userId: userId)
            }
        }
        center.addObserver(forName: .pingAddAccount, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.handleAddAccount() }
        }
        center.addObserver(forName: .pingRemoveAccount, object: nil, queue: .main) { [weak self] note in
            let userId = note.userInfo?[AccountIntentKey.userId] as? String
            Task { @MainActor in
                guard let self, let userId else { return }
                await self.handleRemoveAccount(userId: userId)
            }
        }
    }

    /// 전환/추가 전 공통 정리: 옵저버·창·캐시·상태·인메모리 dedup.
    private func teardownForAccountChange() {
        roomObserverTask?.cancel(); roomObserverTask = nil
        invitationObserverTask?.cancel(); invitationObserverTask = nil
        incomingMessageTask?.cancel(); incomingMessageTask = nil

        if mirrorWindow != nil { closeMirrorWindow() }

        for window in playbackWindows { window.orderOut(nil) }
        playbackWindows.removeAll()
        playbackPrefetchTasks.values.forEach { $0.cancel() }
        playbackPrefetchTasks.removeAll()
        playbackCache.removeAll()

        notifiedChatMessageIds.removeAll()

        appState.currentUser = nil
        appState.rooms = []
        appState.pendingInvitations = []
        appState.resetTransientState()
        appState.pendingRoomFocusId = nil
        appState.lastSelectedRoomId = nil
    }

    private func canSwitchAccountNow() -> Bool {
        if isSwitchingAccount { return false }
        if mirrorWindow != nil, mirrorViewModel.state != .idle {
            showTransientAlert(
                title: "전송 중에는 계정을 전환할 수 없습니다",
                message: "영상 전송을 마친 뒤 다시 시도해주세요."
            )
            return false
        }
        return true
    }

    private func reloadForActiveAccount() {
        guard canSwitchAccountNow() else { return }
        isSwitchingAccount = true
        teardownForAccountChange()
        Task { @MainActor in
            await chatRealtime.unsubscribeAll()
            await bootstrapBackend()
            isSwitchingAccount = false
        }
    }

    private func handleSwitchAccount(userId: String) async {
        guard canSwitchAccountNow() else { return }
        do {
            try SupabaseClient.shared.switchTo(userId: userId)
            reloadForActiveAccount()
        } catch {
            showTransientAlert(title: "계정 전환 실패", message: error.localizedDescription)
        }
    }

    private func handleAddAccount() async {
        guard canSwitchAccountNow() else { return }
        isSwitchingAccount = true
        do {
            let uid = try await SupabaseClient.shared.addAccount()
            teardownForAccountChange()
            await chatRealtime.unsubscribeAll()
            showOnboarding(uid: uid)
        } catch {
            showTransientAlert(title: "계정을 추가하지 못했습니다", message: error.localizedDescription)
        }
        isSwitchingAccount = false
    }

    private func handleRemoveAccount(userId: String) async {
        let wasActive = SupabaseClient.shared.activeUserId == userId
        SupabaseClient.shared.removeAccount(userId: userId)
        if wasActive {
            // 활성이 바뀌었으면(남은 계정 또는 0개) 재로딩. 0개면 bootstrap이 새 익명 계정을 만든다.
            reloadForActiveAccount()
        }
    }
```

> `reloadForActiveAccount`는 `switchTo`로 `activeUserId`가 이미 바뀐 뒤 호출된다. `bootstrapBackend()`가 새 활성 uid로 프로필/옵저버를 재시작하고 캐치업을 유입시킨다. 활성 계정 삭제 후 남은 계정이 없으면 `bootstrapBackend` → `authenticatedSession` → `signInAnonymously` 경로가 새 익명 계정을 만들어 `save(session:)`로 등록한다.

- [ ] **Step 11: `setupAccountSwitching()` 호출 등록**

Edit `Ping/AppDelegate.swift` — `applicationDidFinishLaunching`의 다음을 찾아서:

```swift
        setupStatusBar()
        setupNotifications()
        setupHotkey()
```

다음으로 교체:

```swift
        setupStatusBar()
        setupNotifications()
        setupAccountSwitching()
        setupHotkey()
```

- [ ] **Step 12: 컨트랙트 테스트 통과 + 풀 빌드**

Run:
```bash
xcodegen generate >/dev/null
xcodebuild test -project Ping.xcodeproj -scheme Ping -destination 'platform=macOS' \
  -only-testing:PingTests/MultiAccountSwitchingContractTests 2>&1 | tail -30
```
Expected: 전 케이스 PASS. 컴파일 에러 없음(특히 `shouldNotify` 호출부, ledger 사용).

- [ ] **Step 13: 커밋**

```bash
git add Ping/AppDelegate.swift Ping/Core/AccountNotifications.swift PingTests/MultiAccountSwitchingContractTests.swift Ping.xcodeproj
git commit -m "feat(macos): account switch orchestration, catch-up, intents in AppDelegate"
```

---

## Task 8: 설정 "계정" 섹션 UI (게이트 조건부)

일반 탭 하단에 `MultiAccountGate.isUnlocked()`일 때만 보이는 "계정" 섹션을 추가한다. 계정 목록(닉네임+활성 체크), 전환(탭), 추가 버튼, 삭제(영구 손실 경고 후) — 모두 인텐트 알림으로 AppDelegate에 위임한다.

**Files:**
- Modify: `Ping/UI/Setup/SettingsScene.swift`
- Test: `PingTests/MultiAccountSwitchingContractTests.swift` (SettingsScene 컨트랙트 추가)

- [ ] **Step 1: 실패하는 컨트랙트 테스트 추가**

Edit `PingTests/MultiAccountSwitchingContractTests.swift` — `testAppDelegateBlocksSwitchWhileSending` 다음에 추가:

```swift
    func testSettingsAccountSectionIsGatedAndPostsIntents() throws {
        let source = try readSourceFile("Ping/UI/Setup/SettingsScene.swift")
        XCTAssertTrue(source.contains("@ObservedObject private var supabase = SupabaseClient.shared"))
        XCTAssertTrue(source.contains("MultiAccountGate.isUnlocked()"))
        XCTAssertTrue(source.contains("Notification.Name.pingSwitchAccount"))
        XCTAssertTrue(source.contains("Notification.Name.pingAddAccount"))
        XCTAssertTrue(source.contains("Notification.Name.pingRemoveAccount"))
        // 영구 손실 경고가 존재해야 한다.
        XCTAssertTrue(source.contains("복구할 수 없습니다"))
    }
```

- [ ] **Step 2: 테스트 실패 확인**

Run:
```bash
xcodegen generate >/dev/null
xcodebuild test -project Ping.xcodeproj -scheme Ping -destination 'platform=macOS' \
  -only-testing:PingTests/MultiAccountSwitchingContractTests/testSettingsAccountSectionIsGatedAndPostsIntents 2>&1 | tail -20
```
Expected: FAIL.

- [ ] **Step 3: `GeneralSettingsView`에 supabase 관찰 + 삭제 대상 상태 추가**

Edit `Ping/UI/Setup/SettingsScene.swift` — 다음을 찾아서:

```swift
private struct GeneralSettingsView: View {
    @EnvironmentObject private var appState: AppState
```

다음으로 교체:

```swift
private struct GeneralSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var supabase = SupabaseClient.shared
    @State private var accountPendingDeletion: StoredAccount?
```

- [ ] **Step 4: 본문에 "계정" 섹션 삽입**

Edit `Ping/UI/Setup/SettingsScene.swift` — `GeneralSettingsView.body`의 "프로필" 그룹 닫힘 다음을 찾아서:

```swift
                    settingsGroup("프로필") {
                        settingRow(
                            title: "닉네임",
                            subtitle: nicknameHelperText,
                            subtitleColor: nicknameError == nil ? .secondary : .red
                        ) {
                            HStack(spacing: 10) {
                                TextField("닉네임", text: $nicknameDraft)
                                    .textFieldStyle(.roundedBorder)
                                    .onSubmit(saveNickname)
                                    .disabled(appState.currentUser?.id == nil || isSavingNickname)
                                    .frame(width: 220)

                                Button("저장", action: saveNickname)
                                    .disabled(!canSaveNickname)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
```

다음으로 교체(프로필 그룹은 그대로 두고, 그 다음에 계정 섹션과 `.alert`를 추가):

```swift
                    settingsGroup("프로필") {
                        settingRow(
                            title: "닉네임",
                            subtitle: nicknameHelperText,
                            subtitleColor: nicknameError == nil ? .secondary : .red
                        ) {
                            HStack(spacing: 10) {
                                TextField("닉네임", text: $nicknameDraft)
                                    .textFieldStyle(.roundedBorder)
                                    .onSubmit(saveNickname)
                                    .disabled(appState.currentUser?.id == nil || isSavingNickname)
                                    .frame(width: 220)

                                Button("저장", action: saveNickname)
                                    .disabled(!canSaveNickname)
                            }
                        }
                    }

                    if MultiAccountGate.isUnlocked() {
                        accountSwitcherGroup
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .alert(item: $accountPendingDeletion) { account in
            Alert(
                title: Text("계정을 삭제할까요?"),
                message: Text("이 익명 계정은 복구할 수 없습니다. 이 기기에서 영구히 사라집니다."),
                primaryButton: .destructive(Text("삭제")) {
                    NotificationCenter.default.post(
                        name: .pingRemoveAccount,
                        object: nil,
                        userInfo: [AccountIntentKey.userId: account.userId]
                    )
                },
                secondaryButton: .cancel(Text("취소"))
            )
        }
```

- [ ] **Step 5: 계정 섹션 뷰 + 인텐트 헬퍼 구현**

Edit `Ping/UI/Setup/SettingsScene.swift` — `GeneralSettingsView`의 `private var nicknameHelperText: String { ... }` 정의 바로 앞에 추가:

```swift
    private var accountSwitcherGroup: some View {
        settingsGroup("계정") {
            ForEach(Array(supabase.accounts.enumerated()), id: \.element.userId) { index, account in
                if index > 0 {
                    Divider().opacity(0.45).padding(.leading, 16)
                }
                accountRow(account)
            }

            Divider().opacity(0.45).padding(.leading, 16)

            Button {
                NotificationCenter.default.post(name: .pingAddAccount, object: nil)
            } label: {
                Label("계정 추가", systemImage: "plus.circle")
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func accountRow(_ account: StoredAccount) -> some View {
        let isActive = supabase.activeUserId == account.userId
        let displayName = account.nickname.isEmpty ? "(닉네임 없음)" : account.nickname
        return HStack(spacing: 12) {
            Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary)

            Text(displayName)
                .font(PingFont.label)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 16)

            if account.userId != supabase.activeUserId {
                Button("전환") {
                    NotificationCenter.default.post(
                        name: .pingSwitchAccount,
                        object: nil,
                        userInfo: [AccountIntentKey.userId: account.userId]
                    )
                }
                .buttonStyle(.borderless)
            }

            Button(role: .destructive) {
                accountPendingDeletion = account
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .disabled(supabase.accounts.count <= 1)
        }
        .contentShape(Rectangle())
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

```

> 보안: 목록은 `supabase.accounts`(이 기기 `Accounts.json`)만 반영한다. 타인이 닉네임을 `영민`으로 입력해 게이트를 열어도 자신의 로컬(비어있는) 스위처만 보일 뿐, 오너의 세션/자격증명은 노출되지 않는다.

- [ ] **Step 6: 컨트랙트 테스트 통과 확인**

Run:
```bash
xcodegen generate >/dev/null
xcodebuild test -project Ping.xcodeproj -scheme Ping -destination 'platform=macOS' \
  -only-testing:PingTests/MultiAccountSwitchingContractTests/testSettingsAccountSectionIsGatedAndPostsIntents \
  -only-testing:PingTests/SettingsSceneContractTests 2>&1 | tail -30
```
Expected: 신규 케이스 PASS + 기존 `SettingsSceneContractTests` 회귀 없음.

- [ ] **Step 7: 커밋**

```bash
git add Ping/UI/Setup/SettingsScene.swift PingTests/MultiAccountSwitchingContractTests.swift Ping.xcodeproj
git commit -m "feat(macos): owner-only account switcher UI in Settings"
```

---

## Task 9: 전체 검증 + 수동 테스트 체크리스트

**Files:** 없음(검증 전용)

- [ ] **Step 1: 프로젝트 재생성 + 전체 테스트**

Run:
```bash
xcodegen generate >/dev/null
xcodebuild test -project Ping.xcodeproj -scheme Ping -destination 'platform=macOS' 2>&1 | tail -40
```
Expected: 전체 PASS. 특히 회귀 확인 대상:
- `SupabaseSessionContractTests` (레거시 세션 심볼/리프레시)
- `SettingsSceneContractTests` (기존 일반/정보 탭)
- `CompatibilityContractTests`, `SmokeTests`

- [ ] **Step 2: 릴리스 빌드 컴파일 확인**

Run:
```bash
xcodebuild build -project Ping.xcodeproj -scheme Ping -configuration Debug -destination 'platform=macOS' 2>&1 | tail -15
```
Expected: `BUILD SUCCEEDED`. Swift 6 동시성 경고/에러 없음.

- [ ] **Step 3: 수동 테스트 체크리스트 (실기기/디버그 실행)**

다음을 직접 확인(빌드된 앱 실행):

1. **마이그레이션**: 기존 단일 계정 사용자가 업데이트 후에도 같은 계정으로 로그인 유지(룸/프로필 그대로). `~/Library/Application Support/Ping/Accounts.json` 생성됨, `SupabaseSession.json`도 갱신됨.
2. **게이트 숨김**: 닉네임이 `영민`이 아니면 설정 → 일반에 "계정" 섹션 없음.
3. **게이트 노출/유지**: 닉네임을 `영민`으로 바꾸면 "계정" 섹션 등장. 이후 다른 계정(비-`영민`)으로 전환해도 섹션 유지.
4. **계정 추가**: "계정 추가" → 온보딩(닉네임+룸) → 새 계정으로 진입, 빈 룸 상태.
5. **전환 + 캐치업**: A↔B 전환 시 이전 계정 옵저버/리얼타임 정리, 새 계정 룸·초대 재로딩. B 비활성 동안 도착한 영상/초대/채팅이 B로 전환 시 알림으로 표시.
6. **중복 알림 없음**: 같은 계정으로 재전환해도 이미 본 알림은 다시 오지 않음(계정별 ledger). 채팅은 해당 룸을 열어 `markRoomRead` 후 재전환하면 사라짐.
7. **전송 중 가드**: 미러가 reviewing/uploading일 때 전환 시도 → "전송 중에는 계정을 전환할 수 없습니다" 알림, 전환 차단.
8. **삭제 경고**: 계정 삭제 시 "복구할 수 없습니다" 경고 다이얼로그. 확인해야만 삭제. 활성 계정 삭제 시 남은 계정으로 자동 전환(0개면 새 익명 계정 생성).
9. **보안**: 별도 사용자 환경에서 닉네임 `영민` 입력 → 빈 스위처만 보임(오너 계정 목록 비노출).

- [ ] **Step 4: 최종 검증 보고**

`superpowers:verification-before-completion`에 따라 Step 1~2의 실제 출력(PASS/BUILD SUCCEEDED)을 근거로 완료를 보고한다. 수동 항목 중 실행하지 못한 것은 미검증으로 명시한다.

---

## Self-Review

**1. Spec coverage (스펙 §별 매핑):**
- §4.1 `AccountStore`/`StoredAccount`/`AccountsFile`, 마이그레이션, 레거시 미러, 토큰 갱신 반영 → Task 1·2 (+ Task 3 `save(session:)`의 `upserting`).
- §4.2 `SupabaseClient` 발행 상태 + `addAccount`/`switchTo`/`removeAccount` → Task 3 (+ `updateActiveNickname`).
- §4.3 `reloadForActiveAccount()` 오케스트레이션, `addAccount` 온보딩 재사용 → Task 7.
- §4.4 캐치업: 영상(계정별 ledger), 초대(계정별 ledger), 채팅(신규 `catchUpChatNotifications` + 묶음 알림 + 계정별 dedup) → Task 4·6·7.
- §4.5 `영민` 게이트 + 설정 일반 탭 UI + 보안(로컬 목록만) → Task 5·8.
- §6 엣지: 전송 중 전환 차단(Task 7 `canSwitchAccountNow`), 갱신 실패 시 자동 삭제 안 함(기존 `supabaseSessionExpired` 유지, Task 3에서 미삭제), 활성 삭제 시 자동 전환/신규(Task 3·7), 마이그레이션 안전·다운그레이드 미러(Task 2), 닉네임 변경 시 unlock(Task 5·7 Step 9).
- §7 테스트: 단위(AccountsFile/AccountStore/NotificationLedger/MultiAccountGate) + 컨트랙트(SupabaseClient/AppDelegate/Settings/LocalNotificationCenter) + 수동(Task 9).

**2. Placeholder scan:** "TBD/적절히/등"류 없음. 모든 코드 스텝에 실제 코드/정확 경로/예상 출력 포함.

**3. Type consistency:** `StoredAccount(session:nickname:addedAt:)`, `AccountsFile.{adding,removing,switching,updatingNickname,upserting,migrating,activeAccount,empty}`, `AccountStore.{makeDefault,load,save}`, `SupabaseClient.{accounts,activeUserId,addAccount,switchTo,removeAccount,updateActiveNickname,accountsSnapshot,applyAccountsFile}`, `NotificationLedger.{Kind,contains,remember,ids}`, `MultiAccountGate.{isUnlocked,updateUnlock,unlockedKey,ownerNickname}`, `LocalNotificationCenter.notifyChatCatchUp(roomId:roomName:unreadCount:latestPreview:)`, `Notification.Name.{pingSwitchAccount,pingAddAccount,pingRemoveAccount}`, `AccountIntentKey.userId`, `AppDelegate.{reloadForActiveAccount,teardownForAccountChange,catchUpChatNotifications,handleSwitchAccount,handleAddAccount,handleRemoveAccount,setupAccountSwitching,canSwitchAccountNow,shouldNotify(messageId:uid:message:)}` — 태스크 간 일관 사용. `switchTo`는 `throws`(비-async)로 일관(Task 3 정의 ↔ Task 7 `try` 호출).
