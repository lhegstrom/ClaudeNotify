#!/bin/bash
# Claude Code notification hook (Stop, Notification, UserPromptSubmit, SessionEnd, PostToolUse).
# UserPromptSubmit/SessionEnd/PostToolUse only log state for the menu bar app — they never notify or print.
# Config:  ~/.claude/notify/config.json
# History: ~/.claude/notify/events.jsonl  (read by the menu bar app)
# Phone (ntfy) pushes are deliberately generic — never include project, paths, or message text.

DIR="$HOME/.claude/notify"
CONFIG="$DIR/config.json"
EVENTS="$DIR/events.jsonl"
mkdir -p "$DIR"
ATTN="$DIR/attn"   # one flag file per session currently waiting on the user

# PostToolUse runs after every tool call — bail out before parsing anything unless some session is flagged.
if [ "$1" = "post-tool" ]; then
  shopt -s nullglob; flags=("$ATTN"/*); shopt -u nullglob
  [ ${#flags[@]} -eq 0 ] && { cat >/dev/null; exit 0; }
fi

payload="$(cat)"
cfg() { jq -r --arg k "$1" --arg d "$2" '.[$k] // $d | tostring' "$CONFIG" 2>/dev/null || echo "$2"; }

[ "$(cfg debug_log false)" = "true" ] && printf '%s\n' "$payload" >> "$DIR/debug-payloads.jsonl"

j() { printf '%s' "$payload" | jq -r "$1" 2>/dev/null; }
event="$(j '.hook_event_name // empty')"
session="$(j '.session_id // empty')"
cwd="$(j '.cwd // empty')"
project="$(basename "${cwd:-unknown}")"

# Flatten text for a notification body: collapse whitespace, drop markdown noise, truncate.
summarize() { printf '%s' "$1" | tr '\n\t' '  ' | sed -E 's/[`*#>|]+//g; s/ +/ /g; s/^ //' | cut -c1-"${2:-180}"; }

muted() { [ "$(date +%s)" -lt "$(cfg muted_until 0 | cut -d. -f1)" ]; }

mac_notify() { # title subtitle body sound
  [ "$(cfg mac_enabled true)" = "true" ] || return 0
  muted && return 0
  # Prefer the menu bar app (shows the Claude icon); fall back to osascript if it isn't running.
  if pgrep -x ClaudeNotify >/dev/null 2>&1; then
    q="$DIR/queue"; mkdir -p "$q"; f="$q/$(date +%s)-$$-$RANDOM"
    jq -cn --arg t "$1" --arg s "$2" --arg b "$3" --arg snd "$4" --argjson ts "$(date +%s)" \
      '{title:$t, subtitle:$s, body:$b, sound:$snd, ts:$ts}' > "$f.tmp" && mv "$f.tmp" "$f.json"
    return 0
  fi
  osascript - "$1" "$2" "$3" "$4" >/dev/null 2>&1 <<'AS'
on run argv
  set {t, s, b, snd} to argv
  if snd is "" then
    display notification b with title t subtitle s
  else
    display notification b with title t subtitle s sound name snd
  end if
end run
AS
}

phone_notify() { # message tag priority
  [ "$(cfg phone_enabled true)" = "true" ] || return 0
  muted && return 0
  topic="$(cfg ntfy_topic '')"; [ -n "$topic" ] || return 0
  curl -s -m 8 -H "Title: Claude Code" -H "Tags: $2" -H "Priority: $3" \
    -d "$1" "$(cfg ntfy_server https://ntfy.sh)/$topic" >/dev/null 2>&1 &
}

log_event() { # kind detail bg_count
  jq -cn --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg s "$session" --arg p "$project" \
    --arg c "$cwd" --arg k "$1" --arg d "$2" --argjson n "${3:-0}" \
    '{ts:$ts, session_id:$s, project:$p, cwd:$c, kind:$k, detail:$d, background_running:$n}' >> "$EVENTS"
  # keep history bounded
  if [ "$(wc -l < "$EVENTS")" -gt 400 ]; then tail -n 200 "$EVENTS" > "$EVENTS.tmp" && mv "$EVENTS.tmp" "$EVENTS"; fi
}

flagged=""; [ -n "$session" ] && [ -f "$ATTN/$session" ] && flagged=1
# Any event other than Notification means this session is no longer waiting on the user.
[ -n "$session" ] && [ "$event" != "Notification" ] && rm -f "$ATTN/$session"

case "$event" in
  PostToolUse)
    # Only reached when this session was flagged (flag already cleared above): the user approved.
    [ -n "$flagged" ] && log_event resumed "" 0
    ;;
  UserPromptSubmit)
    log_event working "" 0
    ;;
  SessionEnd)
    log_event ended "$(j '.reason // empty')" 0
    ;;
  Stop)
    # Background tasks still in flight -> Claude will be re-invoked and Stop fires again later.
    # Anything not in a terminal state counts as running. Missing field -> treat as done.
    running="$(j '[.background_tasks // [] | .[] | select((.status // "running" | ascii_downcase)
      | IN("completed","complete","done","failed","error","killed","stopped","cancelled","canceled") | not)] | length')"
    running="${running:-0}"
    if [ "$running" -gt 0 ]; then
      descs="$(j '[.background_tasks[] | .description // .type] | .[0:3] | join(", ")')"
      log_event waiting "$descs" "$running"
      if [ "$(cfg show_waiting true)" = "true" ]; then
        plural=$([ "$running" -eq 1 ] && echo task || echo tasks)
        mac_notify "Claude Code — $project" "Waiting on $running background $plural" \
          "$(summarize "$descs")" "$(cfg sound_waiting '')"
      fi
      exit 0
    fi
    detail="$(summarize "$(j '.last_assistant_message // empty')" 200)"
    log_event done "$detail" 0
    mac_notify "Claude Code — $project" "Task complete" "${detail:-Finished}" "$(cfg sound_done Glass)"
    phone_notify "Task complete" "white_check_mark" "default"
    ;;
  Notification)
    ntype="$(j '.notification_type // empty')"
    [ "$ntype" = "idle_prompt" ] && exit 0   # duplicates the Stop alert
    msg="$(summarize "$(j '.message // empty')" 200)"
    log_event attention "$msg" 0
    mkdir -p "$ATTN" && [ -n "$session" ] && touch "$ATTN/$session"
    mac_notify "Claude Code — $project" "Needs your attention" "${msg:-Waiting for input}" "$(cfg sound_attention Sosumi)"
    phone_notify "Needs your attention" "warning" "high"
    ;;
esac
exit 0
