// ╔══════════════════════════════════════════════════════════════╗
// ║  ShiftSpaceMac — macOS 한영 전환 유틸리티                      ║
// ║  main.swift — 앱 진입점                                       ║
// ╚══════════════════════════════════════════════════════════════╝
//
// NSApplication을 수동으로 구성하여 LSUIElement(에이전트 앱)으로 실행합니다.
// SwiftUI의 @main 대신 수동 설정을 사용하는 이유:
// 1. AppKit 기반 에이전트 앱은 NSApplication.shared를 직접 제어해야 함
// 2. CGEventTap 등 저수준 API와의 호환성 보장
// 3. NSPanel 오버레이의 정밀한 윈도우 레벨 제어 필요

import AppKit

// ────────────────────────────────────────────────────────────
// 앱 실행
// ────────────────────────────────────────────────────────────
let app = NSApplication.shared

// 앱 활성화 정책: .accessory = LSUIElement와 동일하게 Dock에 나타나지 않음
app.setActivationPolicy(.accessory)

let delegate = AppDelegate()
app.delegate = delegate

app.run()
