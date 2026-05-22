# Ping

3초 영상 메시지 macOS 13 Ventura 이상 메뉴바 앱. Option+P 또는 Option+L 한 번으로 친구에게 보낸다.

## Supabase 설정

이 앱은 Supabase Anonymous Auth, Postgres RPC, 비공개 Storage 버킷 `ping-videos`를 사용한다. Supabase 프로젝트의 Project URL과 anon public key를 `Resources/Supabase.plist`에 넣는다. 이 파일은 git에 커밋되지 않는다.

```bash
cp Resources/Supabase.example.plist Resources/Supabase.plist
```

`Resources/Supabase.plist`:

```xml
<key>SUPABASE_URL</key>
<string>https://YOUR_PROJECT_REF.supabase.co</string>
<key>SUPABASE_ANON_KEY</key>
<string>YOUR_SUPABASE_ANON_KEY</string>
<key>PING_INVITE_BASE_URL</key>
<string>https://ping0min.vercel.app</string>
```

스키마는 `supabase/migrations/20260517000100_create_ping_backend.sql`에 있다. 원격 프로젝트에 연결한 뒤 적용한다.

```bash
npx supabase link --project-ref YOUR_PROJECT_REF
npx supabase db push
```

Supabase Dashboard의 Authentication 설정에서 Anonymous sign-ins가 켜져 있어야 한다.

## 설치

1. `Ping-v0.3.15.dmg`를 더블클릭해 마운트한다.
2. `Ping.app`을 Applications 폴더로 드래그한다.
3. 첫 실행은 우클릭 후 "열기"를 선택한다.
4. 카메라, 마이크, 알림 권한을 허용한다.
5. 닉네임을 입력한 뒤 룸을 만들거나 상대를 검색해 초대한다.

## 사용

- Option+P: 얼굴만 거울을 띄운다.
- Option+L: 화면+얼굴 거울을 띄운다.
- Option+O: 내 룸/히스토리 창을 연다.
- Enter: 녹화 시작. 리뷰 화면에서 다시 누르면 전송.
- Backspace: 리뷰 화면에서 다시 찍기.
- Esc: 취소 또는 닫기.
- Tab / 1~9: 파트너 전환.
- 0 또는 A: 전체 파트너에게 동시 발송.
- 내 룸 > 초대링크 복사: 앱을 아직 설치하지 않은 상대에게 초대 링크를 보낸다.

## 자동 업데이트

Ping은 Sparkle로 업데이트를 확인한다. 새 버전이 공개되면 알림과 표준 업데이트 다이얼로그가 뜨고, 사용자가 승인하면 바로 다운로드/설치/재시작 흐름으로 진행된다.

## 시스템 요구사항

- macOS 13 Ventura 이상
- Apple Silicon Mac 권장
