// ╔══════════════════════════════════════════════════════════════╗
// ║  PermissionManager.swift — 접근성/입력 모니터링 권한 관리       ║
// ╚══════════════════════════════════════════════════════════════╝
//
// 책임:
// - 접근성(Accessibility) 권한 확인
// - 권한 미허용 시 시스템 설정으로 안내
//
// ──────────────────────────────────────────────────────────────
// 🔑 코드 서명 가이드 (TCC 권한 유지)
// ──────────────────────────────────────────────────────────────
// 개발 중 빌드할 때마다 접근성 권한이 초기화되는 문제를 방지하려면:
//
// 1. Keychain Access에서 자체 서명 인증서 생성:
//    - Keychain Access → 인증서 지원 → 인증서 생성
//    - 이름: "ShiftSpaceMac Dev" (임의)
//    - 인증서 유형: 코드 서명
//
// 2. Xcode에서 Signing 설정:
//    - Signing & Capabilities → Signing Certificate → 위에서 만든 인증서 선택
//    - Team: None (개인 개발)
//
// 3. 또는 커맨드라인에서:
//    codesign --force --sign "ShiftSpaceMac Dev" \
//      --entitlements ShiftSpaceMac.entitlements \
//      ./build/ShiftSpaceMac.app
//
// 이렇게 하면 빌드마다 바이너리 해시가 바뀌어도 인증서 기반으로
// TCC가 앱을 식별하므로 권한이 유지됩니다.
// ──────────────────────────────────────────────────────────────

import AppKit
import ApplicationServices

final class PermissionManager {

    // ── 접근성 권한 확인 ──────────────────────────────────────
    /// AXIsProcessTrusted()는 현재 프로세스가 접근성 권한을 가지고 있는지 반환합니다.
    /// CGEventTap과 AXUIElement 모두 이 권한이 필요합니다.
    func checkAccessibilityPermission() -> Bool {
        return AXIsProcessTrusted()
    }

    // ── 접근성 권한 요청 ──────────────────────────────────────
    /// 권한이 없을 때 호출하면:
    /// 1. 시스템의 접근성 권한 다이얼로그를 표시 (kAXTrustedCheckOptionPrompt)
    /// 2. 사용자 친화적인 안내 알림 표시
    func requestAccessibilityPermission() {
        // kAXTrustedCheckOptionPrompt: true → 시스템 권한 요청 다이얼로그 표시
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)

        // 추가 안내 알림
        showPermissionAlert()
    }

    // ── 시스템 설정 열기 ──────────────────────────────────────
    /// 접근성 권한 설정 패널을 직접 열기
    func openAccessibilitySettings() {
        // macOS 13+ 의 새로운 URL 스킴
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // ── 입력 모니터링 설정 열기 ────────────────────────────────
    func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    // ── 안내 알림 ────────────────────────────────────────────
    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "접근성 권한이 필요합니다"
        alert.informativeText = """
        ShiftSpaceMac이 시스템 전역에서 키보드 입력을 감지하고 \
        텍스트 커서 위치를 추적하려면 접근성 권한이 필요합니다.

        시스템 설정 → 개인정보 보호 및 보안 → 접근성에서 \
        ShiftSpaceMac을 허용해 주세요.

        권한 허용 후 앱이 자동으로 활성화됩니다.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "시스템 설정 열기")
        alert.addButton(withTitle: "나중에")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            openAccessibilitySettings()
        }
    }
}
