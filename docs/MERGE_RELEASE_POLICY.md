# 머지 사용자별 웹·DB 릴리즈 운영

| 실제 main PR 머지 사용자 | 처리 |
|---|---|
| 0mininseoul (ID 229801971) | Mac에서 승인 SQL 확인/적용 → 원격 이력 확인 → Vercel 원격 빌드 → 최신 커밋일 때 운영 배포 |
| 다른 사용자 | Vercel Git 자동 배포. SQL 변경이 있으면 본인에게 GitHub Issue 할당. SQL은 보류 |

## 키와 실행 위치

Supabase 관리 토큰과 Postgres 비밀번호는 이 Mac login Keychain에만 있다. GitHub Actions에는 Supabase 키나 Vercel 배포 토큰을 저장하지 않는다. Actions는 저장소 checkout 없이 GitHub API로 Issue만 만든다. Vercel Git 연결과 서버 설정의 Ignore Build Step이 실제 머지 사용자별로 분기한다. 확인 실패/직접 push는 운영 Git 배포를 보류한다. Preview는 마이그레이션 없이 빌드된다.

Mac 실행기는 `~/Library/Application Support/Ping Release Coordinator/`에 별도 설치한다. 저장소 밖의 고정 코드를 자동 작업이 호출한다. 실행기는 Git의 고정 commit/blob을 읽고 SQL 해시를 검증하며, 저장소의 설치/빌드/배포 스크립트를 Mac에서 실행하지 않는다. Vercel 소스는 임시 디렉터리에 안전하게 추출해 원격 빌드한다. 다른 사람이 Mac 파일/Keychain에 직접 접근할 수 있는 경우까지 막는 하드웨어 바인딩은 아니다.

## 최초 설치

검토된 커밋의 실행기를 이 Mac에 설치한다.

```bash
python3 scripts/install-release-coordinator.py
```

설치 시 main의 SQL 버전과 원격 적용 이력이 일치해야 한다. 초기 기준점 이전 머지는 소급 실행하지 않는다. 기존 승인 상태가 있으면 설치를 중단하며 승인 목록을 초기화하지 않는다. 코드 갱신은 본인 검토 후 설치본만 교체하고 `state.json`을 보존한다. CLI/프로젝트/Keychain 대상은 고정되어 있다.

## 보류 승인

1. Issue에 표시된 PR, merge SHA, SQL 파일별 SHA256을 검토한다.
2. 0mininseoul 계정으로 Issue에 표시된 명령을 단독 댓글로 작성한다.

```text
/ping-approve-migrations <merge SHA> <manifest SHA256>
```

3. 다음 Mac 작업에서 작성자 ID와 정확한 SHA/내용 해시를 검증해 적용한다. 다른 사용자의 댓글, 본문 편집, 라벨 변경, Issue 닫기는 승인이 아니다.

새 본인 머지는 그 PR에서 변경한 SQL만 승인한다. 이전 다른 사용자 머지의 보류 SQL은 자동 승인되지 않는다. SQL 내용이 변경되면 이전 승인은 무효다. 오래된 미승인 SQL이 뒤의 승인 SQL보다 먼저 와야 하는 경우 뒤 SQL과 본인 배포를 보류한다. 승인 SQL과 이미 적용된 SQL만 포함한 별도 workdir에서 `supabase-ping.sh db push`를 실행한다. 일괄 main DB push로 이 절차를 우회하지 않는다.

## 재시도와 장애

Mac이 꺼지거나 잠자기 상태이면 본인 마이그레이션/후속 배포는 대기한다. 다른 사용자 Vercel Git 배포와 Issue 생성은 클라우드에서 계속 동작한다. 관리 토큰 만료/Keychain 오류/SQL 실패 시 본인 배포를 진행하지 않는다. 원격 이력으로 성공을 확인한 SQL은 재실행하지 않는다. Vercel 실패는 마이그레이션을 반복하지 않고 배포만 재시도한다. 새 main이 이미 있으면 오래된 본인 커밋으로 운영을 되돌리지 않는다.

Supabase 관리 토큰은 2026-10-14 만료 예정이며, 갱신도 이 Mac Keychain에서만 해야 한다. 키를 `.env`, 로그, GitHub Secrets/Variables, 공유 connector로 옮기지 않는다. 실행기는 raw CLI/auth 출력을 GitHub에 게시하지 않는다.

다른 사용자 변경은 새 DB 스키마가 적용되기 전에도 기존 스키마에서 동작해야 한다. 이 정책은 마이그레이션 권한을 제한하며 Vercel의 서버 secret 키를 사용하는 코드의 데이터 권한까지 개인에게 독점시키지는 않는다. 다른 기기에서 같은 GitHub 계정으로 머지해도 같은 사용자로 판단한다.

## 네이티브 앱 릴리즈

이 정책은 Vercel 웹·푸시 서버와 Supabase 변경용이다. Mac 변경은 서명/공증/DMG·Sparkle 배포, Windows 변경은 설치파일 CI 게시, iPhone/Watch 변경은 App Store 업로드/심사/출시가 별도로 필요하다. Cloudflare/OCI 배포는 현재 저장소의 릴리즈 단계에 없다.
