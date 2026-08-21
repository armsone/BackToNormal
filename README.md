# BackToNormal

개발 머신이 느려졌을 때 원인을 보여주고, 검증된 개발 자원만 사용자의 확인을 받아 정리하는 macOS 메뉴 바 앱입니다.

## 무엇을 하나

- 메뉴 바 아이콘으로 현재 상태 표시: 정상 / 주의 / 압박 / 확인 중
- 핵심 원인 한 줄과 사람이 읽는 설명 제공
- 측정값: CPU 부하(load average), 커널 메모리 압박 수준, 사용 가능 메모리, 스왑 사용량
- 데이터 볼륨 여유, CoreSimulator 기기 수·전체 용량, 테스트용 임시 복제본 의심 수,
  Xcode DerivedData와 XCTest 기기 데이터 용량 진단
- 현재 사용자 소유 프로세스 스냅샷(읽기 전용 `ps`)에서 개발 관련 프로세스 감지
  - Gradle / Kotlin 데몬 / Java / Node.js / Xcode 빌드 / 테스트 러너 /
    iOS 시뮬레이터 / Android 에뮬레이터 / ADB / 브라우저 자동화 / 로컬 서버
- 상세 창(측정값·진단·프로세스 목록)과 수동 새로고침, 30초 자동 새로고침
- 메모리 압박 시 실행 중인 시뮬레이터를 기기 데이터를 유지한 채 개별 종료하거나 활동 모니터로 일반 앱 확인
- 사용 불가 또는 종료된 테스트 복제 시뮬레이터를 개별 선택해 `simctl`로 삭제
- 종료된 정상 시뮬레이터의 데이터가 512 MiB 이상이면 기기는 남기고 앱·콘텐츠 데이터만 초기화
- 24시간 이상 수정되지 않은 개별 DerivedData 프로젝트와 7일 이상 된 종료 상태 XCTest 기기 데이터를 휴지통으로 이동
- 30분 이상 launchd에 재부착되어 있고 CPU 1% 이하·상주 메모리 64 MiB 이상인 명확한
  Gradle/Kotlin 데몬·테스트 러너·브라우저 자동화·로컬 개발 서버를 메모리 정리 후보로 제안
- 사용자가 선택한 프로세스는 실행 직전 소유자·PID·PPID·명령줄·경과 시간·자원 상태를 다시 확인하고
  정확한 PID 하나에만 `SIGTERM` 요청
- 수동으로 찾은 정리 후보는 기본 미선택, 최종 확인, 항목별 실행 직전 재검증과 결과 기록
- 정리 전후 메모리 압박·사용 가능 메모리·디스크 여유·스왑 관측값을 분리해 표시
- 보호한 파일·시뮬레이터·프로세스 실행 파일은 이후 제안에서 제외
- 최근 200건의 정리 결과를 로컬 Application Support에 저장
- `자동 정리`는 저위험·휴지통 복구 가능 파일만 즉시 정리하고, 시뮬레이터와 프로세스는 개별 선택·최종 확인 후 실행

## 무엇을 하지 않나 (안전 경계)

- 일반 Java·Node, Xcode, 시뮬레이터·에뮬레이터, ADB와 시스템 프로세스는 프로세스 종료 후보로 만들지 않습니다
- 실행 중인 iOS 시뮬레이터 기기는 별도 `simctl shutdown` 후보로만 제안하며 앱·콘텐츠 데이터는 지우지 않습니다
- 메모리 후보는 자동 선택하거나 자동 종료하지 않으며, `SIGKILL`·프로세스 그룹 종료·광범위한 데몬 중지 명령을 사용하지 않습니다
- 로컬 개발 서버는 의도적인 상시 실행 가능성이 높아 관찰만 하며 종료하지 않습니다
- 자동 정리는 확인 없이 복구 불가능한 시뮬레이터 정리나 프로세스 종료를 실행하지 않습니다
- 포트 자체를 닫지 않습니다
- 수동으로 찾은 정리 후보는 자동 선택하거나 자동 실행하지 않습니다
- DerivedData와 XCTest 데이터는 영구 삭제하지 않고 휴지통으로만 이동합니다
- 시뮬레이터 삭제는 복구 불가임을 확인 화면에 표시하며, 종료 상태를 다시 확인한 뒤 개별 UDID만 삭제합니다
- 관리자 권한을 요구하지 않습니다
- 스왑은 macOS가 스스로 관리하는 대상으로만 표시하며, 이 앱이 "정리"하지 않습니다
- 네트워크 접속과 AI 의존성이 없습니다 — 모든 판정은 코드에 고정된 결정적 규칙입니다

