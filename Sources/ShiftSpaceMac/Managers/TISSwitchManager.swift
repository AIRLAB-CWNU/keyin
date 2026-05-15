// ╔══════════════════════════════════════════════════════════════╗
// ║  TISSwitchManager.swift — 한영 전환 로직                       ║
// ╚══════════════════════════════════════════════════════════════╝
//
// 항상 시스템의 "이전 입력 소스 선택" 단축키를 가상 키 이벤트로
// 합성하여 입력 소스를 토글한다. 단축키 값은 매 호출마다 시스템
// 설정(com.apple.symbolichotkeys, key 60)에서 동적으로 읽으므로
// 사용자가 시스템 환경설정에서 단축키를 바꿔도 즉시 반영된다.
//
// ⚠️ TISSelectInputSource를 사용하지 않는 이유
// ──────────────────────────────────────────────────────────────
// 백그라운드(LSUIElement) 앱이 TISSelectInputSource를 호출하면
// 시스템 전역 입력 소스 상태와 메뉴바 UI는 갱신되지만, 현재 활성
// 앱의 IM(IMKInputController) 컨텍스트가 갱신되지 않아 실제 키
// 입력은 이전 소스(보통 영어)로 처리되는 macOS 버그가 있다.
// 이 상태에서는 TISCopyCurrentKeyboardInputSource도 새 소스를
// 반환하므로 검증으로는 감지가 불가능하다. 따라서 가상 키 합성
// 경로만 사용해 active app의 IM 컨텍스트까지 확실히 갱신한다.

import Foundation
import Carbon
import CoreGraphics

final class TISSwitchManager {

    // 한글 입력 소스 식별자 패턴 (인디케이터 표시 판별용으로만 사용)
    private let koreanInputSourcePrefix = "com.apple.inputmethod.Korean"

    // 시스템 설정을 읽지 못했을 때의 기본값: Ctrl + Space
    private let defaultVirtualKey: UInt16 = 49           // Space
    private let defaultModifiers: CGEventFlags = .maskControl

    // ── 현재 입력 소스가 한글인지 확인 ─────────────────────────
    // 인디케이터(오버레이) 표시 여부를 결정하기 위해 사용된다.
    func isCurrentInputSourceKorean() -> Bool {
        guard let currentSource = TISCopyCurrentKeyboardInputSource() else {
            return false
        }
        let sourceRef = currentSource.takeRetainedValue()
        guard let sourceIDPtr = TISGetInputSourceProperty(
            sourceRef,
            kTISPropertyInputSourceID
        ) else {
            return false
        }

        let sourceID = Unmanaged<CFString>.fromOpaque(sourceIDPtr)
            .takeUnretainedValue() as String

        return sourceID.hasPrefix(koreanInputSourcePrefix)
    }

    // ── 입력 소스 토글 ───────────────────────────────────────
    func toggleInputSource() {
        let (virtualKey, modifiers) = systemInputSourceShortcut()
        sendVirtualKey(virtualKey: virtualKey, modifiers: modifiers)
    }

    // ══════════════════════════════════════════════════════════
    // 시스템 단축키 동적 조회
    // ══════════════════════════════════════════════════════════
    // com.apple.symbolichotkeys.plist의 AppleSymbolicHotKeys 딕셔너리
    // key "60" = "이전 입력 소스 선택" 항목에서 사용자 지정 단축키를
    // 읽어온다. 항목 형식 예시:
    //
    //   "60" = {
    //       enabled = 1;
    //       value = {
    //           parameters = (asciiCode, virtualKey, modifierFlags);
    //           type = standard;
    //       };
    //   };
    //
    // parameters[2]는 NSEvent.ModifierFlags 비트 레이아웃을 사용하며
    // CGEventFlags와 동일한 비트 위치(shift=0x20000, control=0x40000,
    // option=0x80000, command=0x100000)이므로 raw 값을 그대로 매핑
    // 가능하다.
    //
    // 사용자가 단축키를 비활성화/삭제했거나 plist를 읽지 못하면 기본값
    // (Ctrl + Space)을 사용한다.
    private func systemInputSourceShortcut() -> (UInt16, CGEventFlags) {
        let domain = "com.apple.symbolichotkeys" as CFString

        guard let raw = CFPreferencesCopyAppValue(
                "AppleSymbolicHotKeys" as CFString, domain
              ),
              let dict = raw as? [String: Any],
              let hotkey = dict["60"] as? [String: Any]
        else {
            return (defaultVirtualKey, defaultModifiers)
        }

        // enabled 키가 있고 false면 기본값. 키가 없으면 활성으로 간주.
        if let enabled = hotkey["enabled"] as? Bool, !enabled {
            return (defaultVirtualKey, defaultModifiers)
        }
        if let enabledNum = hotkey["enabled"] as? NSNumber, enabledNum.intValue == 0 {
            return (defaultVirtualKey, defaultModifiers)
        }

        guard let valueDict = hotkey["value"] as? [String: Any],
              let params = valueDict["parameters"] as? [NSNumber],
              params.count >= 3
        else {
            return (defaultVirtualKey, defaultModifiers)
        }

        let virtualKey = UInt16(truncatingIfNeeded: params[1].intValue)
        let modifiers = CGEventFlags(rawValue: UInt64(params[2].uint64Value))
        return (virtualKey, modifiers)
    }

    // ══════════════════════════════════════════════════════════
    // 가상 키 이벤트 합성 및 전송
    // ══════════════════════════════════════════════════════════
    private func sendVirtualKey(virtualKey: UInt16, modifiers: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)

        guard let keyDown = CGEvent(
            keyboardEventSource: source,
            virtualKey: virtualKey,
            keyDown: true
        ) else { return }
        keyDown.flags = modifiers
        // InputMonitorManager가 자기 합성 이벤트를 식별하여 자기 루프를
        // 끊을 수 있도록 태그를 박는다.
        keyDown.setIntegerValueField(
            .eventSourceUserData,
            value: kShiftSpaceSyntheticEventTag
        )

        guard let keyUp = CGEvent(
            keyboardEventSource: source,
            virtualKey: virtualKey,
            keyDown: false
        ) else { return }
        keyUp.flags = modifiers
        keyUp.setIntegerValueField(
            .eventSourceUserData,
            value: kShiftSpaceSyntheticEventTag
        )

        // HID 레벨에 주입 → 시스템 핫키(입력소스 전환) 핸들러가 처리한다.
        // .cgSessionEventTap에 post하면 핫키 처리 단계를 우회하여
        // 합성 이벤트가 그냥 포커스된 앱에 스페이스 문자로 전달돼 버린다.
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        print("[TISSwitch] 🔄 가상 키 전송 keyCode=\(virtualKey) flags=0x\(String(modifiers.rawValue, radix: 16))")
    }
}
