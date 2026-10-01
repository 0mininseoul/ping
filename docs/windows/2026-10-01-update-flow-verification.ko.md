# Windows 업데이트 연결 검증

정보 탭에 실제 설치된 MSIX 버전, 업데이트 확인·재시도·설치 동의·다운로드 취소를 연결했다. 기존 `https://0minping.vercel.app/downloads/windows/latest-version.txt`와 아키텍처별 패키지/의존성 목록을 사용한다. 확인한 현재 공개 Windows 버전은 0.3.46이다. 합성 검사에서 쓰는 0.3.80은 실제 공개 Windows 릴리즈를 뜻하지 않는다.

버전은 숫자로 비교하며 더 낮은 버전은 제안하지 않는다. 패키지의 앱 이름·Publisher·버전·아키텍처를 검사하고, Windows Authenticode 검증 결과와 기존 Ping 인증서 thumbprint를 확인한다. 의존성은 같은 배포 경로의 제한된 상대 경로만 허용하고 Microsoft의 신뢰된 서명을 검사한다. 다운로드 실패·취소·검증 실패 시 해당 작업이 만든 파일을 정리한다.

승인한 업데이트의 준비가 끝나면 계정 전환과 같은 종료 경로로 기존 인증·송수신·캡처를 정리한다. 번들에 포함된 로컬 helper를 작업 디렉터리에 복사해 일반 사용자 권한으로 실행하며, Ping 종료를 기다리고 서명/앱 ID/버전을 다시 검사해 `Add-AppxPackage`를 호출한다. 인증서 자동 교체, 데이터 초기화, 강제 downgrade는 하지 않는다. 적용 오류는 결과 파일과 안내를 남기고 기존 설치된 Ping을 다시 연다.

기준 문서: [Microsoft의 MSIX 앱 자체 업데이트](https://learn.microsoft.com/en-us/windows/msix/non-store-developer-updates), [Get-AuthenticodeSignature](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.security/get-authenticodesignature).

검증 결과:

- Core Release 271개, App Release 312개 통과. 숫자 버전 비교, 잘못된 서명/앱 manifest 거부, 의존성 경로 탈출 거부, 정상 준비, 실패/취소 UI 재시도를 합성 HTTP·소유한 임시 파일로 확인했다.
- 실제 WinUI 165개 통과. 정보 탭 버전 binding, 확인 실패/재시도, 설치 확인창의 취소/승인을 실제 컨트롤로 검사했다. 설치 callback은 fixture를 사용했으며 시스템에 패키지를 등록하지 않았다. 결과: `windows/artifacts/ui-shell-19464135ddec41f6b84a9685a2d20ae2`.
- Windows PowerShell 5.1 helper의 검증 전용 경로로 기존 공개 0.3.46 MSIX 및 Microsoft runtime 서명을 검사해 통과했다. 다른 버전과 다른 thumbprint는 각각 exit 1로 거부했다. `windows/artifacts/update-probe-a5bbec3ddd514d3f95e34b67c3c68064`에 기록했다.
- 정상 x64 Release 빌드: 경고 0개, 오류 0개.

실제 사용자 설치/업데이트 및 Mac 간 기기 QA는 아직 실행하지 않았다. 새 배포 패키지와 EXE는 Task 4에서 준비한다. GitHub Secrets 이름 조회로 기존 서명/공개 backend 구성용 Secrets가 있음을 확인했으며, 개인키 값을 조회하거나 출력하지 않았다. 새 인증서를 허용한다는 사용자 지시는 기록했으나 현재는 기존 CI 서명 구성을 활용할 수 있어 인증서를 교체하지 않았다.
