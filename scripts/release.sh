#!/bin/bash
# Prepare a release:  scripts/release.sh 1.1.0
# Bumps VERSION, builds dist/ClaudeNotify.zip, and updates the Homebrew cask's version and sha256.
# Publishing (commit, tag, GitHub release upload) is printed at the end for you to run.
set -euo pipefail
cd "$(dirname "$0")/.."
NEW="${1:?usage: scripts/release.sh <version, e.g. 1.1.0>}"

echo "$NEW" > VERSION
./build.sh --dist
SHA="$(shasum -a 256 dist/ClaudeNotify.zip | cut -d' ' -f1)"
sed -i '' -E "s/^  version \".*\"/  version \"$NEW\"/; s/^  sha256 \".*\"/  sha256 \"$SHA\"/" Casks/claudenotify.rb

cat <<EOF

Release $NEW ready (sha256 $SHA). To publish:
  git commit -am "Release $NEW" && git tag v$NEW && git push && git push --tags
  gh release create v$NEW dist/ClaudeNotify.zip --title "ClaudeNotify $NEW" --generate-notes
EOF
