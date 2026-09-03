#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  diagnose.sh — ShiftSpaceMac이 동작하지 않을 때 원인 진단      ║
# ╚══════════════════════════════════════════════════════════════╝
#
# 다른 맥으로 .app을 복사한 뒤 동작하지 않을 때 실행하세요.
#
#   ./diagnose.sh [ShiftSpaceMac.app 경로]
#
# 경로를 생략하면 /Applications, ~/Applications, 현재 디렉터리를 찾습니다.

BUNDLE_ID="com.keyin.ShiftSpaceMac"
FAIL=0
WARN=0

ok()   { printf "  \033[32m✅\033[0m %s\n" "$1"; }
bad()  { printf "  \033[31m❌\033[0m %s\n" "$1"; FAIL=$((FAIL+1)); }
warn() { printf "  \033[33m⚠️\033[0m  %s\n" "$1"; WARN=$((WARN+1)); }
hdr()  { printf "\n\033[1m%s\033[0m\n" "$1"; }

# ── 앱 찾기 ───────────────────────────────────────────────────
APP="${1:-}"
if [ -z "$APP" ]; then
  for c in "/Applications/ShiftSpaceMac.app" \
           "$HOME/Applications/ShiftSpaceMac.app" \
           "./ShiftSpaceMac.app" \
           "./build/ShiftSpaceMac.app"; do
    [ -d "$c" ] && APP="$c" && break
  done
fi

hdr "0. 앱 위치"
if [ -z "$APP" ] || [ ! -d "$APP" ]; then
  bad "ShiftSpaceMac.app을 찾을 수 없습니다. 경로를 인자로 넘겨주세요."
  echo "     예: ./diagnose.sh /Applications/ShiftSpaceMac.app"
  exit 1
fi
APP="$(cd "$(dirname "$APP")" && pwd)/$(basename "$APP")"
ok "$APP"
EXE="$APP/Contents/MacOS/ShiftSpaceMac"
[ -x "$EXE" ] || bad "실행 파일이 없습니다: $EXE"

# ── 1. 하드웨어 / OS ─────────────────────────────────────────
hdr "1. 하드웨어 · OS 호환성"
ARCH_HOST="$(uname -m)"
echo "  이 머신: $ARCH_HOST / macOS $(sw_vers -productVersion) / $(sysctl -n machdep.cpu.brand_string 2>/dev/null)"

if [ -x "$EXE" ]; then
  ARCHS="$(lipo -archs "$EXE" 2>/dev/null)"
  echo "  앱 아키텍처: $ARCHS"
  if ! echo " $ARCHS " | grep -q " $ARCH_HOST "; then
    bad "아키텍처 불일치 — 이 앱은 이 맥에서 실행될 수 없습니다."
    echo "     arm64 전용 빌드는 Intel 맥에서 Rosetta로도 실행되지 않습니다."
    echo "     해결: 유니버설 빌드가 필요합니다 (아래 안내 참조)"
  else
    ok "아키텍처 일치"
  fi
  MINOS="$(otool -l "$EXE" 2>/dev/null | grep -A3 LC_BUILD_VERSION | awk '/minos/{print $2; exit}')"
  CUR="$(sw_vers -productVersion)"
  echo "  요구 최소 OS: ${MINOS:-?} / 현재: $CUR"
  if [ -n "$MINOS" ]; then
    LOWEST="$(printf '%s\n%s\n' "$MINOS" "$CUR" | sort -V | head -1)"
    if [ "$LOWEST" != "$MINOS" ]; then
      bad "macOS 버전이 낮습니다 (${MINOS} 이상 필요)"
    else
      ok "OS 버전 충족"
    fi
  fi
fi

# ── 2. Gatekeeper / 격리 속성 ────────────────────────────────
hdr "2. Gatekeeper · 격리(quarantine)"
if xattr -p com.apple.quarantine "$APP" >/dev/null 2>&1; then
  bad "격리 속성이 붙어 있습니다 (AirDrop·다운로드·압축해제로 복사한 경우)"
  echo "     해결: xattr -dr com.apple.quarantine \"$APP\""
else
  ok "격리 속성 없음"
fi