측정 사실과 추론은 화면에서 구분해 표시합니다. launchd에 재부착된 프로세스는
세션 근거가 없으므로 "고아"라고 단정하지 않고 불확실성을 명시합니다.

## 설치

GitHub Releases에서 공증된 `BackToNormal-1.2.1.dmg`를 받아 열고, 앱을 Applications로
드래그합니다. 앱을 실행하면 Dock 대신 메뉴 막대에 원상복구 아이콘이 나타납니다.

## 개발 빌드와 실행

macOS 13(Ventura) 이상, Xcode 15+ 툴체인이 필요합니다. 서드파티 의존성은 없습니다.

```sh
swift build          # 빌드
swift test           # 코어 로직 테스트 (파싱·분류·진단)
swift run BackToNormal   # 메뉴 바에 아이콘이 나타납니다
```

팀에서 프로젝트 로컬 캐시를 쓸 경우:

```sh
swift build --cache-path .build/cache --scratch-path .build
swift test  --cache-path .build/cache --scratch-path .build
```

SwiftPM 실행 파일이므로 앱 번들 없이 실행되며, Dock 아이콘은 코드에서
`.accessory` 정책으로 숨깁니다. 종료는 메뉴 바 팝업의 "종료" 버튼을 사용하세요.

공개 배포용 Universal DMG는 Developer ID 인증서와 기존 notarytool 프로필로 만듭니다.

```sh
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE="your-notary-profile" \
./Scripts/package-macos.sh --notarize
```

## 구조

```
Sources/BackToNormalCore/   # 순수 로직 (UI·시스템 호출 없음, 단위 테스트 대상)
  Models.swift              #   상태·지표·프로세스 모델
  PsParser.swift            #   ps 출력 파싱 (etime 포함)
  ProcessClassifier.swift   #   개발 프로세스 분류 규칙
  ProcessCleanupPolicy.swift #  메모리 정리 후보·재검증 규칙
  DiagnosticEngine.swift    #   결정적 진단 규칙 (임계값 고정)
Sources/BackToNormal/       # 앱 타깃
  MetricsCollector.swift    #   getloadavg · sysctl · Mach host 통계 (읽기 전용)
  ProcessCollector.swift    #   /bin/ps 읽기 전용 실행
  StorageCollector.swift    #   디스크·시뮬레이터·DerivedData 용량 읽기(10분 캐시)
  CleanupEvidenceCollector.swift # 정리 후보 근거 수집
  CleanupExecutor.swift     #   재검증 후 simctl 종료·삭제 또는 휴지통 이동
  ProcessCleanupExecutor.swift # 재검증 후 정확한 PID 하나에 SIGTERM 요청
  CleanupHistory.swift      # 보호 목록·정리 이력·실제 전후 지표
  MonitorViewModel.swift    #   수집→진단→화면 연결, 자동 새로고침
  BackToNormalApp.swift     #   MenuBarExtra + 상세 Window
  MenuContentView.swift / DetailView.swift
Tests/BackToNormalCoreTests/  # 파싱·분류·진단 정책 테스트
Tests/BackToNormalTests/      # 실제 실행 경계·이력 저장 테스트
```
