// ╔══════════════════════════════════════════════════════════════╗
// ║  InputMonitorManager.swift — 전역 키보드 이벤트 모니터링       ║
// ╚══════════════════════════════════════════════════════════════╝
//
// CGEventTap으로 시스템 전역 KeyDown/FlagsChanged 이벤트를 캡처하고
// Shift+Space 조합을 감지한다. OS 타임아웃 시 이벤트 탭을 자동 복구한다.

import Foundation
import CoreGraphics

/// TISSwitchManager가 post하는 가상 키 이벤트를 식별하기 위한 태그.
/// CGEvent의 `.eventSourceUserData` 필드에 박혀, 우리 탭이 자기 자신이
/// 합성한 이벤트를 다시 트리거로 처리하는 자기 루프를 차단한다.
let kShiftSpaceSyntheticEventTag: Int64 = 0x53534D41  // 'SSMA'

final class InputMonitorManager {

    private let onShiftSpaceTriggered: () -> Void
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    fileprivate var isShiftPressed = false

    init(onShiftSpaceTriggered: @escaping () -> Void) {
        self.onShiftSpaceTriggered = onShiftSpaceTriggered
    }

    deinit { stopMonitoring() }

    // ── 모니터링 시작 ────────────────────────────────────────
    func startMonitoring() {
        guard eventTap == nil else { return }

        let eventsOfInterest: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventsOfInterest,
            callback: InputMonitorManager.eventTapCallback,
            userInfo: userInfo
        ) else {
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    // ── 모니터링 중지 ────────────────────────────────────────
    func stopMonitoring() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            }
            CFMachPortInvalidate(tap)
            eventTap = nil
            runLoopSource = nil
        }
    }

    // ── CGEventTap 콜백 (C 함수 시그니처) ─────────────────────
    private static let eventTapCallback: CGEventTapCallBack = {
        (proxy, type, event, userInfo) -> Unmanaged<CGEvent>? in

        guard let userInfo = userInfo else {
            return Unmanaged.passUnretained(event)
        }
        let mgr = Unmanaged<InputMonitorManager>.fromOpaque(userInfo).takeUnretainedValue()

        // ⚠️ 안전장치: 이벤트 탭 비활성화 감지 및 재활성화
        // macOS는 콜백 처리가 느리면 이벤트 탭을 자동 비활성화한다.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = mgr.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        // FlagsChanged: Shift 키 상태 추적
        // (keyDown 이벤트의 flags가 환경/입력기에 따라 modifier 비트를
        //  포함하지 않을 수 있으므로 별도 상태로 캐시한다)
        if type == .flagsChanged {
            let flags = event.flags
            mgr.isShiftPressed = flags.contains(.maskShift)
                && !flags.contains(.maskCommand)
                && !flags.contains(.maskControl)
                && !flags.contains(.maskAlternate)
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        // 우리가 post한 합성 이벤트는 그대로 통과시킨다.
        // 그렇지 않으면 가상 키가 우리 탭을 다시 트리거하여
        // 토글 → 즉시 복귀의 무한 루프가 발생한다.
        let userData = event.getIntegerValueField(.eventSourceUserData)
        if userData == kShiftSpaceSyntheticEventTag {
            return Unmanaged.passUnretained(event)
        }

        // KeyDown: Space(49) + Shift → 트리거
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard keyCode == 49 && mgr.isShiftPressed else {
            return Unmanaged.passUnretained(event)
        }

        // autorepeat 이벤트는 소비만 하고 트리거하지 않는다.
        // (Shift+Space를 꾹 누르고 있어도 토글이 연사되지 않게 함)
        let isAutoRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        if isAutoRepeat {
            return nil
        }

        mgr.onShiftSpaceTriggered()
        return nil  // 이벤트 소비 (Space 입력 차단)
    }
}
