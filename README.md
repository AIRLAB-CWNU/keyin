# ShiftSpaceMac ⌨️

macOS 메모리 상주형 한영 전환 유틸리티 — `Shift + Space`로 빠르고 직관적인 한영 전환

## ✨ 기능

- **Shift + Space** 단축키로 시스템 전역 한영 전환
- 한글 입력 시 커서 옆에 **"한" 인디케이터** 표시
- 메뉴바 상주 (Dock에 나타나지 않음)
- 로그인 시 자동 실행 지원
- 모든 데스크탑 Space 및 전체 화면 앱에서 작동

## 📋 요구 사항

- macOS 13 (Ventura) 이상
- Swift 5.9+
- 접근성 권한 (시스템 설정에서 허용 필요)

## 🚀 빌드 및 실행

```bash
# 빌드
swift build

# 실행
swift build && .build/debug/ShiftSpaceMac

# 또는 빌드 스크립트 사용
chmod +x build.sh
./build.sh run
```

### .app 번들 생성

```bash
./build.sh app
# → build/ShiftSpaceMac.app 생성

# 실행
open build/ShiftSpaceMac.app
```

## 🔐 권한 설정

앱 최초 실행 시 **접근성 권한**을 허용해야 합니다:

1. 시스템 설정 → 개인정보 보호 및 보안 → 접근성
2. ShiftSpaceMac을 찾아 토글 활성화
3. (필요 시) 입력 모니터링도 동일하게 허용

> **⚠️ 재빌드하면 권한이 풀립니다 — 인증서로 서명하세요.**
>
> `build.sh`는 기본적으로 ad-hoc 서명(`codesign --sign -`)을 적용하는데, 이 경우 TCC가 바이너리
> 해시로 앱을 식별하므로 **재컴파일할 때마다 접근성 권한이 무효가 됩니다.** 목록에 앱 이름이 남아
> 있어도 실제로는 거부 상태라, 증상은 "Shift+Space가 아무 반응이 없음"으로 나타납니다
> (이벤트 탭 생성 자체가 실패합니다).
>
> 개발 인증서를 지정하면 식별자가 고정되어 이 문제가 사라집니다:
>
> ```bash
> security find-identity -v -p codesigning          # 인증서 목록 확인
> export CODESIGN_IDENTITY="Apple Development: ..."  # 사용할 인증서
> ./build.sh app
> ```
>
> 이미 권한이 꼬였다면 초기화 후 다시 승인하세요:
> `tccutil reset Accessibility com.keyin.ShiftSpaceMac`

## 📦 다른 맥으로 옮기기

`.app`을 복사만 하면 대개 동작하지 않습니다. 아래를 순서대로 확인하세요.
진단 스크립트가 이 항목들을 자동으로 점검합니다:

```bash
./scripts/diagnose.sh /Applications/ShiftSpaceMac.app
```

| 확인 항목 | 증상 | 해결 |
|---|---|---|
| **아키텍처** | 아예 실행되지 않음 | Apple Silicon에서 만든 기본 빌드는 **arm64 전용**이라 Intel 맥에서 Rosetta로도 실행 불가. `UNIVERSAL=1 ./build.sh app` 으로 빌드 |
| **접근성 권한** | 앱은 뜨는데 Shift+Space 무반응 | 맥마다 따로 승인해야 함. TCC는 머신 간에 공유되지 않음 |
| **격리 속성** | "확인할 수 없는 개발자" 경고 | AirDrop·다운로드로 옮기면 quarantine이 붙음 → `xattr -dr com.apple.quarantine <경로>` |
| **LaunchAgent 경로** | 로그인 시 자동 실행이 안 되거나 엉뚱한 앱이 뜸 | plist에 **원본 맥의 절대 경로**가 박혀 있음. 메뉴바에서 자동 실행을 껐다 켜서 재등록 |
| **인스턴스 중복** | 전환이 되다 말다 함 | 두 사본이 동시에 실행되면 서로 이벤트를 가로챔. `pgrep -fl ShiftSpaceMac`로 1개인지 확인 |
| **입력 소스 구성** | 감지는 되는데 전환이 안 됨 | 대상 맥에 한국어 입력 소스가 있어야 하고, 시스템 단축키 **'이전 입력 소스 선택'이 활성**이어야 함 (이 앱은 그 단축키를 재생하는 방식) |

> 이 앱은 공증(notarization)되지 않았습니다. 개인 용도로 직접 빌드해 쓰는 것을 전제로 합니다.

