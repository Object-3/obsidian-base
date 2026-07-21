#!/usr/bin/env bash
# ── ENGINE FILE (base-owned) — AGENT NOTICE ─────────────────────────────────
# In a DERIVED VAULT (git origin is not the obsidian-base repo): if this script
# is buggy, do NOT fix it here and do NOT open a PR against the base repo —
# FILE A GITHUB ISSUE against the upstream base (.agents/.base-url if present,
# else Object-3/obsidian-base) with the error + proposed fix in the issue body.
# Local patches are overwritten by the next update-base and help no other clone.
# See AGENTS.md → "Engine bugs & improvements found in a derived vault".
# ─────────────────────────────────────────────────────────────────────────────
# SessionStart hook (Claude Code): refresh vendored skills if the local copy is
# stale (>7 days) or if the tool pointers are missing/broken. Runs in the
# background, never blocks or fails a session.
#
# This also self-heals the Windows case: if a checkout turned the committed
# symlinks into plain text files, the pointer dirs won't resolve and the sync
# re-materialises them as real copies — no manual intervention.
#
# Caveat: skills are enumerated when the agent launches, so a refresh triggered
# here takes effect on the NEXT session. The committed copies/pointers cover the
# current one.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STAMP="$ROOT/.agents/.skills-last-sync"
SYNC="$ROOT/.agents/scripts/sync-skills.sh"

needs_sync=0
# stale?
if [ -f "$STAMP" ]; then
  last=$(date -d "$(cat "$STAMP")" +%s 2>/dev/null || echo 0)
  now=$(date +%s)
  [ "$(( (now - last) / 86400 ))" -ge 7 ] && needs_sync=1
else
  needs_sync=1
fi
# pointers broken? (e.g. symlinks not preserved on this OS)
[ -f "$ROOT/.claude/skills/INDEX.md" ] || needs_sync=1

[ "$needs_sync" = 0 ] && exit 0
( "$SYNC" >/dev/null 2>&1 & ) || true
exit 0
