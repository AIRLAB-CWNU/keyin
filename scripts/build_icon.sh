#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  build_icon.sh — AppIcon.icns 생성                             ║
# ╚══════════════════════════════════════════════════════════════╝
#
# generate_icon.swift로 1024×1024 마스터 PNG를 만든 뒤,
# sips로 표준 iconset 사이즈(16~1024)로 리사이즈하고
# iconutil로 .icns 번들로 묶는다.
#
# 결과: Sources/ShiftSpaceMac/Resources/AppIcon.icns

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RES_DIR="$ROOT_DIR/Sources/ShiftSpaceMac/Resources"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

ICONSET="$TMP/AppIcon.iconset"
MASTER="$TMP/icon_1024.png"
mkdir -p "$ICONSET"

echo "🎨 마스터 PNG 생성 중..."
swift "$SCRIPT_DIR/generate_icon.swift" "$MASTER"

echo "🪄 iconset 사이즈 생성 중..."
# 표준 macOS iconset 매핑 (px:파일명)
sizes=(
  "16:icon_16x16.png"
  "32:icon_16x16@2x.png"
  "32:icon_32x32.png"
  "64:icon_32x32@2x.png"
  "128:icon_128x128.png"
  "256:icon_128x128@2x.png"
  "256:icon_256x256.png"
  "512:icon_256x256@2x.png"
  "512:icon_512x512.png"
  "1024:icon_512x512@2x.png"
)

for entry in "${sizes[@]}"; do
  px="${entry%%:*}"
  name="${entry##*:}"
  sips -z "$px" "$px" "$MASTER" --out "$ICONSET/$name" >/dev/null
done

echo "📦 .icns 묶는 중..."
mkdir -p "$RES_DIR"
iconutil -c icns "$ICONSET" -o "$RES_DIR/AppIcon.icns"

echo "✅ 생성 완료: $RES_DIR/AppIcon.icns"
