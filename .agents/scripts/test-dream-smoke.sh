#!/usr/bin/env bash
# ── ENGINE FILE (base-owned) — AGENT NOTICE ─────────────────────────────────
# In a DERIVED VAULT (git origin is not the obsidian-base repo): if this script
# is buggy, do NOT fix it here and do NOT open a PR against the base repo —
# FILE A GITHUB ISSUE against the upstream base (.agents/.base-url if present,
# else Object-3/obsidian-base) with the error + proposed fix in the issue body.
# Local patches are overwritten by the next update-base and help no other clone.
# See AGENTS.md → "Engine bugs & improvements found in a derived vault".
# ─────────────────────────────────────────────────────────────────────────────
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
#   9. slug resolution: the exact-root slug dir wins when it has transcripts (no fallback)
#  10. ancestor fallback (issue #54): missing/empty exact slug dir falls back to parent
#      slugs, content-filtered to transcripts referencing THIS vault's path, bounded at $HOME
#  11. dream_project_slug override in vault-profile.md pins the slug (no fallback)
#  12. --doctor distinguishes "0 new sessions" from "session dir missing" (exit 3),
#      while --count on the same broken store stays 0 / exit 0 (hook silence preserved)
#  13. a stale pre-watermark transcript in the exact dir does not suppress the fallback
#      (and --doctor reports the fallback rather than a false "ok")
#  14. the content filter requires a path boundary — …/vault never claims …/vault-fork
#  15. references to the physical (symlink-resolved) root path also match
#  16. dream_project_slug pointing at a missing dir stays safe (--count 0, --doctor
#      BROKEN exit 3); a vault outside $HOME is bounded by the pure 3-level cap
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

echo "== 9: slug resolution — exact-root slug dir wins when it has transcripts =="
# A fake multi-vault layout in a fixture HOME: two sibling vaults under one parent dir,
# driven through the DREAM_ROOT / DREAM_PROFILE / HOME overrides (no DREAM_SLUGS, so the
# real slug-resolution path runs).
FHOME="$WORK/home"; VAULT="$FHOME/user/vault-alpha"; SIB="$FHOME/user/vault-beta"
mkdir -p "$VAULT" "$SIB"
PROJ2="$WORK/projects2"; mkdir -p "$PROJ2"
PROF2="$WORK/profile.md"
printf -- '---\ndream_session_scope: "this-checkout"\n---\n' > "$PROF2"
slugof() { printf '%s' "$1" | sed 's/[^A-Za-z0-9]/-/g'; }
S_VAULT=$(slugof "$VAULT"); S_PARENT=$(slugof "$FHOME/user"); S_HOME=$(slugof "$FHOME")
vsess() { # $1 slug dir, $2 name, $3 path referenced in the transcript content
  mkdir -p "$PROJ2/$1"
  printf '{"type":"user","message":{"role":"user","content":"working in %s today"}}\n' "$3" > "$PROJ2/$1/$2.jsonl"
}
scan2() { HOME="$FHOME" DREAM_ROOT="$VAULT" DREAM_PROFILE="$PROF2" CLAUDE_PROJECTS_DIR="$PROJ2" bash "$SCAN" "$@"; }
vsess "$S_VAULT"  a  "$VAULT"
vsess "$S_VAULT"  b  "$VAULT"
vsess "$S_PARENT" p1 "$VAULT"      # parent-slug transcript — ignored while the exact dir has files
c=$(scan2 --count --since "$WM_2D")
[ "$c" = "2" ] && ok "exact slug dir wins: 2 (parent-slug files not counted)" || bad "exact-slug count=$c != 2"

echo "== 10: ancestor fallback with content filtering (issue #54 layout) =="
# Empty (then missing) exact slug dir -> fallback to parent + grandparent slugs, counting
# only transcripts that reference THIS vault's path.
rm -rf "$PROJ2/$S_VAULT"; mkdir -p "$PROJ2/$S_VAULT"      # exists but EMPTY
vsess "$S_PARENT" p2 "$SIB"        # sibling vault's session — must be filtered OUT
vsess "$S_HOME"   h1 "$VAULT"      # grandparent (== fixture HOME) — within the bound
vsess "$(slugof "$WORK")" x1 "$VAULT"   # ABOVE the fixture HOME — must never be scanned
c=$(scan2 --count --since "$WM_2D")
[ "$c" = "2" ] && ok "fallback (empty exact dir): content-filtered count 2 (p1 + h1)" || bad "fallback-empty count=$c != 2"
printf '%s\n' "$(scan2 --since "$WM_2D")" | grep -q 'p2.jsonl' && bad "sibling vault's transcript miscounted" || ok "sibling vault's transcript filtered out"
rm -rf "$PROJ2/$S_VAULT"                                   # now MISSING entirely
c=$(scan2 --count --since "$WM_2D")
[ "$c" = "2" ] && ok "fallback (missing exact dir): count 2" || bad "fallback-missing count=$c != 2"
printf '%s\n' "$(scan2 --since "$WM_2D")" | grep -q 'x1.jsonl' && bad "fallback climbed past \$HOME" || ok "fallback bounded at \$HOME"

