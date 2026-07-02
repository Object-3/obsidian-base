#!/usr/bin/env bash
# SessionStart hook (Claude Code): a passive, self-surfacing nudge to consolidate the vault.
# When it's been a while AND enough new agent sessions have piled up since the last dream,
# it injects a one-line offer to run `/vault-dream` into the session. Otherwise it stays silent.
#
# Unlike the sibling sync hook (sync-skills-if-stale.sh), which backgrounds work silently,
# this one emits the offer so it surfaces in *this* session. It uses the SessionStart
# `additionalContext` JSON channel — the documented, version-robust way to inject context at
# session start — and phrases the line so the agent relays it to the user (a SessionStart
# hook's output is agent context, not a native UI popup). If a harness doesn't parse the
# JSON, the text still lands in context verbatim, so the nudge degrades gracefully.
# Same safety envelope: set -euo pipefail, always exit 0, fast, never blocks or fails a session.
#
# Repo-scoped by construction: it's registered in this repo's .claude/settings.json via
# ${CLAUDE_PROJECT_DIR}, so it only fires when Claude Code starts INSIDE the vault repo —
# never when another project merely consumes the vault over the Obsidian MCP.
#
# Gate: fires only when BOTH thresholds are crossed — >= ELAPSED_HOURS since the last dream
# AND >= MIN_SESSIONS new sessions. Any broken/uninitialized state (missing or unparseable
# watermark, missing scanner) makes it silent — it nudges, it never nags or errors.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STATE="${DREAM_STATE:-$ROOT/.agents/dream-state}"
SCAN="$ROOT/.agents/scripts/dream-scan.sh"

ELAPSED_HOURS=24
MIN_SESSIONS=5

# ISO-8601 -> epoch seconds, portable across GNU (date -d) and BSD/macOS (date -j -f).
# GNU date -d is unavailable on macOS, so trying it alone would silently break the math.
iso_to_epoch() {
  local iso e
  iso=$(printf '%s' "$1" | tr -d '[:space:]')   # strip CR (CRLF from a Windows-synced vault) / stray whitespace
  [ -n "$iso" ] || { echo 0; return; }
  e=$(date -u -d "$iso" +%s 2>/dev/null)                         && { echo "$e"; return; }
  e=$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$iso" +%s 2>/dev/null)  && { echo "$e"; return; }
  echo 0
}

# Broken/uninitialized state -> silent. Never nag, never error a session.
[ -f "$STATE" ] || exit 0
[ -x "$SCAN" ] || [ -f "$SCAN" ] || exit 0

last=$(iso_to_epoch "$(head -n1 "$STATE" 2>/dev/null || echo "")")
[ "$last" -gt 0 ] 2>/dev/null || exit 0    # unparseable watermark -> silent

now=$(date +%s)
elapsed=$(( now - last ))
[ "$elapsed" -ge $(( ELAPSED_HOURS * 3600 )) ] || exit 0   # time gate

# Count new sessions since the watermark. If the scan errors or returns a non-integer,
# treat it as "can't tell" -> silent.
count=$(bash "$SCAN" --count 2>/dev/null || echo "")
case "$count" in ''|*[!0-9]*) exit 0 ;; esac
[ "$count" -ge "$MIN_SESSIONS" ] || exit 0   # volume gate

# Emit as SessionStart additionalContext so the agent reliably sees it and relays it.
# $count is validated as digits above, so it's safe to interpolate into the JSON unescaped.
printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"🌙 %s unconsolidated agent session(s) have accumulated since the last vault dream. Tell the user they can run /vault-dream to fold durable learnings into the knowledge base and consolidate the vault — it opens a reviewable pull request and never writes to main."}}\n' "$count"
exit 0
