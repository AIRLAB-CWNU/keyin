// ╔══════════════════════════════════════════════════════════════╗
// ║  TISSwitchManager.swift — 한영 전환 로직 (Carbon TIS API)     ║
// ╚══════════════════════════════════════════════════════════════╝
//
// Carbon.h의 TISCreateInputSourceList / TISSelectInputSource로
// 입력 소스를 토글한다. 백그라운드 버그 발생 시 가상 키코드로 우회한다.
//
// ⚠️ 백그라운드 버그 우회 (macOS 알려진 이슈)
// ──────────────────────────────────────────────────────────────
// macOS에서 백그라운드 앱이 TISSelectInputSource를 호출하면
// UI(메뉴바 아이콘)만 바뀌고 실제 입력은 영어로 되는 버그가 있다.
// 이 경우 CGEvent로 가상 키 이벤트를 합성하여 OS에 전송함으로써
// 입력 소스를 강제 전환하는 Fallback을 적용한다.

import Foundation
import Carbon
import CoreGraphics

final class TISSwitchManager {

    // 한글 입력 소스 식별자 패턴
    // macOS 한글 입력기: com.apple.inputmethod.Korean.2SetKorean 등
    private let koreanInputSourcePrefix = "com.apple.inputmethod.Korean"

    // 영문 입력 소스 식별자
    private let englishInputSourceIDs = [
        "com.apple.keylayout.ABC",
        "com.apple.keylayout.US",
        "com.apple.keylayout.USInternational-PC"
    ]

    // ── 현재 입력 소스가 한글인지 확인 ─────────────────────────
    func isCurrentInputSourceKorean() -> Bool {
        guard let currentSource = TISCopyCurrentKeyboardInputSource() else {
            return false
        }
        // TISCopyCurrentKeyboardInputSource는 Create Rule을 따르므로
        // 반환값을 Release해야 한다. 하지만 Swift의 Unmanaged가 처리한다.
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
        let isKorean = isCurrentInputSourceKorean()

        if isKorean {
            switchToEnglish()
        } else {
            switchToKorean()
        }
    }

    // ── 영어로 전환 ──────────────────────────────────────────
    private func switchToEnglish() {
        if let source = findInputSource(matchingAny: englishInputSourceIDs) {
            let result = TISSelectInputSource(source)
            if result != noErr {
                print("[TISSwitch] ⚠️ 영어 전환 실패 (코드: \(result)) — Fallback 사용")
                sendVirtualInputSourceToggle()
            } else {
                // 백그라운드 버그 확인: 전환 후 실제로 바뀌었는지 검증
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    if self?.isCurrentInputSourceKorean() == true {
                        print("[TISSwitch] ⚠️ 백그라운드 버그 감지 — Fallback")
                        self?.sendVirtualInputSourceToggle()
                    }
                }
            }
        } else {
            print("[TISSwitch] ⚠️ 영어 입력 소스 없음 — Fallback")
            sendVirtualInputSourceToggle()
        }
    }

    // ── 한글로 전환 ──────────────────────────────────────────
    private func switchToKorean() {
        if let source = findKoreanInputSource() {
            let result = TISSelectInputSource(source)
            if result != noErr {
                print("[TISSwitch] ⚠️ 한글 전환 실패 — Fallback 사용")
                sendVirtualInputSourceToggle()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    if self?.isCurrentInputSourceKorean() == false {
                        print("[TISSwitch] ⚠️ 백그라운드 버그 감지 — Fallback")
                        self?.sendVirtualInputSourceToggle()
                    }
                }
            }
        } else {
            print("[TISSwitch] ⚠️ 한글 입력 소스 없음 — Fallback")
            sendVirtualInputSourceToggle()
        }
    }

    // ── 입력 소스 검색 (ID 매칭) ──────────────────────────────
    private func findInputSource(matchingAny ids: [String]) -> TISInputSource? {
        let properties: CFDictionary = [
            kTISPropertyInputSourceCategory as String:
                kTISCategoryKeyboardInputSource as String
        ] as CFDictionary

        guard let sourceList = TISCreateInputSourceList(
            properties, false
        )?.takeRetainedValue() as? [TISInputSource] else {
            return nil
        }

        for source in sourceList {
            guard let idPtr = TISGetInputSourceProperty(
                source, kTISPropertyInputSourceID
            ) else { continue }

            let sourceID = Unmanaged<CFString>.fromOpaque(idPtr)
                .takeUnretainedValue() as String

            if ids.contains(sourceID) {
                return source
            }
        }
        return nil
    }

    // ── 한글 입력 소스 검색 ───────────────────────────────────
    private func findKoreanInputSource() -> TISInputSource? {
        let properties: CFDictionary = [
            kTISPropertyInputSourceCategory as String:
                kTISCategoryKeyboardInputSource as String
        ] as CFDictionary

        guard let sourceList = TISCreateInputSourceList(
            properties, false
        )?.takeRetainedValue() as? [TISInputSource] else {
            return nil
        }

        for source in sourceList {
            guard let idPtr = TISGetInputSourceProperty(
                source, kTISPropertyInputSourceID
            ) else { continue }

            let sourceID = Unmanaged<CFString>.fromOpaque(idPtr)
                .takeUnretainedValue() as String

            if sourceID.hasPrefix(koreanInputSourcePrefix) {
                return source
            }
        }
        return nil
    }

    // ══════════════════════════════════════════════════════════
    // Fallback: 가상 키코드를 통한 입력 소스 전환
    // ══════════════════════════════════════════════════════════
    // TISSelectInputSource가 백그라운드에서 정상 작동하지 않을 때
    // macOS의 기본 한영 전환 단축키(Ctrl+Space 또는 Caps Lock)를
    // CGEvent로 합성하여 OS에 전송한다.
    //
    // 시스템 설정에서 "이전 입력 소스 선택" 단축키가 Ctrl+Space로
    // 설정되어 있다고 가정한다.
    private func sendVirtualInputSourceToggle() {
        // Ctrl+Space 가상 키 이벤트 합성
        // keyCode 49 = Space
        let source = CGEventSource(stateID: .hidSystemState)

        // Key Down: Ctrl + Space
        guard let keyDown = CGEvent(
            keyboardEventSource: source,
            virtualKey: 49,       // Space
            keyDown: true
        ) else { return }
        keyDown.flags = .maskControl

        // Key Up
        guard let keyUp = CGEvent(
            keyboardEventSource: source,
            virtualKey: 49,
            keyDown: false
        ) else { return }
        keyUp.flags = .maskControl

        // HID 시스템 레벨로 전송
        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)

        print("[TISSwitch] 🔄 Fallback: Ctrl+Space 가상 키 전송")
    }
}
