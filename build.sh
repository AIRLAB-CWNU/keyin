#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  ShiftSpaceMac 빌드 스크립트                                   ║
# ╚══════════════════════════════════════════════════════════════╝
#
# 사용법:
#   chmod +x build.sh
#   ./build.sh          # 빌드만
#   ./build.sh run      # 빌드 후 실행
#   ./build.sh release  # 릴리즈 빌드
#   ./build.sh app      # .app 번들 생성

set -euo pipefail

PROJECT_NAME="ShiftSpaceMac"
BUNDLE_ID="com.keyin.ShiftSpaceMac"
BUILD_DIR=".build"
APP_DIR="build/${PROJECT_NAME}.app"

case "${1:-build}" in

  build)
    echo "🔨 Debug 빌드 중..."
    swift build
    echo "✅ 빌드 완료: ${BUILD_DIR}/debug/${PROJECT_NAME}"
    ;;

  run)
    echo "🔨 빌드 후 실행..."
    swift build
    echo "🚀 실행 중..."
    "${BUILD_DIR}/debug/${PROJECT_NAME}"
    ;;

  release)
    echo "🔨 Release 빌드 중..."
    swift build -c release
    echo "✅ 릴리즈 빌드 완료: ${BUILD_DIR}/release/${PROJECT_NAME}"
    ;;

  app)
    echo "📦 .app 번들 생성 중..."

    # 릴리즈 빌드
    swift build -c release

    # .app 번들 디렉토리 구조 생성
    rm -rf "${APP_DIR}"
    mkdir -p "${APP_DIR}/Contents/MacOS"
    mkdir -p "${APP_DIR}/Contents/Resources"

    # 실행 파일 복사
    cp "${BUILD_DIR}/release/${PROJECT_NAME}" "${APP_DIR}/Contents/MacOS/"

    # Info.plist 복사
    cp "Sources/ShiftSpaceMac/Resources/Info.plist" "${APP_DIR}/Contents/"

    # 앱 아이콘 (없으면 생성)
    if [ ! -f "Sources/ShiftSpaceMac/Resources/AppIcon.icns" ]; then
      echo "🎨 AppIcon.icns 미존재 — 생성 중..."
      ./scripts/build_icon.sh
    fi
    cp "Sources/ShiftSpaceMac/Resources/AppIcon.icns" "${APP_DIR}/Contents/Resources/"

    echo "✅ .app 번들 생성 완료: ${APP_DIR}"
    echo ""
    echo "──────────────────────────────────────────────────"
    echo "📋 코드 서명 (선택사항 — TCC 권한 유지를 위해 권장):"
    echo ""
    echo "  codesign --force --deep --sign - ${APP_DIR}"
    echo ""
    echo "또는 자체 서명 인증서 사용:"
    echo "  codesign --force --deep --sign \"ShiftSpaceMac Dev\" ${APP_DIR}"
    echo "──────────────────────────────────────────────────"
    ;;

  clean)
    echo "🧹 빌드 캐시 정리..."
    swift package clean
    rm -rf build/
    echo "✅ 정리 완료"
    ;;

  *)
    echo "사용법: $0 {build|run|release|app|clean}"
    exit 1
    ;;

esac
