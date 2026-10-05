# Windows 설치 거부 후 보존과 재시도 검증

설치된0.4.14.0 / Status Ok에서 기존 CI의0.4.13 EXE를 실행했다. 두 EXE는 앞서 검증한 SHA-256과 일치한다. `VERYSILENT`, `SUPPRESSMSGBOXES`, `NORESTART`와 시작 메뉴 task만 사용했으며 앱 실행 task는 선택하지 않았다. 사용자 계정으로 네트워크 인증하거나 Ping 창에 입력하지 않았다.

Windows의 실제 `Add-AppxPackage`는 이미 더 최신 버전이 설치돼 있어 `0x80073D06`으로 이전 버전 등록을 거부했다. EXE는 exit3으로 종료했다. 실패 직후 다음을 확인했다.

- 설치된 버전은0.4.14.0 / Status Ok다.
- 일반 저장소 네 파일과 패키지 런타임 저장소 세 파일의 해시·길이가 이전 기준과 같다. 세션/백업은 최초 계정 기준과도 일치한다.
- DISPLAY3 배치 값, 설치된 App/Core/native DLL/Pretendard/OFL 해시가 유지됐다.
- 시작 메뉴·제거 프로그램의 등록 버전과 계정 보존/제거 스크립트가 정상이다.
- Ping 프로세스는 실행되지 않았다.

이후0.4.14 EXE를 다시 실행했고 exit0으로 완료됐다. 동일한 검사에서 계정 파일7개, 설치 파일과 등록 상태가 다시 일치했다. 소스 수정이나 새 패키지 생성 없이 실제 실패·재설치 경로를 확인했다.

근거는 `windows/artifacts/deployment-retry-0414-82b8a708fcfa4ca0aeed1d449ebd61f4`의 `before-verification.json`, `failure-process.json`, `after-failure-verification.json`, `retry-process.json`, `after-retry-verification.json`과 두 설치 로그다. 현재 설치본과 파일은 [0.4.14 후보](2026-10-05-windows-0.4.14-candidate.ko.md)를 따른다.

## 검증 범위

이 결과는 유효하게 서명된 이전 버전 패키지를 Windows가 실제로 거부한 경우의 보존과 현재 EXE 재실행이다. 설치 UI의 Retry 버튼 클릭, 파일 교체 중 강제 종료, 디스크 부족, 기존 프로세스 점유와 MSIX staging 중 rollback을 검증한 것은 아니다. 설치 중간 실패 복구 전체를 완료로 표시하지 않는다.
