#!/bin/bash
# Build ClaudeNotify.app.
#   ./build.sh         build for this Mac, install to ~/Applications, install the Claude Code hooks, launch
#   ./build.sh --dist  universal (arm64 + x86_64) build, zipped to dist/ClaudeNotify.zip; installs nothing
set -euo pipefail
cd "$(dirname "$0")"
VERSION="$(cat VERSION)"

if [ "${1:-}" = "--dist" ]; then
  ARCHS=(--arch arm64 --arch x86_64)
else
  ARCHS=()
fi
swift build -c release ${ARCHS[@]+"${ARCHS[@]}"}
BIN="$(swift build -c release ${ARCHS[@]+"${ARCHS[@]}"} --show-bin-path)/ClaudeNotify"

APP="build/ClaudeNotify.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" \
                        -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns hooks/notify.sh scripts/install-hooks.sh "$APP/Contents/Resources/"
# Ad-hoc signature: free, required on Apple Silicon. Not trusted by Gatekeeper — see README.
codesign --force --sign - "$APP"

if [ "${1:-}" = "--dist" ]; then
  mkdir -p dist; rm -f dist/ClaudeNotify.zip
  ditto -c -k --keepParent "$APP" dist/ClaudeNotify.zip
  echo "Built dist/ClaudeNotify.zip ($VERSION)"
  exit 0
fi

pkill -x ClaudeNotify 2>/dev/null || true
mkdir -p ~/Applications
rm -rf ~/Applications/ClaudeNotify.app && cp -R "$APP" ~/Applications/
"$APP/Contents/Resources/install-hooks.sh"
open ~/Applications/ClaudeNotify.app
echo "Installed ~/Applications/ClaudeNotify.app"
