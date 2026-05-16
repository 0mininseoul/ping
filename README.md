# Ping

2초 영상 메시지 macOS 전용 앱. Option+P 한 번으로 친구에게 보낸다.

## Firebase 설정

이 앱에는 Firebase Admin SDK 비공개 키가 필요하지 않다. Firebase Console에서 Apple 앱을 Bundle ID `com.youngminpark.ping.Ping`로 등록한 뒤 `GoogleService-Info.plist`를 내려받아 `Resources/GoogleService-Info.plist`에 둔다. 이 파일은 git에 커밋되지 않는다.

## 설치

1. `Ping-v0.1.0.dmg`를 더블클릭해 마운트한다.
2. `Ping.app`을 Applications 폴더로 드래그한다.
3. 첫 실행은 우클릭 후 "열기"를 선택한다.
4. 카메라, 마이크, 알림 권한을 허용한다.
5. 닉네임을 입력한 뒤 룸을 만들거나 상대를 검색해 초대한다.

## 사용

- Option+P: 어디서든 거울을 띄운다.
- Enter: 2초 녹화 시작 후 자동 전송.
- Esc: 취소.
- Tab / 1~9: 파트너 전환.
- 0 또는 A: 전체 파트너에게 동시 발송.

## 시스템 요구사항

- macOS 26 Tahoe 이상
- Apple Silicon Mac (M1 이상)
