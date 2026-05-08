// ╔══════════════════════════════════════════════════════════════╗
// ║  LaunchAgentManager.swift — 로그인 시 자동 실행 관리           ║
// ╚══════════════════════════════════════════════════════════════╝
//
// ~/Library/LaunchAgents/에 .plist 파일을 등록/해제하여
// macOS 로그인 시 앱을 자동으로 시작한다.
// launchctl bootstrap/bootout 명령을 사용한다.

import Foundation

final class LaunchAgentManager {

    private let bundleIdentifier = "com.keyin.ShiftSpaceMac"
    private let plistFileName = "com.keyin.ShiftSpaceMac.plist"

    /// ~/Library/LaunchAgents/ 경로
    private var launchAgentsDir: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/LaunchAgents")
    }

    /// LaunchAgent plist 파일 전체 경로
    private var plistPath: URL {
        launchAgentsDir.appendingPathComponent(plistFileName)
    }

    // ── 자동 실행 활성화 여부 ─────────────────────────────────
    func isEnabled() -> Bool {
        return FileManager.default.fileExists(atPath: plistPath.path)
    }

    // ── 자동 실행 활성화 ─────────────────────────────────────
    func enable() {
        // 현재 실행 파일 경로
        guard let executablePath = Bundle.main.executablePath else {
            // SPM 빌드 시 Bundle.main.executablePath가 nil일 수 있음
            // 이 경우 ProcessInfo에서 가져옴
            let path = ProcessInfo.processInfo.arguments[0]
            writePlist(executablePath: path)
            return
        }
        writePlist(executablePath: executablePath)
    }

    // ── 자동 실행 비활성화 ────────────────────────────────────
    func disable() {
        // 1. launchctl에서 제거
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = [
            "bootout",
            "gui/\(getuid())",
            plistPath.path
        ]
        try? process.run()
        process.waitUntilExit()

        // 2. plist 파일 삭제
        try? FileManager.default.removeItem(at: plistPath)

        print("[LaunchAgent] 자동 실행 비활성화")
    }

    // ── plist 파일 생성 및 등록 ───────────────────────────────
    private func writePlist(executablePath: String) {
        // LaunchAgents 디렉토리 확인/생성
        let fm = FileManager.default
        if !fm.fileExists(atPath: launchAgentsDir.path) {
            try? fm.createDirectory(at: launchAgentsDir,
                                    withIntermediateDirectories: true)
        }

        // ─────────────────────────────────────────────────
        // LaunchAgent plist 내용
        // ─────────────────────────────────────────────────
        // - RunAtLoad: 로그인 시 즉시 실행
        // - KeepAlive: 크래시 시 자동 재시작
        // - ProcessType: Background (시스템 리소스 우선순위 낮춤)
        let plistContent: [String: Any] = [
            "Label": bundleIdentifier,
            "ProgramArguments": [executablePath],
            "RunAtLoad": true,
            "KeepAlive": [
                "SuccessfulExit": false  // 비정상 종료 시에만 재시작
            ],
            "ProcessType": "Background"
        ]

        // plist 파일 쓰기
        let data = try? PropertyListSerialization.data(
            fromPropertyList: plistContent,
            format: .xml,
            options: 0
        )

        guard let data = data else {
            print("[LaunchAgent] ❌ plist 직렬화 실패")
            return
        }

        do {
            try data.write(to: plistPath)
        } catch {
            print("[LaunchAgent] ❌ plist 파일 쓰기 실패: \(error)")
            return
        }

        // launchctl로 등록
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = [
            "bootstrap",
            "gui/\(getuid())",
            plistPath.path
        ]
        try? process.run()
        process.waitUntilExit()

        print("[LaunchAgent] ✅ 자동 실행 활성화: \(plistPath.path)")
    }
}
