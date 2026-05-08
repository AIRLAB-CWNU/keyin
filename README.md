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

> **Tip:** 개발 중 빌드마다 권한이 초기화되는 경우, 자체 서명 인증서를 사용하면 방지할 수 있습니다. `build.sh app` 실행 시 출력되는 코드 서명 안내를 참고하세요.

## 📁 프로젝트 구조

```
Sources/ShiftSpaceMac/
├── main.swift                  # 앱 진입점
├── AppDelegate.swift           # 라이프사이클 관리
└── Managers/
    ├── MenuBarManager.swift        # 메뉴바 아이콘/메뉴
    ├── InputMonitorManager.swift   # CGEventTap 전역 키 감지
    ├── TISSwitchManager.swift      # Carbon TIS 한영 전환
    ├── PanelOverlayManager.swift   # NSPanel 투명 오버레이
    ├── PermissionManager.swift     # 접근성 권한 관리
    └── LaunchAgentManager.swift    # 로그인 시 자동 실행
```

## ⚙️ 아키텍처

| 모듈 | 역할 |
|------|------|
| `InputMonitorManager` | CGEventTap으로 Shift+Space 감지, 이벤트 탭 자동 복구 |
| `TISSwitchManager` | Carbon API로 한영 전환, 백그라운드 버그 시 가상 키코드 Fallback |
| `PanelOverlayManager` | 투명 NSPanel "한" 인디케이터, AX API 커서 추적 |
| `MenuBarManager` | 메뉴바 UI, 자동 실행 토글 |
| `PermissionManager` | 접근성 권한 확인/요청 |
| `LaunchAgentManager` | LaunchAgent plist 등록/해제 |

## 📝 라이선스

MIT
