# Windows 메신저 창 위치 복원

메신저가 마지막 일반 창의 모니터·위치·논리적 크기를 기억한다. 다시 실행할 때 해당 모니터로 복원하고, 모니터가 없으면 주 모니터의 작업 영역 안으로 보정한다. 위치는 작업 영역의 남은 이동 거리 비율, 크기는 DIP로 저장해 해상도·배율 변경을 처리한다. 최소화·최대화는 일반 창 배치를 덮어쓰지 않는다. 이는 Windows 사용성 개선이며 Mac에 동일한 저장 동작이 있다고 주장하지 않는다.

`MessengerWindowPlacement.json`은 기존 사용자 데이터 경로에 작은 version1 JSON으로 저장한다. 손상·읽기 실패는 기본 크기로 복원하고, 쓰기 실패는 창 사용을 막지 않는다. 설치·제거·재설치 데이터 보존 목록에도 포함했다. 진단 빌드의 기본 저장소는 비활성화하며, native fixture는 자기 출력 디렉터리만 사용한다. macOS 소스, Pretendard와 대화 화면 디자인은 변경하지 않았다.

## 검증

- 순수 배치/저장 검사5개를 행동 실패 RED → GREEN으로 확인했다. 전체 Core285/App344가 통과했다.
- DISPLAY3에서 실제 WinUI313개가 통과했다. 창 이동·크기 변경, 숨기기, 새 창 복원, 최소화·최대화 후 일반 크기 복원을 포함한다. 결과: `windows/artifacts/ui-shell-3a18b08d48624df1835e7f86994d0721/result.json`.
- `Save-PingUserData`/`Restore-PingUserData`를 소유한 임시 프로필에 실행해 가상 경로의 배치 파일이 물리 경로로 바이트 그대로 복원됨을 확인했다. 원래 계정 파일은 사용하지 않았다. 결과: `windows/artifacts/placement-retention-e9b2eb76462b47ce93d5d7cf374bdebb/result.json`.
- 정상 Release 빌드는 경고0/오류0이다. 독립 코드 검토에서 Critical/Important 결함은 발견하지 못했다.

첫 native 실행은 이 런타임의 `DisplayArea.FindAll()` projected enumerator 오류를 드러냈고, Count/index 복사로 해결했다. 배치 fixture를 기존 UI 검사 중간에 넣으면 활성화에 따른 대화 새로고침이 이전 행 참조 검사를 방해해 fixture를 마지막에 배치했다. 이후 전체 검사에 56초가 소요된 시점에서 추가 timer 검사가 기존60초 runner 제한에 잘려 제한을120초로 조정했다. 별도 실행의 native drag 시작 실패도 기록했다. 위 성공 결과는 예외를 무시하거나 검사를 생략하지 않은 전체 실행이다.

실제 모니터는100% 배율이다.150%·200% 배율과 음수 좌표는 순수 geometry 검사이며 실제 혼합 DPI 장치 검증은 남아 있다. 카메라·마이크 촬영, Mac 상대 송수신, ARM64 실기, 설치본의 실제 알림 클릭/cold activation 및 업데이트 실패 복구는 이번 검증에 포함되지 않는다.
