# 머지 사용자별 릴리즈 정책 구현 계획

사용자가 승인한 정책을 이 세션에서 직접 구현한다. 관리 키는 이 Mac의 Keychain에만 유지한다.

목표: 0mininseoul이 main에 PR을 머지하면 승인된 마이그레이션 성공 후 Vercel 배포. 다른 사용자가 머지하면 Mac과 무관하게 Vercel Git 배포, SQL 변경은 본인에게 GitHub Issue로 할당.

구조: GitHub Actions는 비밀 키 없이 Issue를 만든다. Vercel Git 배포의 ignore 단계는 GitHub API에서 실제 merged_by ID를 확인해 본인 머지의 즉시 배포를 보류한다. 저장소 밖에 설치된 Mac 실행기는 PR을 재조회하고 SQL 파일/내용 해시를 승인 목록과 대조한다. 완료 후 Vercel CLI가 원격 빌드로 배포한다. Mac에서 저장소의 빌드 스크립트는 실행하지 않는다.

- [ ] scripts/tests/test_release_policy.py: 다른 사용자 승인 위조, 보류 SQL 섞임, 중복 처리, 내용 변경, 실패 시 배포 금지, 순서 의존성 및 경로 검증 테스트를 먼저 작성하고 실패 확인.
- [ ] scripts/release_policy/policy.py: 고정 owner ID, SHA256 manifest, 승인 코멘트 및 적용 가능한 순서 계산 구현.
- [ ] scripts/tests/vercel_merge_gate.test.mjs와 scripts/vercel-merge-gate.mjs: 실제 merge_commit_sha/merged_by 기준 분기 및 API 실패 시 보류 테스트/구현.
- [ ] .github/workflows/migration-approval.yml: 다른 사용자의 main 머지 중 SQL 변경만 Issue 생성. 본인에게 할당하고 같은 PR의 중복 Issue 방지. 저장소 코드 checkout/실행 및 Supabase 자격 증명 없음.
- [ ] scripts/release_policy/adapters.py: GitHub API, bare Git 캐시, 안전한 파일 추출, 로컬 Keychain API 조회, 승인된 SQL만 포함하는 임시 CLI 작업 경로 및 Vercel 원격 배포.
- [ ] scripts/release_policy/runner.py: 로컬 승인 목록/재시도 상태를 저장하고 Mac 재시작 후 이어서 처리. GitHub Issue를 닫는 것만으로 승인하지 않는다.
- [ ] 로컬 설치 및 Codex heartbeat: 관리 실행기와 wrapper를 Application Support에 복사해 고정. 저장소에서 자동 업데이트하지 않음. 잠자기/오프라인일 때 본인 마이그레이션·배포는 대기.
- [ ] GitHub/Vercel 연결 활성화, 실제 본인 PR 머지로 배포 보류→마이그레이션 확인→배포 흐름 검증. 다른 사용자 분기는 위조 계정을 사용하지 않고 테스트 fixture로 검증.
- [ ] AGENTS.md 및 운영 가이드 갱신, commit/push, 운영 URL 검증.

보류 승인: Issue에 표시된 `/ping-approve-migrations <merge SHA> <manifest SHA256>`를 0mininseoul 계정으로 댓글 작성. 파일 내용이 바뀌면 승인은 무효. 앞선 미승인 SQL이 뒤의 승인 SQL보다 오래되면 뒤 SQL 및 본인 배포를 보류하고 Issue에 사유 기록.

기존 53개 SQL은 원격 적용 기록과 모두 일치함을 시작 전에 확인했다. 새 실행기의 초기 기준점 이전 머지는 재실행하지 않는다. 이후 비PR push는 자동 마이그레이션/운영 배포 대상이 아니다.

한계: GitHub 계정 기준이며 물리적 기기를 구분하지 않는다. 서버 코드 배포 권한을 가진 co-author는 서버 secret 키의 권한을 간접적으로 사용할 수 있다. 이 정책은 관리자 키와 마이그레이션 실행을 통제한다. 새 스키마가 없는 동안에도 동작하는 서버 코드만 다른 사용자 자동 배포에 사용해야 한다. 네이티브 앱 서명/공증/스토어 심사 과정은 이 웹·DB 정책과 별개다.
