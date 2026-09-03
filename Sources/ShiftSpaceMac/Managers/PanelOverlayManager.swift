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

    /// 의도된 표시 상태. `panel.isVisible`은 페이드아웃 애니메이션이
    /// 끝나기 전까지 true로 남아 있어 show/hide가 빠르게 교차할 때
    /// 판정 기준으로 쓸 수 없다. (Shift+Space 연타 시 인디케이터가
    /// 사라지던 원인)
    private var isShowing = false

    /// systemWide AX 요소는 한 번만 만들어 재사용한다.
    /// 여기에 설정한 메시징 타임아웃이 이 프로세스가 만드는 모든 AX
    /// 요소의 기본값이 되므로, 응답 없는 앱을 만나도 메인 스레드가
    /// 무한정 물리지 않는다.
    private let systemWideElement: AXUIElement = {
        let element = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(element, 0.1)
        return element
    }()

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
        guard !isShowing else {
            updatePosition()
            return
        }
        isShowing = true

        updatePosition()

        // 페이드인 애니메이션
        // (페이드아웃 도중이었다면 진행 중인 애니메이션을 덮어쓴다)
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
        guard isShowing else { return }
        isShowing = false

        stopTracking()

        // 페이드아웃 애니메이션
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.1
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self = self else { return }
            // 페이드아웃이 끝나기 전에 다시 show()가 호출됐다면
            // 여기서 숨기면 안 된다.
            guard !self.isShowing else { return }
            self.panel.orderOut(nil)
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
    //
    // ⚠️ 이 함수는 추적 타이머에 의해 주기적으로, 그것도 임의의 서드파티
    //    앱을 상대로 호출된다. AX API는 `.success`를 반환하면서도 기대와
    //    다른 타입의 값을 돌려줄 수 있다. CF 타입은 `as?`가 런타임 검사
    //    없이 통과할 수 있으므로, CFGetTypeID로 명시 확인한 뒤에만 캐스팅
    //    한다. 검사 없는 강제 언래핑은 곧 앱 전체의 크래시를 뜻한다.
    private func getCaretPosition() -> NSPoint? {
        // 1. 현재 포커스된 앱 가져오기
        var focusedApp: AnyObject?
        guard AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedApplicationAttribute as CFString,
            &focusedApp
        ) == .success,
        let appRef = focusedApp,
        CFGetTypeID(appRef) == AXUIElementGetTypeID() else { return nil }
        let appElement = appRef as! AXUIElement

        // 2. 포커스된 UI 요소 가져오기
        var focusedElement: AnyObject?
        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        ) == .success,
        let elementRef = focusedElement,
        CFGetTypeID(elementRef) == AXUIElementGetTypeID() else { return nil }
        let element = elementRef as! AXUIElement

        // 3. 선택 범위에서 캐럿 위치 인덱스 가져오기
        var selectedRange: AnyObject?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedRange
        ) == .success,
        let range = selectedRange else { return nil }

        // 4. 캐럿 인덱스의 화면 좌표 가져오기
        var caretBounds: AnyObject?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            range,
            &caretBounds
        ) == .success,
        let boundsRef = caretBounds,
        CFGetTypeID(boundsRef) == AXValueGetTypeID() else { return nil }
        let boundsValue = boundsRef as! AXValue

        // AXValue에서 CGRect 추출
        // (타입이 .cgRect가 아니면 AXValueGetValue가 false를 반환한다)
        var rect = CGRect.zero
        guard AXValueGetValue(boundsValue, .cgRect, &rect) else { return nil }

        // 커서 위치: rect의 오른쪽 아래 모서리 (AX 좌표계 = 좌상단 원점)
        return NSPoint(x: rect.origin.x + rect.width, y: rect.origin.y + rect.height)
    }

    // ── 좌표 변환 ────────────────────────────────────────────
    // AX API는 좌상단 원점(top-left origin)의 전역 좌표계를 사용하지만,
    // AppKit/NSPanel은 좌하단 원점(bottom-left origin)을 사용한다.
    //
    // ⚠️ 뒤집기의 기준은 반드시 "주 화면"(메뉴바가 있는 화면)이어야 한다.
    //    두 좌표계 모두 원점이 주 화면에 고정돼 있으므로, 캐럿이 어느
    //    모니터에 있든 주 화면의 maxY 하나로 변환이 성립한다.
    //    NSScreen.main은 "키 윈도우가 있는 화면"이라 키 윈도우가 없는
    //    에이전트 앱에서는 값이 예측 불가하며, 다중 모니터에서 인디케이터가
    //    엉뚱한 위치에 뜨는 원인이 된다.
    //
    //    주 화면은 AppKit 전역 좌표계에서 원점이 (0,0)인 화면으로 정의된다.
    //    NSScreen.screens.first가 그 화면인 것이 일반적이지만 보장되지는
    //    않으므로, 원점이 (0,0)인 화면을 직접 찾고 없을 때만 first로
    //    되돌아간다.
    private func convertToScreenCoordinates(_ point: NSPoint) -> NSPoint {
        guard let primaryScreen = Self.primaryScreen else { return point }
        return NSPoint(x: point.x, y: primaryScreen.frame.maxY - point.y)
    }

    private static var primaryScreen: NSScreen? {
        NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.screens.first
    }

    /// 화면 구성을 로그에 남긴다. 다중 모니터에서 인디케이터 위치가
    /// 어긋난다는 제보를 받았을 때, 원격 머신의 배치를 알아야 원인을
    /// 좁힐 수 있다.
    func logScreenConfiguration() {
        let screens = NSScreen.screens
        let primary = Self.primaryScreen
        Log.overlay.notice("화면 \(screens.count, privacy: .public)개 연결됨")
        for (i, screen) in screens.enumerated() {
            let f = screen.frame
            let mark = (screen === primary) ? " (주 화면)" : ""
            Log.overlay.notice(
                "  [\(i, privacy: .public)] origin=(\(f.origin.x, privacy: .public), \(f.origin.y, privacy: .public)) size=\(f.width, privacy: .public)x\(f.height, privacy: .public)\(mark, privacy: .public)"
            )
        }
        if primary?.frame.origin != .zero {
            Log.overlay.error("원점이 (0,0)인 화면을 찾지 못했습니다 — 인디케이터 위치가 어긋날 수 있습니다")
        }
    }

    // ── 마우스/커서 추적 타이머 ────────────────────────────────
    // 한글 상태일 때 주기적으로 커서 위치를 업데이트한다.
    //
    // 매 틱마다 임의의 서드파티 앱을 상대로 systemWide AX 질의(프로세스
    // 간 통신)가 일어난다. 30ms(초당 33회)는 상주 유틸리티가 상시로
    // 치르기엔 비싼 비용이고, 인디케이터 추적 정확도에 체감 차이도 없어
    // 100ms로 낮춘다.
    //
    // 또한 `.common` 모드로 등록해야 메뉴를 열거나 드래그하는 동안
    // (eventTracking 모드) 추적이 멈추지 않는다.
    private func startTracking() {
        stopTracking()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updatePosition()
        }
        RunLoop.main.add(timer, forMode: .common)
        mouseTrackingTimer = timer
    }

    private func stopTracking() {
        mouseTrackingTimer?.invalidate()
        mouseTrackingTimer = nil
    }
}
