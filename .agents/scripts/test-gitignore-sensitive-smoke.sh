#!/usr/bin/env bash
# ── ENGINE FILE (base-owned) — AGENT NOTICE ─────────────────────────────────
# In a DERIVED VAULT (git origin is not the obsidian-base repo): if this script
# is buggy, do NOT fix it here and do NOT open a PR against the base repo —
# FILE A GITHUB ISSUE against the upstream base (.agents/.base-url if present,
# else Object-3/obsidian-base) with the error + proposed fix in the issue body.
# Local patches are overwritten by the next update-base and help no other clone.
# See AGENTS.md → "Engine bugs & improvements found in a derived vault".
# ─────────────────────────────────────────────────────────────────────────────
# Smoke test for the Sensitive-plane block of the base .gitignore (issue #60).
#
# Self-contained and offline: builds a scratch git repo in a temp dir, copies this
# repo's .gitignore in, and asserts `git check-ignore` / staging behavior for every
# shape `_sensitive` (and legacy `_local`) can take. Run from anywhere:
#
#   .agents/scripts/test-gitignore-sensitive-smoke.sh
#
# Covers the guarantee the block exists for — the confidential plane never reaches
# git — across the matrix the rules' ORDER makes load-bearing (last-match-wins:
# reordering `/_sensitive`, `!/_sensitive/`, `_sensitive/*` changes behavior):
#   1. a bare `_sensitive` SYMLINK (setup-sensitive-plane `link`) is ignored —
#      `git add -A` must not stage the confidential backing path (the #60 leak)
#   2. a real `_sensitive/` DIRECTORY keeps template semantics: notes inside are
#      ignored, `.gitkeep`/`README.md` stay addable
#   3. the legacy `_local` twin gets the same symlink + directory treatment
#
# Exits non-zero if any assertion fails.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GI="$ROOT/.gitignore"
[ -f "$GI" ] || { echo "missing: $GI"; exit 1; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

pass=0; fail=0
ok()  { echo "  ok:   $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }

REPO="$WORK/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q
cp "$GI" "$REPO/.gitignore"

check_plane() { # $1 = plane name (_sensitive | _local)
  local plane="$1"

  echo "== $plane: bare symlink (the #60 leak shape) =="
  ln -s "$WORK/confidential-backing-dir" "$REPO/$plane"
  if git -C "$REPO" check-ignore -q "$plane"; then
    ok "$plane symlink is ignored"
  else
    bad "$plane symlink is NOT ignored — backing path can be committed"
  fi
  git -C "$REPO" add -A
  if git -C "$REPO" status --porcelain | grep -q "$plane"; then
    bad "$plane symlink got staged by git add -A"
  else
    ok "$plane symlink not staged by git add -A"
  fi
  git -C "$REPO" reset -q
  rm "$REPO/$plane"

  echo "== $plane: real directory (template semantics) =="
  mkdir "$REPO/$plane"
  : > "$REPO/$plane/.gitkeep"
  : > "$REPO/$plane/README.md"
  : > "$REPO/$plane/secret-note.md"
  if git -C "$REPO" check-ignore -q "$plane/secret-note.md"; then
    ok "$plane/secret-note.md is ignored"
  else
    bad "$plane/secret-note.md is NOT ignored"
  fi
  if git -C "$REPO" check-ignore -q "$plane/.gitkeep"; then
    bad "$plane/.gitkeep is ignored (placeholder re-include broken)"
  else
    ok "$plane/.gitkeep stays addable"
  fi
  if git -C "$REPO" check-ignore -q "$plane/README.md"; then
    bad "$plane/README.md is ignored (placeholder re-include broken)"
  else
    ok "$plane/README.md stays addable"
  fi
  git -C "$REPO" add -A
  if git -C "$REPO" status --porcelain | grep -q "$plane/secret-note.md"; then
    bad "$plane/secret-note.md got staged by git add -A"
  else
    ok "$plane/secret-note.md not staged by git add -A"
  fi
  git -C "$REPO" reset -q
  rm -rf "${REPO:?}/$plane"
}

check_plane "_sensitive"
check_plane "_local"

echo
echo "smoke: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
