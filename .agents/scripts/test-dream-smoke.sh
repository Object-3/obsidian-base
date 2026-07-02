#!/usr/bin/env bash
# Smoke test for the vault-dream shell surface: dream-scan.sh (watermark + scope selection,
# the portable --extract digest) and the dream-if-stale.sh nudge gate.
#
# Self-contained and offline: every read is redirected to a temp fixture store via the
# CLAUDE_PROJECTS_DIR / DREAM_SLUGS / DREAM_STATE overrides the scripts honor, so it NEVER
# touches your real ~/.claude/projects or the tracked .agents/dream-state watermark. Run
# from anywhere in the repo:
#
#   .agents/scripts/test-dream-smoke.sh
#
# Covers the behavioral guarantees that have no other automated check:
#   1. dream-scan selects ONLY session files newer than the watermark
#   2. dream-scan --count matches the number of selected paths
#   3. all-worktrees globs multiple slugs and de-duplicates
#   4. empty / missing store -> empty output, exit 0 (never crashes a caller)
#   5. --extract emits Claude + Codex message shapes, strips tool noise, tolerates malformed lines
#   6. dream-if-stale fires ONLY when >=24h elapsed AND >=5 new sessions
#   7. dream-if-stale is silent below either gate, and on broken/missing/malformed state
#   8. the hook is read-only — mutates neither the watermark, the session store, nor the repo,
#      checked on the FIRE path (not just the pre-gate silent path)
#
# Exits non-zero if any assertion fails.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCAN="$ROOT/.agents/scripts/dream-scan.sh"
HOOK="$ROOT/.claude/hooks/dream-if-stale.sh"
[ -f "$SCAN" ] || { echo "missing $SCAN"; exit 1; }
[ -f "$HOOK" ] || { echo "missing $HOOK"; exit 1; }
command -v python3 >/dev/null || { echo "python3 is required"; exit 1; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
PROJ="$WORK/projects"

pass=0; fail=0
ok()  { echo "  ok:   $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }

# epoch -> ISO-8601 UTC, portable across BSD (date -r) and GNU (date -d @).
epoch_to_iso() { date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null; }

now=$(date -u +%s)
WM_2D=$(epoch_to_iso $(( now - 2*86400 )))     # 2 days ago
WM_3H=$(epoch_to_iso $(( now - 3*3600 )))      # 3 hours ago
WM_FUT=$(epoch_to_iso $(( now + 86400 )))      # 1 day in the future

# A fixture session store: slug dirs with .jsonl files. "new" files keep their current
# mtime (> any past watermark); "old" files are backdated well before any watermark.
sess() { mkdir -p "$PROJ/$1"; printf '%s\n' '{"type":"user","message":{"role":"user","content":"x"}}' > "$PROJ/$1/$2.jsonl"; }
old()  { touch -t 197001020000 "$PROJ/$1/$2.jsonl"; }

# slugA: 3 new + 2 old ; slugB: 1 new
for i in 1 2 3; do sess slugA "new$i"; done
for i in 1 2;   do sess slugA "old$i"; old slugA "old$i"; done
sess slugB "new1"

echo "== 1/2: dream-scan selects only-newer + count matches =="
sel=$(CLAUDE_PROJECTS_DIR="$PROJ" DREAM_SLUGS="slugA" bash "$SCAN" --since "$WM_2D")
n=$(printf '%s\n' "$sel" | sed '/^$/d' | wc -l | tr -d ' ')
[ "$n" = "3" ] && ok "3 new files selected (2 old excluded)" || bad "expected 3 selected, got $n"
printf '%s\n' "$sel" | grep -q 'old1.jsonl' && bad "backdated file wrongly selected" || ok "backdated files excluded"
c=$(CLAUDE_PROJECTS_DIR="$PROJ" DREAM_SLUGS="slugA" bash "$SCAN" --count --since "$WM_2D")
[ "$c" = "3" ] && ok "--count ($c) matches selected paths" || bad "--count=$c != 3"

echo "== 3: all-worktrees globs multiple slugs + de-duplicates =="
# duplicate slugA in the list must not double-count; slugB adds its 1 new file -> 4 total
c=$(CLAUDE_PROJECTS_DIR="$PROJ" DREAM_SLUGS="slugA slugA slugB" bash "$SCAN" --count --since "$WM_2D")
[ "$c" = "4" ] && ok "multi-slug de-dup: 3 + 1 = 4" || bad "expected 4 across deduped slugs, got $c"

echo "== 4: empty / missing store -> empty, exit 0 =="
out=$(CLAUDE_PROJECTS_DIR="$WORK/nope" DREAM_SLUGS="slugA" bash "$SCAN" --since "$WM_2D"); rc=$?
[ -z "$out" ] && [ "$rc" = "0" ] && ok "missing store: empty output, exit 0" || bad "missing store: out='$out' rc=$rc"
c=$(CLAUDE_PROJECTS_DIR="$PROJ" DREAM_SLUGS="slugA" bash "$SCAN" --count --since "$WM_FUT")
[ "$c" = "0" ] && ok "future watermark: count 0" || bad "future watermark count=$c != 0"

echo "== 4b: dream-scan reads the watermark from DREAM_STATE (no --since) =="
printf '%s\n' "$WM_2D" > "$WORK/wm"
c=$(DREAM_STATE="$WORK/wm" CLAUDE_PROJECTS_DIR="$PROJ" DREAM_SLUGS="slugA" bash "$SCAN" --count)
[ "$c" = "3" ] && ok "state-file watermark read: 3 new (no --since)" || bad "state-file read count=$c != 3"
printf '%s\n' "$WM_FUT" > "$WORK/wm"
c=$(DREAM_STATE="$WORK/wm" CLAUDE_PROJECTS_DIR="$PROJ" DREAM_SLUGS="slugA" bash "$SCAN" --count)
[ "$c" = "0" ] && ok "state-file future watermark: 0" || bad "state-file future count=$c != 0"

echo "== 5: --extract digest (Claude + Codex shapes, strips tools, tolerates malformed) =="
EX="$WORK/one.jsonl"
{
  printf '%s\n' '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"HELLO_USER"}]}}'
  printf '%s\n' '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"HELLO_ASSISTANT"},{"type":"tool_use","name":"Bash","input":{"command":"SECRET_TOOL_CALL"}}]}}'
  printf '%s\n' '{"role":"user","content":[{"type":"input_text","text":"CODEX_USER"}]}'
  printf '%s\n' '{"payload":{"role":"assistant","content":[{"type":"output_text","text":"CODEX_ASSISTANT"}]}}'
  printf '%s\n' '{"type":"summary","summary":"a valid non-message record"}'
  printf '%s\n' 'this is not json at all'
} > "$EX"
dg=$(bash "$SCAN" --extract "$EX")
printf '%s\n' "$dg" | grep -q 'HELLO_USER'       && ok "extract keeps Claude user text"          || bad "extract dropped Claude user text"
printf '%s\n' "$dg" | grep -q 'HELLO_ASSISTANT'  && ok "extract keeps Claude assistant text"     || bad "extract dropped Claude assistant text"
printf '%s\n' "$dg" | grep -q 'CODEX_USER'       && ok "extract handles Codex bare {role,content}" || bad "extract dropped Codex bare-shape text"
printf '%s\n' "$dg" | grep -q 'CODEX_ASSISTANT'  && ok "extract handles Codex {payload:{...}}"    || bad "extract dropped Codex payload-shape text"
printf '%s\n' "$dg" | grep -q 'SECRET_TOOL_CALL' && bad "extract leaked tool_use input"           || ok "extract strips tool_use noise"
# Only the syntactically-invalid line is a parse error; the valid {type:summary} record is skipped, not counted.
printf '%s\n' "$dg" | tail -n1 | grep -qE '"parse_errors":[[:space:]]*1' && ok "only malformed line counts (valid non-message skipped)" || bad "extract _meta parse_errors wrong (expected exactly 1)"

echo "== 6: nudge fires only when >=24h AND >=5 sessions =="
# 6 new sessions in slugC, watermark 2 days ago -> fire
for i in 1 2 3 4 5 6; do sess slugC "new$i"; done
printf '%s\n' "$WM_2D" > "$WORK/wm"
fire() { DREAM_STATE="$WORK/wm" CLAUDE_PROJECTS_DIR="$PROJ" DREAM_SLUGS="slugC" bash "$HOOK"; }
out=$(fire)
printf '%s\n' "$out" | grep -q 'vault-dream' && ok "fires: 2d elapsed + 6 sessions" || bad "expected nudge, got '$out'"
# The nudge must be valid SessionStart additionalContext JSON (the injection channel).
printf '%s' "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["hookSpecificOutput"]["hookEventName"]=="SessionStart" and "/vault-dream" in d["hookSpecificOutput"]["additionalContext"]' 2>/dev/null \
  && ok "nudge is valid SessionStart additionalContext JSON" || bad "nudge is not valid additionalContext JSON: '$out'"

echo "== 7: silent below either gate + on broken state =="
# volume gate: only 4 sessions
rm -rf "$PROJ/slugC"; for i in 1 2 3 4; do sess slugC "new$i"; done
out=$(DREAM_STATE="$WORK/wm" CLAUDE_PROJECTS_DIR="$PROJ" DREAM_SLUGS="slugC" bash "$HOOK")
[ -z "$out" ] && ok "silent: only 4 sessions (< 5)" || bad "should be silent under volume gate: '$out'"
# time gate: 6 sessions but watermark 3h ago
for i in 5 6; do sess slugC "new$i"; done
printf '%s\n' "$WM_3H" > "$WORK/wm"
out=$(DREAM_STATE="$WORK/wm" CLAUDE_PROJECTS_DIR="$PROJ" DREAM_SLUGS="slugC" bash "$HOOK")
[ -z "$out" ] && ok "silent: 6 sessions but only 3h elapsed" || bad "should be silent under time gate: '$out'"
# missing watermark file
out=$(DREAM_STATE="$WORK/gone" CLAUDE_PROJECTS_DIR="$PROJ" DREAM_SLUGS="slugC" bash "$HOOK"); rc=$?
[ -z "$out" ] && [ "$rc" = "0" ] && ok "silent + exit 0: missing watermark" || bad "missing watermark: out='$out' rc=$rc"
# malformed watermark
printf 'not-a-timestamp\n' > "$WORK/wm"
out=$(DREAM_STATE="$WORK/wm" CLAUDE_PROJECTS_DIR="$PROJ" DREAM_SLUGS="slugC" bash "$HOOK"); rc=$?
[ -z "$out" ] && [ "$rc" = "0" ] && ok "silent + exit 0: malformed watermark" || bad "malformed watermark: out='$out' rc=$rc"

echo "== 8: hook is read-only — mutates nothing, even on the FIRE path =="
# Drive the hook entirely off fixtures (never the real ~/. or committed watermark), and force
# the FIRING state (2d elapsed + 6 sessions) so the read-only guarantee is checked on the path
# that actually prints — not just the pre-gate silent path.
rm -rf "$PROJ/slugC"; for i in 1 2 3 4 5 6; do sess slugC "new$i"; done
printf '%s\n' "$WM_2D" > "$WORK/wm"
wm_before=$(cat "$WORK/wm"); proj_before=$(ls -lR "$PROJ" 2>/dev/null)
out=$(DREAM_STATE="$WORK/wm" CLAUDE_PROJECTS_DIR="$PROJ" DREAM_SLUGS="slugC" bash "$HOOK")
printf '%s\n' "$out" | grep -q 'vault-dream' && ok "case 8 exercises the fire path" || bad "case 8 setup: fire path not active"
[ "$(cat "$WORK/wm")" = "$wm_before" ] && ok "hook did not mutate the watermark (fire path)" || bad "hook mutated the watermark"
[ "$(ls -lR "$PROJ" 2>/dev/null)" = "$proj_before" ] && ok "hook did not mutate the session store" || bad "hook mutated the session store"
if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  before=$(git -C "$ROOT" status --porcelain)
  DREAM_STATE="$WORK/wm" CLAUDE_PROJECTS_DIR="$PROJ" DREAM_SLUGS="slugC" bash "$HOOK" >/dev/null 2>&1
  after=$(git -C "$ROOT" status --porcelain)
  [ "$before" = "$after" ] && ok "hook left the repo working tree unchanged" || bad "hook mutated tracked files"
else
  ok "not a git repo — skipping tracked-file check"
fi

echo
echo "dream-smoke: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
