#!/usr/bin/env bash
# ── ENGINE FILE (base-owned) — AGENT NOTICE ─────────────────────────────────
# In a DERIVED VAULT (git origin is not the obsidian-base repo): if this script
# is buggy, do NOT fix it here and do NOT open a PR against the base repo —
# FILE A GITHUB ISSUE against the upstream base (.agents/.base-url if present,
# else Object-3/obsidian-base) with the error + proposed fix in the issue body.
# Local patches are overwritten by the next update-base and help no other clone.
# See AGENTS.md → "Engine bugs & improvements found in a derived vault".
# ─────────────────────────────────────────────────────────────────────────────
# Smoke test for .agents/scripts/vault-git-doctor.sh (issues #37 + #43).
#
# Self-contained and offline: builds throwaway git repos in a temp dir with the
# script + setup/lib.sh copied in (mirroring where they live in a real vault),
# and never fetches any remote — base-URL remotes exist as config only. Run
# from anywhere:
#
#   .agents/scripts/test-git-doctor-smoke.sh
#
# Covers:
#   1. clean vault → exit 0, both checks report ✓
#   2. branch tracking a base-URL remote (public default) → exit 3; --fix-tracking
#      detaches the branch, removes the remote, and re-report is clean
#   3. scp-style base URL on 'origin' is recognized (URL normalization) and the
#      fix prints the reconnect-your-own-repo guidance
#   4. a fork pinned in .agents/.base-url is recognized as "the base" too
#   5. an unpersonalized TEMPLATE checkout ({{VAULT_NAME}} still in
#      vault-profile.md — the base repo itself / a contributor checkout) is
#      never flagged and never fixed: 'origin' = base is legitimate there
#   6. 0-byte stub at a path not on main → exit 3 and listed; a 0-byte file that
#      IS on main is NOT flagged; _sensitive/ and raw/ are never scanned;
#      --fix-stubs deletes only the stub
#
# Exits non-zero if any assertion fails.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DOCTOR_SRC="$ROOT/.agents/scripts/vault-git-doctor.sh"
LIB_SRC="$ROOT/setup/lib.sh"
[ -f "$DOCTOR_SRC" ] || { echo "missing: $DOCTOR_SRC"; exit 1; }
[ -f "$LIB_SRC" ]    || { echo "missing: $LIB_SRC"; exit 1; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
unset BASE_REPO_URL BASE_REPO   # deterministic base resolution inside the temp vaults

pass=0; fail=0
ok()  { echo "  ok:   $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }

G() { git -c user.name=t -c user.email=t@localhost "$@"; }   # commit identity for temp repos

# Build a minimal vault repo at $1 with the doctor + lib in place and one commit on main.
mk_vault() {
  local d="$1"
  mkdir -p "$d/.agents/scripts" "$d/setup"
  cp "$DOCTOR_SRC" "$d/.agents/scripts/vault-git-doctor.sh"
  cp "$LIB_SRC" "$d/setup/lib.sh"
  chmod +x "$d/.agents/scripts/vault-git-doctor.sh"
  ( cd "$d"
    git init -q -b main 2>/dev/null || { git init -q && git symbolic-ref HEAD refs/heads/main; }
    echo "# note" > real-note.md
    G add -A && G commit -q -m init )
}

doctor() { ( cd "$1" && shift && ./.agents/scripts/vault-git-doctor.sh "$@" ); }

# ---- 1. clean vault --------------------------------------------------------
V1="$WORK/v1"; mk_vault "$V1"
out=$(doctor "$V1"); rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '✓ tracking' && printf '%s' "$out" | grep -q '✓ stubs'; then
  ok "clean vault reports ✓✓ (exit 0)"
else
  bad "clean vault (exit $rc): $out"
fi

# ---- 2. branch tracking the public base ------------------------------------
V2="$WORK/v2"; mk_vault "$V2"
( cd "$V2"
  git remote add base https://github.com/Object-3/obsidian-base.git
  git config branch.main.remote base
  git config branch.main.merge refs/heads/main )
out=$(doctor "$V2"); rc=$?
if [ "$rc" -eq 3 ] && printf '%s' "$out" | grep -q "✗ tracking: branch 'main' tracks 'base'"; then
  ok "base-tracking branch flagged (exit 3)"
else
  bad "base-tracking not flagged (exit $rc): $out"
fi
out=$(doctor "$V2" --fix-tracking); rc=$?
if [ "$rc" -eq 0 ] \
   && ! ( cd "$V2" && git config --get branch.main.remote ) >/dev/null 2>&1 \
   && ! ( cd "$V2" && git remote get-url base ) >/dev/null 2>&1; then
  ok "--fix-tracking detached the branch and removed the base remote"
else
  bad "--fix-tracking left tracking/remote behind (exit $rc): $out"
fi
out=$(doctor "$V2"); rc=$?
if [ "$rc" -eq 0 ]; then ok "re-report after fix is clean (exit 0)"
else bad "still drifted after fix (exit $rc): $out"; fi

# ---- 3. scp-style base URL on 'origin' (normalization + guidance) ----------
V3="$WORK/v3"; mk_vault "$V3"
( cd "$V3" && git remote add origin git@github.com:Object-3/obsidian-base.git )
out=$(doctor "$V3"); rc=$?
if [ "$rc" -eq 3 ] && printf '%s' "$out" | grep -q "✗ remote: standing remote 'origin'"; then
  ok "scp-style base URL on origin flagged (exit 3)"
else
  bad "scp-style base URL not flagged (exit $rc): $out"
fi
out=$(doctor "$V3" --fix-tracking); rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q "connect-github.sh" \
   && ! ( cd "$V3" && git remote get-url origin ) >/dev/null 2>&1; then
  ok "--fix-tracking removed base 'origin' and pointed at connect-github.sh"
else
  bad "base 'origin' fix wrong (exit $rc): $out"
fi

# ---- 4. fork pinned in .agents/.base-url is recognized as the base ---------
V4="$WORK/v4"; mk_vault "$V4"
( cd "$V4"
  echo "https://example.com/me/my-base-fork.git" > .agents/.base-url
  git remote add base https://example.com/me/my-base-fork.git )
out=$(doctor "$V4"); rc=$?
if [ "$rc" -eq 3 ] && printf '%s' "$out" | grep -q "✗ remote: standing remote 'base'"; then
  ok "pinned fork base remote flagged (exit 3)"
else
  bad "pinned fork base remote not flagged (exit $rc): $out"
fi

# ---- 5. template checkout (the base repo itself) is left alone -------------
V6="$WORK/v6"; mk_vault "$V6"
( cd "$V6"
  mkdir -p .agents
  printf 'vault_name: "{{VAULT_NAME}}"\n' > .agents/vault-profile.md
  git remote add origin https://github.com/Object-3/obsidian-base.git
  git config branch.main.remote origin
  git config branch.main.merge refs/heads/main )
out=$(doctor "$V6"); rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'TEMPLATE checkout'; then
  ok "unpersonalized template checkout not flagged as drift (exit 0)"
else
  bad "template checkout handling wrong (exit $rc): $out"
fi
out=$(doctor "$V6" --fix-tracking); rc=$?
if [ "$rc" -eq 0 ] && ( cd "$V6" && git remote get-url origin ) >/dev/null 2>&1 \
   && [ "$(cd "$V6" && git config --get branch.main.remote)" = "origin" ]; then
  ok "--fix-tracking skips a template checkout (origin + tracking intact)"
else
  bad "--fix-tracking touched a template checkout (exit $rc): $out"
fi

# ---- 6. 0-byte stub scan ----------------------------------------------------
V5="$WORK/v5"; mk_vault "$V5"
( cd "$V5"
  : > placeholder.md            # 0-byte but ON main → must NOT be flagged
  G add placeholder.md && G commit -q -m placeholder
  : > "old-name.md"             # 0-byte, NOT on main → the race signature
  mkdir -p _sensitive raw
  : > _sensitive/secret-stub.md # never scanned
  : > raw/raw-stub.md )         # never scanned
out=$(doctor "$V5"); rc=$?
if [ "$rc" -eq 3 ] && printf '%s' "$out" | grep -q 'old-name.md' \
   && ! printf '%s' "$out" | grep -q 'placeholder.md' \
   && ! printf '%s' "$out" | grep -q 'secret-stub' \
   && ! printf '%s' "$out" | grep -q 'raw-stub'; then
  ok "stub flagged; on-main empty file, _sensitive/ and raw/ ignored (exit 3)"
else
  bad "stub scan wrong (exit $rc): $out"
fi
out=$(doctor "$V5" --fix-stubs); rc=$?
if [ "$rc" -eq 0 ] && [ ! -f "$V5/old-name.md" ] \
   && [ -f "$V5/_sensitive/secret-stub.md" ] && [ -f "$V5/raw/raw-stub.md" ] \
   && [ -f "$V5/placeholder.md" ]; then
  ok "--fix-stubs removed only the stub"
else
  bad "--fix-stubs deleted the wrong things (exit $rc): $out"
fi
out=$(doctor "$V5"); rc=$?
if [ "$rc" -eq 0 ]; then ok "stub re-report is clean (exit 0)"
else bad "still drifted after stub fix (exit $rc): $out"; fi

echo
echo "vault-git-doctor smoke: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