echo "== 11: dream_project_slug override pins the slug (no fallback) =="
printf -- '---\ndream_session_scope: "this-checkout"\ndream_project_slug: "customslug"\n---\n' > "$PROF2"
vsess customslug o1 "$VAULT"; vsess customslug o2 "$SIB"; vsess customslug o3 "unrelated"
c=$(scan2 --count --since "$WM_2D")
[ "$c" = "3" ] && ok "override: all 3 transcripts in the pinned slug counted (no content filter)" || bad "override count=$c != 3"
printf '%s\n' "$(scan2 --since "$WM_2D")" | grep -q 'p1.jsonl' && bad "override still ran the fallback" || ok "override suppresses the ancestor fallback"

echo "== 12: --doctor distinguishes 0-sessions from a missing session dir =="
printf -- '---\ndream_session_scope: "this-checkout"\n---\n' > "$PROF2"
# healthy: exact slug dir with a transcript -> exit 0
vsess "$S_VAULT" a "$VAULT"
out=$(scan2 --doctor --since "$WM_2D"); rc=$?
[ "$rc" = "0" ] && printf '%s' "$out" | grep -q 'verdict: ok' && ok "doctor: healthy exact layout -> exit 0" || bad "doctor healthy: rc=$rc out='$out'"
# fallback-reachable: exact dir gone, parent transcripts reference the vault -> exit 0, names fallback
rm -rf "$PROJ2/$S_VAULT"
out=$(scan2 --doctor --since "$WM_2D"); rc=$?
[ "$rc" = "0" ] && printf '%s' "$out" | grep -q 'fallback' && ok "doctor: fallback layout -> exit 0, mentions fallback" || bad "doctor fallback: rc=$rc out='$out'"
# broken: no slug dir anywhere and nothing references the vault -> exit 3, says BROKEN
PROJ3="$WORK/projects3"; mkdir -p "$PROJ3"
out=$(HOME="$FHOME" DREAM_ROOT="$VAULT" DREAM_PROFILE="$PROF2" CLAUDE_PROJECTS_DIR="$PROJ3" bash "$SCAN" --doctor --since "$WM_2D"); rc=$?
[ "$rc" = "3" ] && printf '%s' "$out" | grep -q 'BROKEN' && ok "doctor: missing session dir -> exit 3 + BROKEN verdict" || bad "doctor broken: rc=$rc out='$out'"
# ...while non-doctor mode on the same broken store stays 0 / exit 0 (hook silence preserved)
c=$(HOME="$FHOME" DREAM_ROOT="$VAULT" DREAM_PROFILE="$PROF2" CLAUDE_PROJECTS_DIR="$PROJ3" bash "$SCAN" --count); rc=$?
[ "$c" = "0" ] && [ "$rc" = "0" ] && ok "--count on broken store: 0, exit 0 (hook stays silent)" || bad "broken-store --count: c=$c rc=$rc"

echo "== 13: stale pre-watermark transcript in exact dir does NOT suppress fallback =="
# Exact slug dir exists but holds ONLY a pre-watermark transcript; parent (p1) + fixture
# HOME (h1) still hold new transcripts referencing the vault -> fallback must engage.
rm -rf "$PROJ2/$S_VAULT"
vsess "$S_VAULT" stale "$VAULT"; touch -t 197001020000 "$PROJ2/$S_VAULT/stale.jsonl"
c=$(scan2 --count --since "$WM_2D")
[ "$c" = "2" ] && ok "stale-only exact dir: fallback engaged, count 2" || bad "stale-exact count=$c != 2"
out=$(scan2 --doctor --since "$WM_2D"); rc=$?
[ "$rc" = "0" ] && printf '%s' "$out" | grep -q 'fallback' && ok "doctor reports fallback (not a false plain ok) on stale exact dir" || bad "doctor stale-exact: rc=$rc out='$out'"

