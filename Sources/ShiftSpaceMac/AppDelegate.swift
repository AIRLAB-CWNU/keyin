// ╔══════════════════════════════════════════════════════════════╗
// ║  AppDelegate.swift — 앱 라이프사이클 관리                      ║
// ╚══════════════════════════════════════════════════════════════╝
//
// 책임:
// - 모든 매니저 초기화 및 연결
// - 권한 확인 → 이벤트 모니터 시작 → 오버레이 준비
// - 입력 소스 변경 알림 수신 및 오버레이 업데이트

import AppKit
import Carbon

class AppDelegate: NSObject, NSApplicationDelegate {

    // ── 매니저 인스턴스 ──────────────────────────────────────
    private var menuBarManager: MenuBarManager!
    private var inputMonitorManager: InputMonitorManager!
    private var tisSwitchManager: TISSwitchManager!
    private var panelOverlayManager: PanelOverlayManager!
    private var permissionManager: PermissionManager!
    private var launchAgentManager: LaunchAgentManager!

    // ── 앱 시작 ──────────────────────────────────────────────
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("[ShiftSpaceMac] 앱 시작")

        // 1) 매니저 초기화 (의존성 없는 것부터)
        permissionManager = PermissionManager()
        launchAgentManager = LaunchAgentManager()
        tisSwitchManager = TISSwitchManager()
        panelOverlayManager = PanelOverlayManager()

        // 2) 메뉴바 매니저 (UI 구성)
        menuBarManager = MenuBarManager(
            launchAgentManager: launchAgentManager,
            permissionManager: permissionManager
        )

        // 3) 입력 모니터 매니저 (전역 키 감지)
        inputMonitorManager = InputMonitorManager { [weak self] in
            self?.handleShiftSpaceTriggered()
        }

        // 4) 권한 확인 후 시작
        let hasPermission = permissionManager.checkAccessibilityPermission()
        print("[ShiftSpaceMac] 실행 경로: \(Bundle.main.executablePath ?? ProcessInfo.processInfo.arguments[0])")
        print("[ShiftSpaceMac] 접근성 권한: \(hasPermission ? "✅ 허용됨" : "❌ 거부됨")")
        if hasPermission {
            startMonitoring()
        } else {
            // 권한이 없으면 안내 후 대기
            permissionManager.requestAccessibilityPermission()
            // 3초마다 권한 재확인
            startPermissionPolling()
        }

        // 5) 입력 소스 변경 알림 수신
        // macOS는 입력 소스가 변경될 때마다 이 알림을 보냄
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(inputSourceDidChange),
            name: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil
        )

        // 6) 초기 상태 반영
        updateOverlayForCurrentInputSource()
    }

    func applicationWillTerminate(_ notification: Notification) {
        inputMonitorManager?.stopMonitoring()
        panelOverlayManager?.hide()
        print("[ShiftSpaceMac] 앱 종료")
    }

    // ── 권한 폴링 ────────────────────────────────────────────
    // 사용자가 시스템 설정에서 권한을 허용할 때까지 주기적으로 확인
    private var permissionTimer: Timer?

    private func startPermissionPolling() {
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) {
            [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            if self.permissionManager.checkAccessibilityPermission() {
                timer.invalidate()
                self.permissionTimer = nil
                print("[ShiftSpaceMac] 접근성 권한 허용됨 — 모니터링 시작")
                self.startMonitoring()
            }
        }
    }

    // ── 모니터링 시작 ────────────────────────────────────────
    private func startMonitoring() {
        inputMonitorManager.startMonitoring()
        print("[ShiftSpaceMac] 전역 키보드 모니터링 활성화")
    }

    // ── Shift+Space 트리거 핸들러 ────────────────────────────
    // InputMonitorManager가 Shift+Space를 감지하면 호출됨
    private func handleShiftSpaceTriggered() {
        DispatchQueue.main.async { [weak self] in
            self?.tisSwitchManager.toggleInputSource()
            // 오버레이 업데이트는 inputSourceDidChange 알림에서 처리
        }
    }

    // ── 입력 소스 변경 알림 핸들러 ────────────────────────────
    @objc private func inputSourceDidChange(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.updateOverlayForCurrentInputSource()
        }
    }

    // ── 오버레이 상태 업데이트 ────────────────────────────────
    private func updateOverlayForCurrentInputSource() {
        let isKorean = tisSwitchManager.isCurrentInputSourceKorean()

        if isKorean {
            panelOverlayManager.show()
        } else {
            panelOverlayManager.hide()
        }
    }
}
