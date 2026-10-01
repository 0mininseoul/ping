# Windows 설정·기기·설치 완성 계획

승인된 전체 Windows parity 전략의 후속 실행 계획이다. 기존 목표와 사용자 우선순위(사용 가능한 완성 제품과 EXE를 먼저, 세부 디자인·과도한 보강은 이후)를 유지한다. 캡처 milestone의 중요한 리뷰 결함을 먼저 해결하고 아래 순서로 실행한다. 추가 디자인 승인 단계는 필요하지 않다.

## 기준

- Mac 참고: `Ping/Core/UserPreferences.swift`, `Ping/UI/Setup/SettingsScene.swift`, `DevicePairingView.swift`, `Ping/Backend/DeviceHandoffPayload.swift`, `SupabaseClient.swift` 및 저장 계정 전환 구현.
- 기존 Windows 계정·룸·설정 경로와 MSIX identity/Publisher를 보존한다. 이메일·소셜 인증, 새로운 서버 또는 SQL 변경을 도입하지 않는다.
- Windows 시스템 폰트, 같은 16DIP 카드·상태 색·review/fade 의미를 유지한다. 일반 설정은 시스템/밝게/어둡게, 소리 기본/없음과 받은 영상 자동 재생을 제공한다.
- 실제 사용자 세션·장치 캡처·운영 backend를 테스트 fixture에 사용하지 않는다. 빌드/합성 검사와 실제 기기 QA 결과를 구분한다.

## 1. 사용할 수 있는 설정 창

- [x] 영어/한국어가 섞인 고정 크기 설정을 한국어 항목과 스크롤 가능한 일반·단축키·룸·저장·정보 탭으로 정리. 현재 DPI/work-area에 맞는 클라이언트 크기와 기존 닫기 동작 유지. 기기 탭은 실제 기능과 함께 Task 2에서 추가.
- [x] 소리와 외관을 기존 설정 파일에 하위 호환 필드로 저장. 외관을 기존/새 창에 적용하고 알림 무음을 실제 Windows 토스트 구성에 반영. 기존 핫키·저장·자동재생 값 보존.
- [x] 관련 순수 설정 저장/토스트 구성 검사, 실제 WinUI에서 선택·반영·스크롤을 합성 데이터로 확인하고 정상 Release 빌드. Commit `feat(windows-settings): add appearance and notification preferences`. 검증: `docs/windows/2026-10-01-settings-appearance-verification.ko.md`.

## 2. 기기 선택과 연결

- [x] 읽기 전용 장치 목록과 기본값/선택한 카메라·마이크를 제공한다. WinRT 카메라 ID와 MMDevice/WinRT 마이크 쌍을 명시적으로 대응시키며 문자열 추측 변환을 하지 않는다. 장치 없음/제거를 안내한다.
- [x] 선택을 다음 카메라 lease 생성에 고정해 얼굴·화면·빠른 전송·자동 회신에 동일하게 전달. 진행 중인 녹화를 설정 변경으로 교체하지 않는다.
- [x] Task 2A: 장치 선택·기존 JSON 보존·lease 고정과 실제 WinUI 선택/연결 끊김 검사 및 정상 Release 빌드. Commit `feat(windows-devices): add capture device selection`. 결과: `docs/windows/2026-10-01-capture-device-selection-verification.ko.md`. QR 연결은 Task 2B로 계속 진행한다.
- [x] 기기 탭을 열 때만 최신 인증 세션으로 Mac와 동일한 필드·날짜 형식의 QR handoff를 생성. QR을 로그/아티팩트/clipboard에 자동 기록하지 않고 닫기·계정 변경 시 제거. 기존 refresh-token 공유 계약을 보존한다.
- [x] 합성 ID/세션/QR decode와 기본값 마이그레이션 검사, 실제 WinUI 기기 UI fixture 및 Release 빌드. Commit `feat(windows-devices): add capture selection and device pairing`. Task 2B 결과: `docs/windows/2026-10-01-device-pairing-verification.ko.md`. 실제 iPhone/Watch 연결과 장치 녹화 QA는 Task 5에 남아 있다.

## 3. 계정과 업데이트 연결

- [ ] Mac 저장 계정 UX/세션 교체를 조사하고 현재 계정 유지·전환·명시적 새 계정 생성/제거를 구현한다. 전환 전에 송수신·카메라·알림 작업을 정리하고 계정별 ledger를 분리. 손상·갱신 실패에 자동 새 계정을 만들지 않는다.
- [ ] 정보 탭에 실제 Windows 버전과 업데이트 확인/실패/재시도/설치 동의 흐름을 제공. 다운로드·서명·버전 검증 후 설치하며 기존 계정/룸/설정은 유지. 존재하는 배포 URL/인증서를 조사하고 검증되지 않은 signer/주소로 자동 교체하지 않는다.
- [ ] owned account files/fake auth 및 update manifest/signature fixtures로 전환·실패·보존을 확인. Commit `feat(windows-account): add account management and update flow`.

## 4. 실제 EXE 산출물

- [ ] x64/ARM64 빌드 도구 확인. 현재 x64 SDK와 C++는 준비돼 있으나 ARM64 compiler가 확인되지 않았으므로 도구를 준비하거나 명시적인 결과를 기록한다.
- [ ] 기존 설치 EXE가 온라인 MSIX 다운로드에 의존하는 흐름을 번들 payload로 바꾼다. 필요한 런타임/dependency, 공개 Supabase 구성과 인증서 포함 여부를 검증. 구성/서명 재료가 없으면 완성된 패키징 단계와 정확한 누락 항목을 전달한다.
- [ ] 로그인 사용자의 패키지 등록·일반 권한 실행을 보장하고 필요한 인증서 신뢰 작업만 상승 권한으로 수행. 실제 작업 진행률, 실패·재시도·취소와 제거를 처리한다. 업데이트·재설치가 기존 데이터를 보존하고 데이터 삭제는 명시적 선택으로만 수행한다.
- [ ] Inno compiler로 실제 EXE 생성, payload/signature/dependency·오프라인 설치 경로 검사. 실제 시스템 신뢰/사용자 계정 설치 검증은 별도 기록하고 unsigned validation artifact를 공개 릴리즈라고 표시하지 않는다. Commit `feat(windows-installer): bundle complete offline setup payload`.

## 5. 릴리즈 후보 확인

- [ ] 주요 구현을 한 번 검토하고 검증된 중요한 결함만 우선 수정한다. 불필요하게 내부 fixture 행렬을 확대하지 않는다.
- [ ] Mac↔Windows 영상/채팅/이미지/답장/반응/초대/삭제/자동 회신, Windows 카메라·마이크·권한·DPI·설치/업데이트와 ARM64 실기 결과를 기록한다. 장치·계정·서명 자료가 필요한 남은 검사와 구현 완료를 구분한다.
- [ ] 사용자에게 실제 EXE 경로, 기능/설치 안내와 미검증 항목을 전달. 전체 목표는 실제 필요한 작업이 끝나기 전까지 완료로 표시하지 않는다.
