#!/usr/bin/env bash
# ── ENGINE FILE (base-owned) — AGENT NOTICE ─────────────────────────────────
# In a DERIVED VAULT (git origin is not the obsidian-base repo): if this script
# is buggy, do NOT fix it here and do NOT open a PR against the base repo —
# FILE A GITHUB ISSUE against the upstream base (.agents/.base-url if present,
# else Object-3/obsidian-base) with the error + proposed fix in the issue body.
# Local patches are overwritten by the next update-base and help no other clone.
# See AGENTS.md → "Engine bugs & improvements found in a derived vault".
# ─────────────────────────────────────────────────────────────────────────────
# End-to-end test for update-base.sh's overlay, exercising the exact scenario in
# issue #38 bug #1: a stale fork that predates `.agents/mcp-quick-orient.md` must
# receive that file when it runs /update-base against a base that has it.
#
# Fully offline: builds two throwaway git repos in a temp dir (a "base" cloned
# from this repo's committed HEAD, and a "stale fork" with the file removed), runs
# update-base.sh in the fork pointed at the local base via BASE_REPO_URL, then
# asserts the file was overlaid and staged. No network, no side effects outside
# the temp dir.
#
#   .agents/scripts/test-update-base-overlay.sh
#
# Exits non-zero if any assertion fails. Requires git + jq (same as update-base).
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OVERLAY_FILE=".agents/mcp-quick-orient.md"

fail=0
ok()  { printf '  ok: %s\n' "$*"; }
bad() { printf '  FAIL: %s\n' "$*"; fail=1; }

command -v git >/dev/null || { echo "git required"; exit 1; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
base="$tmp/base"; fork="$tmp/fork"

# ── Base: this repo's committed HEAD, on a `main` branch (the default BASE_REF).
git clone -q --local "$ROOT" "$base"
git -C "$base" checkout -q -B main
[ -f "$base/$OVERLAY_FILE" ] || { echo "precondition failed: base lacks $OVERLAY_FILE (is the #38 fix committed?)"; exit 1; }
grep -q '".agents/mcp-quick-orient.md"' "$base/.agents/scripts/update-base.sh" \
  || { echo "precondition failed: base update-base.sh missing the PATHS entry (is the #38 fix committed?)"; exit 1; }

# ── Fork: clone the base, then simulate a pre-#38 stale fork by deleting the file.
git clone -q --local "$base" "$fork"
git -C "$fork" checkout -q -B main
git -C "$fork" rm -q "$OVERLAY_FILE"
git -C "$fork" -c user.email=t@t -c user.name=t commit -q -m "stale: pre-#38 fork without mcp-quick-orient.md"
[ -f "$fork/$OVERLAY_FILE" ] && bad "setup: fork still has $OVERLAY_FILE" || ok "setup: stale fork lacks $OVERLAY_FILE"

# ── Run update-base in the fork against the local base.
echo "== running update-base.sh in the stale fork =="
( cd "$fork" && BASE_REPO_URL="$base" BASE_REF=main .agents/scripts/update-base.sh ) >"$tmp/out.log" 2>&1
run_rc=$?
sed 's/^/     | /' "$tmp/out.log"
[ "$run_rc" -eq 0 ] && ok "update-base exited 0" || bad "update-base exited $run_rc"

# ── Assert: the file is now present, staged, and byte-identical to the base.
if [ -f "$fork/$OVERLAY_FILE" ]; then
  ok "overlay landed: $OVERLAY_FILE now exists in the fork"
else
  bad "overlay MISSED: $OVERLAY_FILE still absent (this is exactly issue #38 bug #1)"
fi

if git -C "$fork" diff --cached --name-only | grep -qxF "$OVERLAY_FILE"; then
  ok "overlay is staged (ready to commit)"
else
  bad "overlay not staged"
fi

if [ -f "$fork/$OVERLAY_FILE" ] && cmp -s "$base/$OVERLAY_FILE" "$fork/$OVERLAY_FILE"; then
  ok "overlaid content is byte-identical to base"
else
  bad "overlaid content differs from base (or missing)"
fi

echo
if [ "$fail" -eq 0 ]; then echo "PASS: update-base overlay (issue #38 bug #1)"; else echo "FAIL: update-base overlay (issue #38 bug #1)"; fi
exit "$fail"