echo "== 14: path-boundary filter — …/vault never claims …/vault-fork sessions =="
PVAULT="$FHOME/user/vault"; PFORK="$FHOME/user/vault-fork"; mkdir -p "$PVAULT" "$PFORK"
PROJ4="$WORK/projects4"; mkdir -p "$PROJ4"
xsess() { # $1 store, $2 slug dir, $3 name, $4 path referenced in content
  mkdir -p "$1/$2"
  printf '{"type":"user","message":{"role":"user","content":"working in %s today"}}\n' "$4" > "$1/$2/$3.jsonl"
}
xsess "$PROJ4" "$S_PARENT" fork1 "$PFORK"              # prefix sibling — must NOT count
xsess "$PROJ4" "$S_PARENT" mine1 "$PVAULT"             # exact path + boundary (space)
xsess "$PROJ4" "$S_PARENT" mine2 "$PVAULT/notes/x.md"  # path continues with '/' — counts
c=$(HOME="$FHOME" DREAM_ROOT="$PVAULT" DREAM_PROFILE="$PROF2" CLAUDE_PROJECTS_DIR="$PROJ4" bash "$SCAN" --count --since "$WM_2D")
[ "$c" = "2" ] && ok "boundary filter: 2 counted, vault-fork transcript excluded" || bad "prefix-sibling count=$c != 2"

echo "== 15: physical (symlink-resolved) root path references also match =="
REAL="$WORK/realvault"; mkdir -p "$REAL"
REAL_P=$(cd "$REAL" && pwd -P)                          # fully physical (mktemp dirs can sit behind /var -> /private/var on macOS)
ln -s "$REAL" "$FHOME/user/vlink"
PROJ5="$WORK/projects5"; mkdir -p "$PROJ5"
xsess "$PROJ5" "$S_PARENT" phys1 "$REAL_P"             # transcript records the PHYSICAL path
c=$(HOME="$FHOME" DREAM_ROOT="$FHOME/user/vlink" DREAM_PROFILE="$PROF2" CLAUDE_PROJECTS_DIR="$PROJ5" bash "$SCAN" --count --since "$WM_2D")
[ "$c" = "1" ] && ok "symlinked root: physical-path reference matched" || bad "symlink count=$c != 1"

echo "== 16: override to a missing dir + vault outside \$HOME (pure 3-level cap) =="
PROFG="$WORK/profile-ghost.md"
printf -- '---\ndream_session_scope: "this-checkout"\ndream_project_slug: "ghostslug"\n---\n' > "$PROFG"
c=$(HOME="$FHOME" DREAM_ROOT="$VAULT" DREAM_PROFILE="$PROFG" CLAUDE_PROJECTS_DIR="$PROJ2" bash "$SCAN" --count --since "$WM_2D"); rc=$?
[ "$c" = "0" ] && [ "$rc" = "0" ] && ok "override -> missing dir: count 0, exit 0 (no crash, no fallback)" || bad "ghost override: c=$c rc=$rc"
out=$(HOME="$FHOME" DREAM_ROOT="$VAULT" DREAM_PROFILE="$PROFG" CLAUDE_PROJECTS_DIR="$PROJ2" bash "$SCAN" --doctor --since "$WM_2D"); rc=$?
[ "$rc" = "3" ] && printf '%s' "$out" | grep -q 'BROKEN' && ok "override -> missing dir: doctor BROKEN, exit 3" || bad "ghost override doctor: rc=$rc out='$out'"
# vault outside the fixture HOME: the walk must stop at the 3-level cap, never at $HOME
VOUT="$WORK/deep/a/b/c/vault2"; mkdir -p "$VOUT"
PROJ6="$WORK/projects6"; mkdir -p "$PROJ6"
xsess "$PROJ6" "$(slugof "$WORK/deep/a/b/c")" in1  "$VOUT"   # level 1 — counted
xsess "$PROJ6" "$(slugof "$WORK/deep")"       out1 "$VOUT"   # level 4 — beyond the cap
c=$(HOME="$FHOME" DREAM_ROOT="$VOUT" DREAM_PROFILE="$PROF2" CLAUDE_PROJECTS_DIR="$PROJ6" bash "$SCAN" --count --since "$WM_2D")
[ "$c" = "1" ] && ok "outside-\$HOME vault: 3-level cap holds (level-4 dir not scanned)" || bad "outside-home count=$c != 1"

echo
echo "dream-smoke: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
