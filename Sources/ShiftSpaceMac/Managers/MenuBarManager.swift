// ╔══════════════════════════════════════════════════════════════╗
// ║  MenuBarManager.swift — 메뉴바 아이콘 및 드롭다운 메뉴 관리    ║
// ╚══════════════════════════════════════════════════════════════╝
//
// 책임:
// - NSStatusItem으로 메뉴바 아이콘 생성
// - 드롭다운 메뉴 구성 (자동 실행 토글, 권한 설정, 종료)
// - LaunchAgentManager와 연동하여 자동 실행 상태 동기화

import AppKit

final class MenuBarManager {

    private var statusItem: NSStatusItem!
    private let launchAgentManager: LaunchAgentManager
    private let permissionManager: PermissionManager
    private var autoLaunchMenuItem: NSMenuItem!

    init(launchAgentManager: LaunchAgentManager, permissionManager: PermissionManager) {
        self.launchAgentManager = launchAgentManager
        self.permissionManager = permissionManager
        setupStatusItem()
    }

    // ── 메뉴바 아이콘 설정 ────────────────────────────────────
    private func setupStatusItem() {
        // NSStatusBar.system에서 가변 길이 아이템 생성
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            // SF Symbols 사용 (macOS 11+)
            // "character.ko" 아이콘 없으면 "keyboard" 사용
            if let image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "ShiftSpaceMac") {
                image.isTemplate = true  // 다크 모드 자동 대응
                button.image = image
            } else {
                button.title = "⌨"
            }
            button.toolTip = "ShiftSpaceMac — Shift+Space 한영 전환"
        }

        // 드롭다운 메뉴 구성
        let menu = NSMenu()

        // ─ 헤더
        let headerItem = NSMenuItem(title: "ShiftSpaceMac v1.0", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)
        menu.addItem(NSMenuItem.separator())

        // ─ 로그인 시 자동 실행
        autoLaunchMenuItem = NSMenuItem(
            title: "로그인 시 자동 실행",
            action: #selector(toggleAutoLaunch),
            keyEquivalent: ""
        )
        autoLaunchMenuItem.target = self
        autoLaunchMenuItem.state = launchAgentManager.isEnabled() ? .on : .off
        menu.addItem(autoLaunchMenuItem)

        menu.addItem(NSMenuItem.separator())

        // ─ 권한 설정 서브메뉴
        let permissionItem = NSMenuItem(title: "권한 설정", action: nil, keyEquivalent: "")
        let permissionSubmenu = NSMenu()

        let accessibilityItem = NSMenuItem(
            title: "접근성 권한 열기",
            action: #selector(openAccessibility),
            keyEquivalent: ""
        )
        accessibilityItem.target = self
        permissionSubmenu.addItem(accessibilityItem)

        let inputMonitorItem = NSMenuItem(
            title: "입력 모니터링 권한 열기",
            action: #selector(openInputMonitoring),
            keyEquivalent: ""
        )
        inputMonitorItem.target = self
        permissionSubmenu.addItem(inputMonitorItem)

        permissionItem.submenu = permissionSubmenu
        menu.addItem(permissionItem)

        menu.addItem(NSMenuItem.separator())

        // ─ 종료
        let quitItem = NSMenuItem(
            title: "종료",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // ── 액션 핸들러 ──────────────────────────────────────────

    @objc private func toggleAutoLaunch() {
        let currentlyEnabled = launchAgentManager.isEnabled()

        if currentlyEnabled {
            launchAgentManager.disable()
        } else {
            launchAgentManager.enable()
        }

        autoLaunchMenuItem.state = launchAgentManager.isEnabled() ? .on : .off
        print("[MenuBarManager] 자동 실행: \(launchAgentManager.isEnabled() ? "활성화" : "비활성화")")
    }

    @objc private func openAccessibility() {
        permissionManager.openAccessibilitySettings()
    }

    @objc private func openInputMonitoring() {
        permissionManager.openInputMonitoringSettings()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
