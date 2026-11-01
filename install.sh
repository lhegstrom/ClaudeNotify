#!/bin/bash
# One-line installer:  curl -fsSL https://raw.githubusercontent.com/lhegstrom/ClaudeNotify/main/install.sh | bash
# Downloads the latest release into ~/Applications, installs the Claude Code hooks, and launches the app.
# (Files fetched with curl aren't quarantined, so the unsigned app opens without a Gatekeeper prompt.)
set -euo pipefail
REPO="lhegstrom/ClaudeNotify"
URL="https://github.com/$REPO/releases/latest/download/ClaudeNotify.zip"
DEST="$HOME/Applications"

[ "$(sw_vers -productVersion | cut -d. -f1)" -ge 15 ] || { echo "ClaudeNotify requires macOS 15 or later." >&2; exit 1; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
echo "Downloading ClaudeNotify…"
curl -fsSL "$URL" -o "$tmp/ClaudeNotify.zip"
ditto -x -k "$tmp/ClaudeNotify.zip" "$tmp"

pkill -x ClaudeNotify 2>/dev/null || true
mkdir -p "$DEST"
rm -rf "$DEST/ClaudeNotify.app"
mv "$tmp/ClaudeNotify.app" "$DEST/"
xattr -dr com.apple.quarantine "$DEST/ClaudeNotify.app" 2>/dev/null || true

"$DEST/ClaudeNotify.app/Contents/Resources/install-hooks.sh"
open "$DEST/ClaudeNotify.app"
echo "Installed $DEST/ClaudeNotify.app — look for the bell in your menu bar."
