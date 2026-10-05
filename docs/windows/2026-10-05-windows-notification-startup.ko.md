# Windows 알림 활성화 등록 순서와 인자 해석

0.4.13 설치본의 직접 COM 활성화 검사에서는 실행 중 알림의 읽지 않음 상태가 유지됐고, 종료 상태의 COM 서버 실행은 `0x80080005`로 실패했다. 이를 실제 OS 알림 클릭 성공으로 기록하지 않는다. 이후 UI와 사용자 계정을 열지 않는 실제 Windows SDK 진단으로 두 결함을 재현했다.

1. `Program.DecideRedirection()`에서 알림 SDK 등록 전에 `GetActivatedEventArgs()`를 호출하면 첫 프로세스와 기존 프로세스로 전달할 보조 프로세스 모두 `0xC0000409`로 비정상 종료했다.
2. Ping의 `action=chat&chat_id=...&room_id=...` 문자열을 SDK 사전으로만 읽으면 `action` 값이 `chat&chat_id=...&room_id=...`가 돼 대화 동작을 찾지 못했다. 영상 알림도 같은 형식이다.

첫 프로세스는 인스턴스 키를 확보하고 앱을 구성한 뒤 기존 컨트롤러가 SDK를 등록한 다음 최초 알림을 읽는다. 보조 프로세스는 정확한 COM 실행 표식이 있는 경우 SDK를 임시 등록하고 알림 인자를 기존 프로세스로 전달한 뒤 등록을 해제한다. 일반 실행 경로에는 이 임시 등록을 추가하지 않았다. 컨트롤러 등록에 실패하면 최초 인자를 읽지 않는다.

완전한 Ping 쿼리 문자열은 원문으로 해석하고, SDK 빌더의 세미콜론 형식과 불완전한 원문은 SDK 사전으로 해석한다. 기존 중복 키와 잘못된 퍼센트 인코딩 방어를 유지한다. Microsoft의 [알림 시작 지침](https://learn.microsoft.com/en-us/windows/apps/develop/notifications/app-notifications/app-notifications-quickstart)은 알림 등록 이후 활성화 인자를 읽는 순서를 설명한다.

## 검증

파서 회귀 검사는 수정 전에 실패를 확인했고 수정 후 App348개가 통과했다. 보조 프로세스 검사도 수정 전 `0xC0000409` 실패 후 수정된 실제 메서드로 통과했다. 최종 소스의 격리 빌드와 일반 x64 Release 빌드는 경고0/오류0이다.

| 실제 네이티브 검사 | 결과 | 로컬 근거 |
|---|---|---|
| 첫 프로세스 등록, 최초 COM 인자 보존, 후속 COM 콜백 | 4개 통과 | `windows/artifacts/notification-startup-3ca7f98c5bd54a0689127b43c208e43f` |
| 두 프로세스의 실제 COM→AppLifecycle 전달과 정상 종료 | 2개 통과 | `windows/artifacts/notification-startup-8d64d7c690384a69a90aa0ec093578aa` |
| 기존 시작 큐 전달과 동시 전달 | 4개 통과 | `windows/artifacts/activation-94e51dd8f09a4790af3cc2327ee36487` |
| 보조 프로세스 수정 전 실패 | 재현 | `windows/artifacts/notification-startup-e1f2b53588aa49d0bbd00e1d920c1c9d` |

```powershell
windows/scripts/test-notification-startup.ps1
windows/scripts/test-notification-startup.ps1 -SkipBuild -Redirection
windows/scripts/test-activation-handoff.ps1 -SkipBuild
```

진단 전용 실행 파일은 UI나 사용자 계정을 열지 않으며 배포 패키지에 포함하지 않는다. 두 프로세스 검사의 주 프로세스는 AppLifecycle만 등록하므로 두 알림 COM 리스너가 경쟁하는 상황까지 검증하지 않는다. 실제 OS 클릭, 패키지 브로커 실행과 앱 전체 시작 흐름의 성공을 이 검사로 주장하지 않는다. 0.4.14 패키지 빌드 이후 설치본 검증이 남아 있으며 현재 설치본은0.4.13이다. 카메라·Mac 상대·ARM64 실제 기기 검증도 별도로 남아 있다.
