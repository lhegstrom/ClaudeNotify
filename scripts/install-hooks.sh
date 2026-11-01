#!/bin/bash
# Install (or remove) the ClaudeNotify hook for Claude Code.
#   install-hooks.sh             copy notify.sh to ~/.claude/hooks/ and register it in ~/.claude/settings.json
#   install-hooks.sh --uninstall remove the hook entries and script (config and history are kept)
# Existing hooks are left alone; settings.json is backed up before any change.
set -euo pipefail

HOOKS_DIR="$HOME/.claude/hooks"
SCRIPT="$HOOKS_DIR/notify.sh"
SETTINGS="$HOME/.claude/settings.json"
CMD="~/.claude/hooks/notify.sh"
MARK="hooks/notify.sh" # any hook command containing this is ours

command -v jq >/dev/null || { echo "ClaudeNotify needs jq (included with macOS 15+, or: brew install jq)" >&2; exit 1; }

# notify.sh sits next to this script, both in the app bundle and in the source tree (../hooks).
here="$(cd "$(dirname "$0")" && pwd)"
src="$here/notify.sh"; [ -f "$src" ] || src="$here/../hooks/notify.sh"

backup() { [ -f "$SETTINGS" ] && cp "$SETTINGS" "$SETTINGS.bak-claudenotify"; }

if [ "${1:-}" = "--uninstall" ]; then
  if [ -f "$SETTINGS" ]; then
    backup
    jq --arg m "$MARK" '
      if .hooks then
        .hooks |= (with_entries(.value |= (map(.hooks |= map(select((.command // "") | contains($m) | not)))
                                           | map(select(.hooks | length > 0))))
                   | with_entries(select(.value | length > 0)))
        | if .hooks == {} then del(.hooks) else . end
      else . end' "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
  fi
  rm -f "$SCRIPT"
  echo "Removed ClaudeNotify hooks."
  exit 0
fi

mkdir -p "$HOOKS_DIR"
if [ -f "$SCRIPT" ] && ! cmp -s "$src" "$SCRIPT"; then
  cp "$SCRIPT" "$SCRIPT.bak"
  echo "Updated $SCRIPT (previous version saved as notify.sh.bak)"
fi
cp "$src" "$SCRIPT"; chmod +x "$SCRIPT"

[ -s "$SETTINGS" ] || echo '{}' > "$SETTINGS"
backup
jq --arg c "$CMD" --arg m "$MARK" '
  def ensure(ev; cmd; t):
    if [(.hooks[ev] // [])[].hooks[]?.command // empty] | any(contains($m)) then .
    else .hooks[ev] = ((.hooks[ev] // []) + [{hooks: [{type: "command", command: cmd, timeout: t}]}]) end;
  ensure("Stop"; $c; 15) | ensure("Notification"; $c; 15) | ensure("UserPromptSubmit"; $c; 5)
  | ensure("SessionEnd"; $c; 5) | ensure("PostToolUse"; $c + " post-tool"; 5)' \
  "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
echo "ClaudeNotify hooks installed. New Claude Code sessions will report to the menu bar."
