#!/bin/bash
# WorkClock.app을 빌드한다. Xcode 없이 Command Line Tools의 swiftc만 쓴다.
#
#   ./build.sh                 빌드 후 ~/Applications/WorkClock.app에 설치
#   ./build.sh --output DIR    빌드 후 DIR/WorkClock.app에만 둔다 (Homebrew formula용)
#   ./build.sh --no-install    build/WorkClock.app까지만 만든다

set -euo pipefail
cd "$(dirname "$0")"

MODE="install"
OUTPUT=""
case "${1:-}" in
  --output)
    MODE="output"
    OUTPUT="${2:?--output 뒤에 경로가 필요합니다}"
    ;;
  --no-install)
    MODE="none"
    ;;
  "") ;;
  *)
    echo "알 수 없는 옵션: $1" >&2
    exit 2
    ;;
esac

VERSION="$(sed -n 's/^let appVersion = "\(.*\)"$/\1/p' main.swift)"
MIN_MACOS="13.0"
ARCH="$(uname -m)"
BUILD_DIR="build"
APP="$BUILD_DIR/WorkClock.app"

rm -rf "$BUILD_DIR"
mkdir -p "$APP/Contents/MacOS"

echo "==> swiftc 빌드 (WorkClock $VERSION, $ARCH, macOS $MIN_MACOS 이상)"
swiftc -O -target "$ARCH-apple-macos$MIN_MACOS" main.swift -o "$APP/Contents/MacOS/WorkClock"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>WorkClock</string>
  <key>CFBundleDisplayName</key>
  <string>WorkClock</string>
  <key>CFBundleIdentifier</key>
  <string>io.github.msk226.workclock</string>
  <key>CFBundleExecutable</key>
  <string>WorkClock</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$VERSION</string>
  <key>CFBundleDevelopmentRegion</key>
  <string>ko</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_MACOS</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHumanReadableCopyright</key>
  <string>MIT License</string>
</dict>
</plist>
PLIST

echo "==> ad-hoc 서명"
# Finder 정보 같은 확장 속성이 남아 있으면 codesign이 거부한다.
xattr -cr "$APP"
codesign --force --sign - "$APP"
codesign --verify "$APP"

case "$MODE" in
  output)
    mkdir -p "$OUTPUT"
    rm -rf "$OUTPUT/WorkClock.app"
    cp -R "$APP" "$OUTPUT/WorkClock.app"
    echo "==> $OUTPUT/WorkClock.app"
    ;;
  install)
    DEST="$HOME/Applications/WorkClock.app"
    mkdir -p "$HOME/Applications"
    if pgrep -x WorkClock >/dev/null; then
      echo "==> 실행 중인 WorkClock 종료"
      pkill -x WorkClock || true
      sleep 1
    fi
    rm -rf "$DEST"
    cp -R "$APP" "$DEST"
    echo "==> $DEST 에 설치했습니다. 실행: open \"$DEST\""
    ;;
  none)
    echo "==> $APP"
    ;;
esac
