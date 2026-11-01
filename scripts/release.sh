#!/bin/bash
# Prepare a release:  scripts/release.sh 1.1.0
# Bumps VERSION, builds dist/ClaudeNotify.zip, and updates the Homebrew cask's version and sha256
# in the tap repo (a checkout of github.com/lhegstrom/homebrew-tap; override with TAP_DIR=...).
# Publishing (commit, tag, GitHub release upload, tap push) is printed at the end for you to run.
set -euo pipefail
cd "$(dirname "$0")/.."
NEW="${1:?usage: scripts/release.sh <version, e.g. 1.1.0>}"
TAP_DIR="${TAP_DIR:-../homebrew-tap}"
CASK="$TAP_DIR/Casks/claudenotify.rb"
[ -f "$CASK" ] || { echo "Cask not found at $CASK (clone lhegstrom/homebrew-tap next to this repo, or set TAP_DIR)" >&2; exit 1; }

echo "$NEW" > VERSION
./build.sh --dist
SHA="$(shasum -a 256 dist/ClaudeNotify.zip | cut -d' ' -f1)"
sed -i '' -E "s/^  version \".*\"/  version \"$NEW\"/; s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$CASK"

cat <<EOF

Release $NEW ready (sha256 $SHA). To publish:
  git commit -am "Release $NEW" && git tag v$NEW && git push && git push --tags
  gh release create v$NEW dist/ClaudeNotify.zip --title "ClaudeNotify $NEW" --generate-notes
  git -C "$TAP_DIR" commit -am "claudenotify $NEW" && git -C "$TAP_DIR" push
EOF
