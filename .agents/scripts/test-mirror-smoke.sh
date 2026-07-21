#!/usr/bin/env bash
# ── ENGINE FILE (base-owned) — AGENT NOTICE ─────────────────────────────────
# In a DERIVED VAULT (git origin is not the obsidian-base repo): if this script
# is buggy, do NOT fix it here and do NOT open a PR against the base repo —
# FILE A GITHUB ISSUE against the upstream base (.agents/.base-url if present,
# else Object-3/obsidian-base) with the error + proposed fix in the issue body.
# Local patches are overwritten by the next update-base and help no other clone.
# See AGENTS.md → "Engine bugs & improvements found in a derived vault".
# ─────────────────────────────────────────────────────────────────────────────
# Smoke test for the user-scope skill mirror in .agents/scripts/sync-skills.sh.
#
# Self-contained and offline: every write is redirected to a temp dir via the
# CLAUDE_USER_SKILLS / CODEX_USER_SKILLS / MIRROR_MANIFEST overrides the script
# honors, so it NEVER touches your real ~/. Run from anywhere in the repo:
#
#   .agents/scripts/test-mirror-smoke.sh
#
# Covers the behavioral guarantees that have no other automated check:
#   1. non-destructive — a same-named skill you installed is never overwritten
#   2. install — a locked skill lands in BOTH targets and is recorded owned
#   3. manifest schema round-trips
#   4. owned[] is retained across refresh (the freeze-bug guard)
#   5. --status exit codes (0 up-to-date / 1 stale / 2 not-installed)
#   6. --mirror-only works with no network
#   7. no staging artifacts leak into the scanned skills root (stages live in the parent)
#
# Exits non-zero if any assertion fails.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SYNC="$ROOT/.agents/scripts/sync-skills.sh"
LOCK="$ROOT/.agents/skill-sources.lock.json"
CANON="$ROOT/.agents/skills"
command -v jq >/dev/null || { echo "jq is required"; exit 1; }
[ -f "$LOCK" ] || { echo "no lock at $LOCK — run sync-skills.sh once first"; exit 1; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
export CLAUDE_USER_SKILLS="$WORK/claude"
export CODEX_USER_SKILLS="$WORK/codex"
export MIRROR_MANIFEST="$WORK/skill-mirror.json"

pass=0; fail=0
ok()  { echo "  ok:   $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }
owned_has() { jq -e --arg n "$1" '.owned | index($n) != null' "$MIRROR_MANIFEST" >/dev/null 2>&1; }

# Pick two distinct locked skills that actually exist on disk.
NAMES=()
while IFS= read -r n; do [ -n "$n" ] && NAMES+=("$n"); done < <(jq -r '.skills[]?' "$LOCK")
OWN_SKILL=""; USER_SKILL=""
for n in "${NAMES[@]}"; do [ -d "$CANON/$n" ] && { OWN_SKILL="$n"; break; }; done
for n in "${NAMES[@]}"; do [ "$n" != "$OWN_SKILL" ] && [ -d "$CANON/$n" ] && { USER_SKILL="$n"; break; }; done
[ -n "$OWN_SKILL" ] && [ -n "$USER_SKILL" ] || { echo "need >=2 on-disk locked skills to test"; exit 1; }

echo "== 1: non-destructive (a skill you installed is never overwritten) =="
mkdir -p "$CLAUDE_USER_SKILLS/$USER_SKILL"
printf 'MINE\n' > "$CLAUDE_USER_SKILLS/$USER_SKILL/SKILL.md"
bash "$SYNC" --mirror-only >/dev/null 2>&1
[ "$(cat "$CLAUDE_USER_SKILLS/$USER_SKILL/SKILL.md" 2>/dev/null)" = "MINE" ] \
  && ok "your '$USER_SKILL' left untouched" || bad "your '$USER_SKILL' was overwritten"
owned_has "$USER_SKILL" && bad "'$USER_SKILL' wrongly claimed as owned" \
  || ok "'$USER_SKILL' not claimed as owned"

echo "== 2: install (locked skill lands in both targets + recorded owned) =="
[ -f "$CLAUDE_USER_SKILLS/$OWN_SKILL/SKILL.md" ] && ok "'$OWN_SKILL' in ~/.claude/skills" || bad "'$OWN_SKILL' missing from ~/.claude/skills"
[ -f "$CODEX_USER_SKILLS/$OWN_SKILL/SKILL.md" ]  && ok "'$OWN_SKILL' in ~/.agents/skills" || bad "'$OWN_SKILL' missing from ~/.agents/skills"
owned_has "$OWN_SKILL" && ok "'$OWN_SKILL' recorded owned" || bad "'$OWN_SKILL' not recorded owned"

echo "== 3: manifest schema round-trips =="
jq -e 'has("owned") and has("lock_hash") and has("vault_path") and has("written")' "$MIRROR_MANIFEST" >/dev/null \
  && ok "manifest has {owned,lock_hash,vault_path,written}" || bad "manifest schema wrong"

echo "== 4: owned[] retained across refresh (freeze-bug guard) =="
KEEP="zz-smoke-kept-skill"
mkdir -p "$CLAUDE_USER_SKILLS/$KEEP"; printf 'k\n' > "$CLAUDE_USER_SKILLS/$KEEP/SKILL.md"
jq --arg k "$KEEP" '.owned += [$k]' "$MIRROR_MANIFEST" > "$MIRROR_MANIFEST.x" && mv "$MIRROR_MANIFEST.x" "$MIRROR_MANIFEST"
bash "$SYNC" --mirror-only >/dev/null 2>&1
owned_has "$KEEP" && ok "previously-owned on-disk skill retained" || bad "owned skill dropped on refresh (freeze bug)"

echo "== 5: --status exit codes =="
bash "$SYNC" --status >/dev/null 2>&1 && ok "status 0 when up to date" || bad "status not 0 when up to date"
jq '.lock_hash = "deadbeef"' "$MIRROR_MANIFEST" > "$MIRROR_MANIFEST.x" && mv "$MIRROR_MANIFEST.x" "$MIRROR_MANIFEST"
bash "$SYNC" --status >/dev/null 2>&1; [ "$?" -eq 1 ] && ok "status 1 on drift" || bad "status not 1 on drift"
rm -f "$MIRROR_MANIFEST"
bash "$SYNC" --status >/dev/null 2>&1; [ "$?" -eq 2 ] && ok "status 2 when not installed" || bad "status not 2 when not installed"

echo "== 6: --mirror-only is offline (curl forced to fail) =="
mkdir -p "$WORK/bin"; printf '#!/bin/sh\nexit 1\n' > "$WORK/bin/curl"; chmod +x "$WORK/bin/curl"
rm -rf "$CLAUDE_USER_SKILLS" "$CODEX_USER_SKILLS"
PATH="$WORK/bin:$PATH" bash "$SYNC" --mirror-only >/dev/null 2>&1
[ -f "$CLAUDE_USER_SKILLS/$OWN_SKILL/SKILL.md" ] && ok "mirrors with no network" || bad "mirror failed offline"

echo "== 7: no staging artifacts leak into the scanned skills root =="
# A host's skill scanner reads the skills ROOT; staging there would momentarily list a
# half-written '.tmp' dir as a skill. Stages must live in the parent and be swept clean.
bash "$SYNC" --mirror-only >/dev/null 2>&1
root_junk=0
for d in "$CLAUDE_USER_SKILLS" "$CODEX_USER_SKILLS"; do
  n=$(find "$d" -maxdepth 1 \( -name '.*.tmp.*' -o -name '.skill-mirror-stage.*' \) 2>/dev/null | wc -l | tr -d ' ')
  [ "$n" = "0" ] || root_junk=1
done
[ "$root_junk" -eq 0 ] && ok "no temp/stage dirs in skills root after run" || bad "staging leaked into skills root"
par_junk=$(find "$WORK" -maxdepth 1 -name '.skill-mirror-stage.*' 2>/dev/null | wc -l | tr -d ' ')
[ "$par_junk" = "0" ] && ok "parent stages swept clean" || bad "stage orphans left in parent dir"

echo
echo "smoke: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
