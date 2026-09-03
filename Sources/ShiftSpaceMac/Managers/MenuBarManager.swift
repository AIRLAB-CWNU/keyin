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

    /// 메뉴 헤더에 표시할 이름과 버전.
    /// Info.plist에서 읽어오므로 버전을 올릴 때 여기를 함께 고칠 필요가 없다.
    /// (.app 번들이 아닌 SPM 실행 파일로 직접 띄우면 Info.plist가 없어
    ///  버전을 알 수 없으므로 이름만 표시한다)
    private static var versionTitle: String {
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "ShiftSpaceMac"
        guard let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String else {
            return name
        }
        return "\(name) v\(version)"
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
        let headerItem = NSMenuItem(title: Self.versionTitle, action: nil, keyEquivalent: "")
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
