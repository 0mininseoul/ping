# 자동 업데이트(Sparkle) 1회 셋업

Ping은 [Sparkle 2](https://sparkle-project.org/) 로 사용자 측 자동 업데이트를 제공한다.
한 번 EdDSA 키 페어를 만들고 공개키를 `project.yml`에 박아 두면, 이후 릴리스는
`scripts/build-release.sh` 만 실행하면 자동으로 서명된 DMG + `appcast.xml` 까지 생성된다.

## 1. 한 번만 — EdDSA 키 생성

```bash
./scripts/sparkle-generate-keys.sh
```

이 스크립트는 SPM이 다운로드한 Sparkle CLI(`generate_keys`)를 실행한다.
실행하면 **개인키는 macOS 로그인 Keychain에 저장**되고, **공개키 한 줄**이 stdout에 찍힌다.

## 2. 공개키 박기

`project.yml` 의 `SUPublicEDKey` 값을 1번에서 출력된 공개키로 교체한 뒤
`xcodegen generate` 를 실행한다. `Ping/Info.plist` 는 XcodeGen 산출물이므로 직접 편집하지 않는다.

> 공개키는 git에 커밋해도 안전하다. 개인키는 Keychain 밖으로 내보내지 말 것.

## 3. 릴리스

```bash
./scripts/build-release.sh
```

빌드 스크립트가 자동으로 처리하는 것:

1. 앱 빌드 + ad-hoc 코드사인.
2. DMG 생성, `dist/Ping-v<VERSION>.dmg` + `web/public/downloads/Ping-v<VERSION>.dmg` 복사.
3. `generate_appcast` 가 `web/public/downloads/` 의 DMG를 스캔하고, Keychain의
   개인키로 각 DMG를 EdDSA 서명한 뒤 `web/public/appcast.xml` 을 생성한다.

이후 Vercel에 배포하면 `https://ping0min.vercel.app/appcast.xml` 에서 appcast가 노출되고,
`Ping/Info.plist` 의 `SUFeedURL` 이 이 주소를 가리키므로 사용자 앱이 자동으로 폴링한다.

## 4. 사용자 측 동작

- 앱 실행 시 Sparkle이 백그라운드로 appcast을 폴링한다 (`SUScheduledCheckInterval = 86400` = 24시간).
- 새 버전 감지 → 표준 Sparkle 다이얼로그가 떠서 다운로드/설치/재시작까지 자동 진행.
- `SUAutomaticallyUpdate = true` 라 사용자가 한 번 동의하면 이후 무음 업데이트도 가능.
- 메뉴바 → "업데이트 확인…" 으로 수동 강제 체크도 가능.

## 5. 첫 릴리스 주의

- 현재 v0.1.0 사용자는 Sparkle이 번들되지 않았기 때문에 자동 업데이트를 받지 못한다.
  새 DMG를 수동으로 다운로드해야 v0.1.x (Sparkle 포함) 로 갈 수 있다.
- 다음 버전부터는 자동 업데이트가 작동한다. 따라서 `project.yml` 의 `MARKETING_VERSION`
  과 `CURRENT_PROJECT_VERSION` 을 새 릴리스마다 올리는 것을 잊지 말 것.

## 6. Sandbox 호환

`com.apple.security.app-sandbox` 가 켜진 상태에서 Sparkle 2는
`SUEnableInstallerLauncherService` 옵션과 함께 동작한다.
`InstallerLauncher.xpc` 가 Sparkle 프레임워크 안에 번들된 채로 앱에 임베드되어,
샌드박스 밖의 권한이 필요한 설치 작업은 이 XPC 서비스가 대신 수행한다.

## 7. ad-hoc 서명과 EdDSA

Ping은 Developer ID 코드 서명을 사용하지 않고 ad-hoc 서명 (`-`) 만 사용한다.
이 환경에서도 Sparkle은 EdDSA 서명만으로 업데이트의 진위를 검증한다. 즉
`SUPublicEDKey` 가 박힌 현재 앱 → 동일 키로 서명된 새 DMG 만 신뢰한다.
공격자가 임의 DMG로 사용자 앱을 속이려면 개인키(Keychain)가 필요하다.

ad-hoc 서명 + hardened runtime 에서는 Sparkle.framework 로드 시 Team ID 검증이
걸리므로 `com.apple.security.cs.disable-library-validation` entitlement가 필요하다.
Developer ID 서명으로 전환하면 이 항목은 다시 검토할 것.
