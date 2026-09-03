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
#
# 환경변수:
#   CODESIGN_IDENTITY   서명에 쓸 인증서 (기본 "-" = ad-hoc)
#   UNIVERSAL=1         Intel+Apple Silicon 유니버설 빌드 (타 맥 배포용)

set -euo pipefail

PROJECT_NAME="ShiftSpaceMac"
# 코드 서명 ID. 기본값 "-"는 ad-hoc 서명으로, 빌드할 때마다 바이너리
# 해시가 바뀌어 접근성(TCC) 권한이 초기화된다. 개발 인증서 이름을
# CODESIGN_IDENTITY 환경변수로 넘기면 식별자가 고정되어 권한이 유지된다.
#   예) export CODESIGN_IDENTITY="Apple Development: Hong Gildong (XXXXXXXXXX)"
#   사용 가능한 인증서: security find-identity -v -p codesigning
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
BUNDLE_ID="com.keyin.ShiftSpaceMac"
BUILD_DIR=".build"
APP_DIR="build/${PROJECT_NAME}.app"

case "${1:-build}" in

  build)
    echo "🔨 Debug 빌드 중..."
    swift build
    codesign --force --sign "${CODESIGN_IDENTITY}" "${BUILD_DIR}/debug/${PROJECT_NAME}" 2>/dev/null || true
    echo "✅ 빌드 완료: ${BUILD_DIR}/debug/${PROJECT_NAME}"
    ;;

  run)
    echo "🔨 빌드 후 실행..."
    swift build
    codesign --force --sign "${CODESIGN_IDENTITY}" "${BUILD_DIR}/debug/${PROJECT_NAME}" 2>/dev/null || true
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
    # UNIVERSAL=1 이면 Intel + Apple Silicon 유니버설 바이너리로 빌드한다.
    # 기본(호스트 전용) 빌드는 arm64 맥에서 만들면 arm64 전용이 되어
    # Intel 맥으로 복사했을 때 아예 실행되지 않는다 (Rosetta로도 불가).
    # 다른 맥에 배포할 목적이면 UNIVERSAL=1을 쓸 것.
    if [ "${UNIVERSAL:-0}" = "1" ]; then
      echo "   (유니버설: arm64 + x86_64)"
      swift build -c release --arch arm64 --arch x86_64
      # --arch를 주면 산출물 경로가 .build/apple/Products/Release/ 로 바뀐다
      PRODUCT=".build/apple/Products/Release/${PROJECT_NAME}"
    else
      swift build -c release
      PRODUCT="${BUILD_DIR}/release/${PROJECT_NAME}"
    fi

    # .app 번들 디렉토리 구조 생성
    rm -rf "${APP_DIR}"
    mkdir -p "${APP_DIR}/Contents/MacOS"
    mkdir -p "${APP_DIR}/Contents/Resources"

    # 실행 파일 복사
    cp "${PRODUCT}" "${APP_DIR}/Contents/MacOS/"

    # Info.plist 복사
    cp "Sources/ShiftSpaceMac/Resources/Info.plist" "${APP_DIR}/Contents/"

    # 앱 아이콘 (없으면 생성)
    if [ ! -f "Sources/ShiftSpaceMac/Resources/AppIcon.icns" ]; then
      echo "🎨 AppIcon.icns 미존재 — 생성 중..."
      ./scripts/build_icon.sh
    fi
    cp "Sources/ShiftSpaceMac/Resources/AppIcon.icns" "${APP_DIR}/Contents/Resources/"

    # 코드 서명 (TCC 권한 식별 안정화)
    codesign --force --deep --sign "${CODESIGN_IDENTITY}" "${APP_DIR}"

    echo "✅ .app 번들 생성 완료: ${APP_DIR}"
    echo "   아키텍처: $(lipo -archs "${APP_DIR}/Contents/MacOS/${PROJECT_NAME}")"
    echo ""
    echo "──────────────────────────────────────────────────"
    if [ "${CODESIGN_IDENTITY}" = "-" ]; then
      echo "🔏 ad-hoc 서명 적용됨."
      echo ""
      echo "⚠️  ad-hoc 서명은 빌드할 때마다 바이너리 해시가 바뀌므로"
      echo "    접근성 권한이 매번 초기화됩니다. 인증서를 지정하세요:"
      echo ""
      echo "  security find-identity -v -p codesigning   # 인증서 목록"
      echo "  export CODESIGN_IDENTITY=\"Apple Development: ...\""
    else
      echo "🔏 서명 완료: ${CODESIGN_IDENTITY}"
    fi
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
