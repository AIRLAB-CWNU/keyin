// ╔══════════════════════════════════════════════════════════════╗
// ║  InputMonitorManager.swift — 전역 키보드 이벤트 모니터링       ║
// ╚══════════════════════════════════════════════════════════════╝
//
// CGEventTap으로 시스템 전역 KeyDown/FlagsChanged 이벤트를 캡처하고
// Shift+Space 조합을 감지한다. OS 타임아웃 시 이벤트 탭을 자동 복구한다.

import Foundation
import CoreGraphics

final class InputMonitorManager {

    private let onShiftSpaceTriggered: () -> Void
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isShiftPressed = false

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
            print("[InputMonitor] ❌ CGEventTap 생성 실패")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        print("[InputMonitor] ✅ 전역 이벤트 모니터링 시작")
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
            print("[InputMonitor] ⚠️ 탭 비활성화 → 재활성화")
            if let tap = mgr.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        // FlagsChanged: Shift 키 상태 추적
        if type == .flagsChanged {
            let flags = event.flags
            mgr.isShiftPressed = flags.contains(.maskShift)
                && !flags.contains(.maskCommand)
                && !flags.contains(.maskControl)
                && !flags.contains(.maskAlternate)
            return Unmanaged.passUnretained(event)
        }

        // KeyDown: Space(49) + Shift → 트리거
        if type == .keyDown {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if keyCode == 49 && mgr.isShiftPressed {
                print("[InputMonitor] 🎯 Shift+Space 감지!")
                mgr.onShiftSpaceTriggered()
                return nil  // 이벤트 소비 (Space 입력 차단)
            }
        }

        return Unmanaged.passUnretained(event)
    }
}