### 로그 확인

앱은 메뉴바 상주 에이전트라 stdout이 어디에도 보이지 않습니다. 대신 `os.Logger`로
시스템 로그에 남기므로, 어느 맥에서든 아래로 상태를 확인할 수 있습니다.

```bash
# 시작 시 권한·이벤트 탭 상태 (zsh의 log 빌트인과 겹치므로 절대 경로로 호출)
/usr/bin/log show --last 10m \
  --predicate 'subsystem == "com.keyin.ShiftSpaceMac"' --style compact

# Shift+Space를 누르며 실시간 관찰
/usr/bin/log stream \
  --predicate 'subsystem == "com.keyin.ShiftSpaceMac"' --level debug
```

`앱 시작 — 접근성권한=false`가 보이면 권한이 원인입니다.

## 📁 프로젝트 구조

```
Sources/ShiftSpaceMac/
├── main.swift                  # 앱 진입점
├── AppDelegate.swift           # 라이프사이클 관리
└── Managers/
    ├── MenuBarManager.swift        # 메뉴바 아이콘/메뉴
    ├── InputMonitorManager.swift   # CGEventTap 전역 키 감지
    ├── TISSwitchManager.swift      # 시스템 단축키 합성으로 입력 소스 전환
    ├── PanelOverlayManager.swift   # NSPanel 투명 오버레이
    ├── PermissionManager.swift     # 접근성 권한 관리
    └── LaunchAgentManager.swift    # 로그인 시 자동 실행

scripts/
├── diagnose.sh                 # 동작하지 않을 때 원인 진단
├── build_icon.sh               # AppIcon.icns 생성
└── generate_icon.swift         # 아이콘 마스터 PNG 생성
```

## ⚙️ 아키텍처

| 모듈 | 역할 |
|------|------|
| `InputMonitorManager` | CGEventTap으로 Shift+Space 감지, 자기 합성 이벤트·키 반복 필터링, 이벤트 탭 자동 복구 |
| `TISSwitchManager` | 시스템 "이전 입력 소스 선택" 단축키를 읽어 가상 키로 재생, 현재 입력 소스가 한글인지 판별 |
| `PanelOverlayManager` | 투명 NSPanel "한" 인디케이터, AX API 캐럿 추적 (실패 시 마우스 위치 Fallback) |
| `MenuBarManager` | 메뉴바 UI, 자동 실행 토글 |
| `PermissionManager` | 접근성 권한 확인/요청 |
| `LaunchAgentManager` | LaunchAgent plist 등록/해제 |

### 한영 전환은 어떻게 이뤄지나

`TISSelectInputSource`(Carbon)를 **쓰지 않습니다.** 메뉴바 상주(LSUIElement) 앱이 이 API를 호출하면
시스템 전역 입력 소스와 메뉴바 표시는 바뀌지만 현재 활성 앱의 입력기(IMK) 컨텍스트가 따라오지 않아,
실제 타이핑은 이전 소스로 처리되는 macOS 버그가 있습니다. 이 상태에서는 `TISCopyCurrentKeyboardInputSource`도
새 소스를 반환하므로 결과 검증으로 감지할 수도 없습니다.

그래서 대신 **시스템의 "이전 입력 소스 선택" 단축키를 그대로 재생**합니다:

1. `com.apple.symbolichotkeys`의 `AppleSymbolicHotKeys` 딕셔너리에서 key `60`을 읽어
   사용자가 지정한 단축키를 매 호출마다 조회합니다 (설정을 바꿔도 즉시 반영, 읽기 실패 시 `Ctrl+Space`).
2. 해당 키 조합을 `CGEvent`로 합성해 **HID 레벨**(`.cghidEventTap`)에 주입합니다.
   세션 탭에 주입하면 시스템 핫키 처리 단계를 건너뛰어 그냥 스페이스 문자로 전달돼 버립니다.
3. 합성한 이벤트에는 `eventSourceUserData` 태그를 박아두고, `InputMonitorManager`가 이를 걸러냅니다.
   그렇지 않으면 사용자가 시스템 단축키를 `Shift+Space`로 지정했을 때 자기 이벤트가 자기 탭을
   다시 트리거하는 무한 루프가 발생합니다.

`TISCopyCurrentKeyboardInputSource`는 "한" 인디케이터의 표시 여부를 판별하는 용도로만 씁니다.

## 📝 라이선스

MIT
