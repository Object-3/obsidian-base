#!/usr/bin/env bash
# SessionStart hook (Claude Code): a passive, self-surfacing nudge to consolidate the vault.
# When it's been a while AND enough new agent sessions have piled up since the last dream,
# it prints ONE line into session context offering `/vault-dream`. Otherwise it stays silent.
#
# Unlike the sibling sync hook (sync-skills-if-stale.sh), which backgrounds work silently,
# this one PRINTS to stdout so the offer surfaces in *this* session — the agent can relay it.
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
  local iso="$1" e
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

printf '🌙 %s unconsolidated session(s) since your last dream — run /vault-dream to fold learnings into the KB and consolidate the vault.\n' "$count"
exit 0