if codesign --verify --deep --strict "$APP" 2>/dev/null; then
  ok "코드 서명 무결성 정상"
  codesign -dvvv "$APP" 2>&1 | grep -E "^Authority|^TeamIdentifier" | sed 's/^/     /'
else
  bad "코드 서명이 깨졌습니다 (복사 과정에서 손상되었을 수 있음)"
  echo "     해결: 이 맥에서 ad-hoc 재서명 → codesign --force --deep --sign - \"$APP\""
fi

SPCTL="$(spctl -a -t exec -vv "$APP" 2>&1)"
if echo "$SPCTL" | grep -q "accepted"; then
  ok "Gatekeeper 통과"
else
  warn "Gatekeeper 거부 — 공증(notarization)되지 않은 앱입니다"
  echo "     격리 속성이 없으면 대개 그냥 실행됩니다."
  echo "     차단된다면: 우클릭 → 열기, 또는 시스템 설정 → 개인정보 보호 및 보안 → '확인 없이 열기'"
fi

# ── 3. 실행 상태 ─────────────────────────────────────────────
hdr "3. 실행 상태"
PID="$(pgrep -f "ShiftSpaceMac.app/Contents/MacOS" | head -1)"
if [ -n "$PID" ]; then
  ok "실행 중 (PID $PID)"
  ps -o pid,etime,%cpu,rss -p "$PID" | tail -1 | sed 's/^/     /'
else
  bad "실행되고 있지 않습니다"
  echo "     해결: open \"$APP\"  로 실행 후 이 스크립트를 다시 돌려보세요."
fi

# ── 4. 접근성 권한 ───────────────────────────────────────────
hdr "4. 접근성 권한 (가장 흔한 원인)"

# 앱이 os.Logger로 남긴 실제 권한 상태를 읽는다. TCC 데이터베이스는
# SIP로 막혀 있지만, 앱이 스스로 기록한 값은 시스템 로그에서 읽을 수 있다.
# (zsh에는 log 빌트인이 있어 반드시 /usr/bin/log 로 호출해야 한다)
LOGOUT="$(/usr/bin/log show --last 30m \
          --predicate 'subsystem == "com.keyin.ShiftSpaceMac"' \
          --style compact 2>/dev/null | grep -v '^Timestamp')"

if [ -n "$LOGOUT" ]; then
  echo "  앱이 남긴 로그:"
  echo "$LOGOUT" | tail -8 | sed 's/^/     /'
  echo
  if echo "$LOGOUT" | grep -q "접근성권한=false"; then
    bad "앱이 접근성 권한 없음을 보고했습니다 — 이것이 원인입니다"
  elif echo "$LOGOUT" | grep -q "접근성권한=true"; then
    ok "접근성 권한 있음"
    if echo "$LOGOUT" | grep -q "CGEventTap 생성 성공"; then
      ok "이벤트 탭 생성 성공 — 키 감지는 정상입니다"
      echo "     여기까지 정상인데 전환이 안 된다면 5번 항목을 보세요."
    elif echo "$LOGOUT" | grep -q "CGEventTap 생성 실패"; then
      bad "권한은 있는데 이벤트 탭 생성에 실패했습니다"
    fi
  fi
else
  warn "앱 로그가 없습니다 — 로깅이 없는 구버전이거나, 아직 실행되지 않았습니다"
  echo "     최신 빌드로 교체 후 실행하고 다시 시도하세요."
fi

echo
echo "  직접 확인하려면:"
echo "     시스템 설정 → 개인정보 보호 및 보안 → 접근성"
echo "     • 목록에 ShiftSpaceMac이 있고 토글이 켜져 있는가?"
echo "     • 목록에 있는데도 안 되면: 항목을 '−'로 삭제 후 '+'로 이 경로를 다시 추가"
echo "       $APP"
echo
echo
echo "  권한이 꼬였을 때 초기화 (초기화 후 앱을 다시 실행하면 요청 창이 뜹니다):"
echo "     tccutil reset Accessibility $BUNDLE_ID"
echo
echo "  실시간으로 보려면 (Shift+Space를 누르며 관찰):"
echo "     /usr/bin/log stream --predicate 'subsystem == \"$BUNDLE_ID\"' --level debug"

