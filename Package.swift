// swift-tools-version: 5.9
// ShiftSpaceMac - macOS 메모리 상주형 한영 전환 유틸리티
// ────────────────────────────────────────────────────────
// Swift Package Manager 프로젝트 설정
// macOS 13 (Ventura) 이상 필수 (Apple Silicon & Intel 지원)

import PackageDescription

let package = Package(
    name: "ShiftSpaceMac",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "ShiftSpaceMac",
            path: "Sources/ShiftSpaceMac",
            exclude: ["Resources/Info.plist", "Resources/AppIcon.icns"],
            linkerSettings: [
                // Carbon 프레임워크: TISCreateInputSourceList, TISSelectInputSource 등
                // 입력 소스 관리를 위해 반드시 필요
                .linkedFramework("Carbon"),
                // AppKit: NSPanel, NSStatusItem 등 UI 요소
                .linkedFramework("AppKit"),
                // CoreGraphics: CGEventTap 등 전역 이벤트 모니터링
                .linkedFramework("CoreGraphics"),
                // ApplicationServices: Accessibility API (AXUIElement)
                .linkedFramework("ApplicationServices"),
            ]
        )
    ]
)
