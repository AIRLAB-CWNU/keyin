// ╔══════════════════════════════════════════════════════════════╗
// ║  PanelOverlayManager.swift — 투명 플로팅 오버레이             ║
// ╚══════════════════════════════════════════════════════════════╝
//
// NSPanel로 테두리/그림자 없는 투명 "한" 인디케이터를 표시한다.
// AXUIElement로 텍스트 커서 위치를 추적하고,
// 실패 시 마우스 커서 위치를 Fallback으로 사용한다.

import AppKit
import ApplicationServices

final class PanelOverlayManager {

    private var panel: NSPanel!
    private var label: NSTextField!
    private var mouseTrackingTimer: Timer?

    // 오버레이 크기 및 오프셋
    private let overlaySize = NSSize(width: 24, height: 24)
    private let cursorOffset = NSPoint(x: 12, y: -4)  // 커서 우측 하단

    init() {
        setupPanel()
    }

    // ── 패널 설정 ────────────────────────────────────────────
    private func setupPanel() {
        // ─────────────────────────────────────────────────
        // NSPanel 생성: border/title 없음, 투명 배경
        // ─────────────────────────────────────────────────
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: overlaySize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // 투명 배경 (그림자 없음)
        panel.backgroundColor = NSColor.clear
        panel.isOpaque = false
        panel.hasShadow = false

        // 항상 최상위에 표시
        panel.level = .floating

        // ─────────────────────────────────────────────────
        // 클릭 통과 보장 (Pass-through)
        // ─────────────────────────────────────────────────
        // ignoresMouseEvents = true로 설정하면 이 패널 위의
        // 모든 마우스 이벤트가 뒤편 앱으로 통과된다.
        panel.ignoresMouseEvents = true

        // ─────────────────────────────────────────────────
        // 모든 데스크탑 Space에서 표시
        // ─────────────────────────────────────────────────
        // canJoinAllSpaces: Space 전환 시에도 오버레이가 보임
        // fullScreenAuxiliary: 전체 화면 앱 위에도 표시
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary
        ]

        // 앱 활성화 없이 표시 (에이전트 앱이므로 필수)
        panel.hidesOnDeactivate = false

        // ─────────────────────────────────────────────────
        // "한" 라벨 생성
        // ─────────────────────────────────────────────────
        label = NSTextField(frame: NSRect(origin: .zero, size: overlaySize))
        label.stringValue = "한"
        label.font = NSFont.systemFont(ofSize: 13, weight: .bold)
        label.textColor = NSColor.systemBlue
        label.backgroundColor = NSColor.clear
        label.isBordered = false
        label.isEditable = false
        label.isSelectable = false
        label.alignment = .center

        // 라벨에도 클릭 통과 적용 (이중 안전장치)
        label.refusesFirstResponder = true

        panel.contentView?.addSubview(label)
    }

    // ── 오버레이 표시 ────────────────────────────────────────
    func show() {
        guard !panel.isVisible else {
            updatePosition()
            return
        }

        updatePosition()

        // 페이드인 애니메이션
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 1.0
        }

        startTracking()
    }

    // ── 오버레이 숨김 ────────────────────────────────────────
    func hide() {
        stopTracking()

        guard panel.isVisible else { return }

        // 페이드아웃 애니메이션
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.1
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.panel.orderOut(nil)
        })
    }

    // ── 위치 업데이트 ────────────────────────────────────────
    private func updatePosition() {
        // 1차 시도: Accessibility API로 텍스트 커서 위치 가져오기
        if let caretPosition = getCaretPosition() {
            let screenPoint = convertToScreenCoordinates(caretPosition)
            let panelOrigin = NSPoint(
                x: screenPoint.x + cursorOffset.x,
                y: screenPoint.y + cursorOffset.y - overlaySize.height
            )
            panel.setFrameOrigin(panelOrigin)
            return
        }

        // 2차 Fallback: 마우스 커서 위치 사용
        let mouseLocation = NSEvent.mouseLocation
        let panelOrigin = NSPoint(
            x: mouseLocation.x + cursorOffset.x,
            y: mouseLocation.y + cursorOffset.y - overlaySize.height
        )
        panel.setFrameOrigin(panelOrigin)
    }

    // ── 텍스트 커서(Caret) 위치 가져오기 (Accessibility API) ──
    // AXUIElement를 사용하여 현재 포커스된 앱의 텍스트 필드에서
    // 캐럿(커서)의 화면 좌표를 가져온다.
    private func getCaretPosition() -> NSPoint? {
        // 1. 현재 포커스된 앱 가져오기
        let systemWide = AXUIElementCreateSystemWide()

        var focusedApp: AnyObject?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedApplicationAttribute as CFString,
            &focusedApp
        ) == .success else { return nil }

        // 2. 포커스된 UI 요소 가져오기
        var focusedElement: AnyObject?
        guard AXUIElementCopyAttributeValue(
            focusedApp as! AXUIElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        ) == .success else { return nil }

        let element = focusedElement as! AXUIElement

        // 3. 선택 범위에서 캐럿 위치 인덱스 가져오기
        var selectedRange: AnyObject?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedRange
        ) == .success else { return nil }

        // 4. 캐럿 인덱스의 화면 좌표 가져오기
        var caretBounds: AnyObject?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            selectedRange!,
            &caretBounds
        ) == .success else { return nil }

        // AXValue에서 CGRect 추출
        var rect = CGRect.zero
        guard AXValueGetValue(
            caretBounds as! AXValue,
            .cgRect,
            &rect
        ) else { return nil }

        // 커서 위치: rect의 왼쪽 하단
        return NSPoint(x: rect.origin.x + rect.width, y: rect.origin.y + rect.height)
    }

    // ── 좌표 변환 ────────────────────────────────────────────
    // AX API는 좌상단 원점(top-left origin) 좌표계를 사용하지만,
    // AppKit/NSPanel은 좌하단 원점(bottom-left origin)을 사용한다.
    // 스크린 높이를 기준으로 Y축을 뒤집어야 한다.
    private func convertToScreenCoordinates(_ point: NSPoint) -> NSPoint {
        guard let screen = NSScreen.main else { return point }
        let screenHeight = screen.frame.height
        return NSPoint(x: point.x, y: screenHeight - point.y)
    }

    // ── 마우스/커서 추적 타이머 ────────────────────────────────
    // 한글 상태일 때 주기적으로 커서 위치를 업데이트한다.
    // 60fps 수준의 추적은 불필요하므로 30ms 간격이면 충분하다.
    private func startTracking() {
        stopTracking()
        mouseTrackingTimer = Timer.scheduledTimer(
            withTimeInterval: 0.03,
            repeats: true
        ) { [weak self] _ in
            self?.updatePosition()
        }
    }

    private func stopTracking() {
        mouseTrackingTimer?.invalidate()
        mouseTrackingTimer = nil
    }
}
