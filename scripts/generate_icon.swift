#!/usr/bin/env swift
// ╔══════════════════════════════════════════════════════════════╗
// ║  generate_icon.swift — ShiftSpaceMac 앱 아이콘 마스터 PNG 생성  ║
// ╚══════════════════════════════════════════════════════════════╝
//
// 1024×1024 PNG 한 장을 생성한다. 다른 사이즈는 sips로 리사이즈하고
// iconutil로 .icns로 묶는다 (build_icon.sh가 담당).
//
// 사용법:
//   swift scripts/generate_icon.swift <output_path>

import AppKit
import CoreGraphics
import Foundation

let pixelSize = 1024
let size = CGFloat(pixelSize)

// macOS Big Sur+ 앱 아이콘 squircle 근사 (코너 약 22.37%)
let cornerRadius = size * 0.2237

let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil,
    width: pixelSize,
    height: pixelSize,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fatalError("CGContext 생성 실패") }

let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = nsCtx

// ── 1) Squircle 클립 ───────────────────────────────────────────
let squircle = NSBezierPath(
    roundedRect: NSRect(x: 0, y: 0, width: size, height: size),
    xRadius: cornerRadius,
    yRadius: cornerRadius
)
squircle.addClip()

// ── 2) 그라디언트 배경 (인디고 → 블루, 위→아래) ───────────────
let gradient = NSGradient(colors: [
    NSColor(red: 0.10, green: 0.13, blue: 0.45, alpha: 1.0),  // top
    NSColor(red: 0.20, green: 0.50, blue: 0.98, alpha: 1.0),  // bottom
])!
gradient.draw(in: squircle, angle: 270)  // 270° = top→bottom

// ── 3) 중앙 "한" 글자 ──────────────────────────────────────────
// 시스템 폰트는 CoreText 캐스케이드로 한글 글리프(Apple SD Gothic Neo)
// 자동 fallback. weight: .bold로 두께 확보.
let fontSize = size * 0.62
let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)

let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center

// 살짝의 그림자로 입체감 (선택적, 너무 강하지 않게)
let shadow = NSShadow()
shadow.shadowColor = NSColor(white: 0, alpha: 0.18)
shadow.shadowOffset = NSSize(width: 0, height: -size * 0.012)
shadow.shadowBlurRadius = size * 0.025

let attrs: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: NSColor.white,
    .paragraphStyle: paragraph,
    .shadow: shadow,
]

let text = "한" as NSString
let textBounds = text.size(withAttributes: attrs)

// 시각적 중앙(font의 metric box가 글리프보다 크기 때문에 약간 보정).
let yOffset = -size * 0.045
let drawRect = NSRect(
    x: 0,
    y: (size - textBounds.height) / 2 + yOffset,
    width: size,
    height: textBounds.height
)
text.draw(in: drawRect, withAttributes: attrs)

NSGraphicsContext.restoreGraphicsState()

// ── 4) PNG 저장 ────────────────────────────────────────────────
guard let cgImage = ctx.makeImage() else { fatalError("CGImage 생성 실패") }
let bitmap = NSBitmapImageRep(cgImage: cgImage)
guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("PNG 인코딩 실패")
}

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "icon_1024.png"

try png.write(to: URL(fileURLWithPath: outputPath))
print("✅ \(pixelSize)×\(pixelSize) PNG 생성: \(outputPath)")