# ── 5. 입력 소스 구성 ────────────────────────────────────────
hdr "5. 입력 소스 · 시스템 단축키 (이 앱이 의존하는 설정)"
SRC="$(defaults read com.apple.HIToolbox AppleEnabledInputSources 2>/dev/null)"
if echo "$SRC" | grep -q "inputmethod.Korean"; then
  ok "한국어 입력 소스가 추가되어 있음"
else
  bad "한국어 입력 소스가 없습니다"
  echo "     해결: 시스템 설정 → 키보드 → 입력 소스에서 '한국어 - 2벌식' 추가"
fi
NSRC="$(echo "$SRC" | grep -c InputSourceKind)"
if [ "${NSRC:-0}" -lt 2 ]; then
  warn "입력 소스가 1개뿐이면 전환할 대상이 없습니다"
fi

python3 - "$BUNDLE_ID" <<'PY'
import subprocess, plistlib, os, sys
p = os.path.expanduser("~/Library/Preferences/com.apple.symbolichotkeys.plist")
try:
    raw = subprocess.run(["plutil","-convert","xml1","-o","-",p],
                         capture_output=True).stdout
    hk = plistlib.loads(raw)["AppleSymbolicHotKeys"].get("60")
except Exception:
    hk = None

if hk is None:
    print("  \033[31m❌\033[0m '이전 입력 소스 선택' 단축키(key 60) 설정을 찾을 수 없습니다")
    print("     이 앱은 이 단축키를 재생해서 전환합니다. 없으면 Ctrl+Space로 가정합니다.")
else:
    enabled = hk.get("enabled")
    params = hk.get("value", {}).get("parameters", [])
    if not enabled:
        print("  \033[31m❌\033[0m '이전 입력 소스 선택' 단축키가 \033[1m비활성\033[0m 상태입니다")
        print("     → 이 앱이 합성한 키를 시스템이 무시하므로 전환이 되지 않습니다.")
        print("     해결: 시스템 설정 → 키보드 → 키보드 단축키 → 입력 소스")
        print("           '이전 입력 소스 선택' 체크")
    elif len(params) >= 3:
        vk, mod = params[1], params[2]
        names = []
        for bit, n in ((0x20000,"Shift"),(0x40000,"Control"),(0x80000,"Option"),(0x100000,"Command")):
            if mod & bit: names.append(n)
        combo = "+".join(names + ([ "Space" ] if vk == 49 else [f"keyCode {vk}"]))
        print(f"  \033[32m✅\033[0m '이전 입력 소스 선택' 활성 — {combo}")
        if mod & 0x20000 and vk == 49:
            print("  \033[33m⚠️\033[0m  시스템 단축키가 Shift+Space입니다.")
            print("     이 앱의 트리거와 같아 충돌할 수 있습니다. 다른 조합을 권장합니다.")
PY

# ── 6. LaunchAgent ───────────────────────────────────────────
hdr "6. 로그인 시 자동 실행(LaunchAgent)"
PLIST="$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"
if [ -f "$PLIST" ]; then
  PROG="$(plutil -extract ProgramArguments.0 raw -o - "$PLIST" 2>/dev/null)"
  echo "  plist 경로: $PLIST"
  echo "  가리키는 실행 파일: $PROG"
  if [ -x "$PROG" ]; then
    ok "경로 유효"
  else
    bad "plist가 존재하지 않는 경로를 가리킵니다 (다른 맥에서 복사해 온 plist)"
    echo "     해결: 메뉴바 → '로그인 시 자동 실행'을 껐다 켜서 이 맥 기준으로 다시 등록"
    echo "     또는: rm \"$PLIST\""
  fi
else
  echo "  (자동 실행 미설정 — 수동 실행만 한다면 정상입니다)"
fi

# ── 결론 ─────────────────────────────────────────────────────
hdr "결론"
if [ "$FAIL" -gt 0 ]; then
  printf "  \033[31m%d건의 문제\033[0m, %d건의 주의사항이 발견되었습니다. 위의 ❌부터 해결하세요.\n" "$FAIL" "$WARN"
else
  printf "  차단 요인은 발견되지 않았습니다 (주의 %d건).\n" "$WARN"
  echo "  그래도 안 된다면 4번 접근성 권한을 다시 확인해 주세요 — 가장 흔한 원인입니다."
fi
echo
