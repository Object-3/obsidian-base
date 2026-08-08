#!/usr/bin/env bash
# ── ENGINE FILE (base-owned) — AGENT NOTICE ─────────────────────────────────
# In a DERIVED VAULT (git origin is not the obsidian-base repo): if this script
# is buggy, do NOT fix it here and do NOT open a PR against the base repo —
# FILE A GITHUB ISSUE against the upstream base (.agents/.base-url if present,
# else Object-3/obsidian-base) with the error + proposed fix in the issue body.
# Local patches are overwritten by the next update-base and help no other clone.
# See AGENTS.md → "Engine bugs & improvements found in a derived vault".
# ─────────────────────────────────────────────────────────────────────────────
# Smoke test for .agents/scripts/vault-git-doctor.sh (issues #37 + #43) and the
# connect-github.sh base-origin guard.
#
# Self-contained and offline: builds throwaway git repos in a temp dir with the
# script + setup/lib.sh copied in (mirroring where they live in a real vault),
# and never fetches any remote — base-URL remotes exist as config only. Run
# from anywhere:
#
#   .agents/scripts/test-git-doctor-smoke.sh
#
# Covers:
#    1. clean vault → exit 0, both checks report ✓
#    2. branch tracking a base-URL remote (public default) → exit 3;
#       --fix-tracking detaches, removes the remote, re-report clean
#    3. a legitimate NON-base 'origin' survives --fix-tracking untouched, and
#       tracking is RE-POINTED to it after the base remote is removed
#    4. a remote literally NAMED 'base' at a non-template URL is NOT flagged
#       and survives the fix (identity is by URL, never by name)
#    5. an ambient BASE_REPO_URL export equal to the user's origin does NOT
#       weaponize the fix (identity ignores env)
#    6. URL normalization: ssh://…:22, ssh.github.com:443, user-less scp, and
#       double-trailing-slash forms all match the base (lib-level), and the
#       ssh-port form is flagged doctor-level; removing the only remote flips
#       Obsidian Git auto-sync back OFF
#    7. a fork pinned in .agents/.base-url is flagged, but the NON-INTERACTIVE
#       fix refuses to remove it (could be the user's own fork backup)
#    8. an unpersonalized TEMPLATE checkout (vault_name still {{VAULT_NAME}})
#       is never flagged/fixed; a profile that merely MENTIONS the placeholder
#       in prose is treated as personalized
#    9. stubs: 0-byte untracked stale stub flagged; a TRACKED empty file, a
#       fresh (<10 min) 0-byte file, _sensitive/ and raw/ are never flagged;
#       --fix-stubs with explicit paths deletes the stub (incl. a leading-dash
#       name) and REFUSES a path that grew content since the report
#   10. master-canonical repo with a STALE local main: an empty placeholder
#       committed on master (HEAD) is not flagged even though main lacks it
#   11. connect-github.sh guard: a base-pointing 'origin' is removed and the
#       create-your-own-repo path is reached (gh stubbed)
#   12. unbacked-vault note: zero remotes → informational '· backup:' line on
#       every report, no drift exit; silent once a remote exists
#   13. connect-github.sh visibility guard: non-interactive VISIBILITY=public
#       and a typo'd value both fall back to a PRIVATE repo
#
# Exits non-zero if any assertion fails.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DOCTOR_SRC="$ROOT/.agents/scripts/vault-git-doctor.sh"
LIB_SRC="$ROOT/setup/lib.sh"
CONNECT_SRC="$ROOT/setup/connect-github.sh"
[ -f "$DOCTOR_SRC" ]  || { echo "missing: $DOCTOR_SRC"; exit 1; }
[ -f "$LIB_SRC" ]     || { echo "missing: $LIB_SRC"; exit 1; }
[ -f "$CONNECT_SRC" ] || { echo "missing: $CONNECT_SRC"; exit 1; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
unset BASE_REPO_URL BASE_REPO   # deterministic base resolution inside the temp vaults

pass=0; fail=0
ok()  { echo "  ok:   $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }

G() { git -c user.name=t -c user.email=t@localhost "$@"; }   # commit identity for temp repos
age() { touch -t 202001010000 "$@"; }                        # backdate past the 10-min stub guard

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

# Run the doctor non-interactively (stdin not a tty) inside vault $1.
doctor() { ( cd "$1" && shift && ./.agents/scripts/vault-git-doctor.sh "$@" </dev/null ); }

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

# ---- 3. legit non-base origin survives; tracking re-pointed to it ----------
V3="$WORK/v3"; mk_vault "$V3"
( cd "$V3"
  git remote add origin https://github.com/someuser/my-private-vault.git
  git update-ref refs/remotes/origin/main HEAD          # simulate a fetched origin/main
  git remote add base https://github.com/Object-3/obsidian-base.git
  git config branch.main.remote base
  git config branch.main.merge refs/heads/main )
out=$(doctor "$V3" --fix-tracking); rc=$?
if [ "$rc" -eq 0 ] \
   && [ "$(cd "$V3" && git remote get-url origin)" = "https://github.com/someuser/my-private-vault.git" ] \
   && ! ( cd "$V3" && git remote get-url base ) >/dev/null 2>&1 \
   && [ "$(cd "$V3" && git config --get branch.main.remote)" = "origin" ]; then
  ok "non-base origin survived; base removed; tracking re-pointed to origin/main"
else
  bad "origin survival / re-point wrong (exit $rc): $out"
fi

# ---- 4. remote NAMED 'base' at a non-template URL is not flagged -----------
V4="$WORK/v4"; mk_vault "$V4"
( cd "$V4" && git remote add base https://github.com/someuser/my-private-vault.git )
out=$(doctor "$V4"); rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '✓ tracking'; then
  ok "remote named 'base' at a private URL not flagged (exit 0)"
else
  bad "name-based false positive (exit $rc): $out"
fi
doctor "$V4" --fix-tracking >/dev/null 2>&1
if ( cd "$V4" && git remote get-url base ) >/dev/null 2>&1; then
  ok "remote named 'base' at a private URL survives --fix-tracking"
else
  bad "fix removed a private remote just because it is named 'base'"
fi

# ---- 5. ambient BASE_REPO_URL export must not weaponize the fix ------------
V5="$WORK/v5"; mk_vault "$V5"
( cd "$V5"
  git remote add origin https://github.com/someuser/my-private-vault.git
  git config branch.main.remote origin
  git config branch.main.merge refs/heads/main )
out=$( cd "$V5" && BASE_REPO_URL="https://github.com/someuser/my-private-vault.git" \
       ./.agents/scripts/vault-git-doctor.sh --fix-tracking </dev/null ); rc=$?
if [ "$rc" -eq 0 ] \
   && ( cd "$V5" && git remote get-url origin ) >/dev/null 2>&1 \
   && [ "$(cd "$V5" && git config --get branch.main.remote)" = "origin" ]; then
  ok "env BASE_REPO_URL equal to origin does not classify it as the base"
else
  bad "ambient env weaponized the fix (exit $rc): $out"
fi

# ---- 6. URL normalization (lib-level) + doctor-level ssh-port + autosync off
norms_ok=1
while IFS= read -r u; do
  n=$(bash -c ". '$LIB_SRC'; lib_norm_git_url \"\$1\"" _ "$u")
  [ "$n" = "github.com/object-3/obsidian-base" ] || { norms_ok=""; bad "lib_norm_git_url('$u') = '$n'"; }
done <<'EOF'
ssh://git@github.com:22/Object-3/obsidian-base.git
ssh://git@ssh.github.com:443/Object-3/obsidian-base.git
github.com:Object-3/obsidian-base
https://github.com/Object-3/obsidian-base.git//
git@github.com:Object-3/obsidian-base
HTTPS://GitHub.com/object-3/obsidian-base/
EOF
[ -n "$norms_ok" ] && ok "all URL forms normalize to the same identity"
V6="$WORK/v6"; mk_vault "$V6"
mkdir -p "$V6/.obsidian/plugins/obsidian-git"
printf '{"autoSaveInterval":10,"autoPullInterval":10,"autoPullOnBoot":true,"autoBackupAfterFileChange":true,"disablePush":false}\n' \
  > "$V6/.obsidian/plugins/obsidian-git/data.json"
( cd "$V6" && git remote add origin "ssh://git@github.com:22/Object-3/obsidian-base.git" )
out=$(doctor "$V6"); rc=$?
if [ "$rc" -eq 3 ] && printf '%s' "$out" | grep -q "✗ remote: standing remote 'origin'"; then
  ok "ssh-port base URL on origin flagged (exit 3)"
else
  bad "ssh-port base URL not flagged (exit $rc): $out"
fi
out=$(doctor "$V6" --fix-tracking); rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q "connect-github.sh" \
   && ! ( cd "$V6" && git remote get-url origin ) >/dev/null 2>&1; then
  ok "--fix-tracking removed base 'origin' and pointed at connect-github.sh"
else
  bad "base 'origin' fix wrong (exit $rc): $out"
fi
if command -v jq >/dev/null 2>&1; then
  if [ "$(jq -r '.autoPullInterval' "$V6/.obsidian/plugins/obsidian-git/data.json")" = "0" ] \
     && [ "$(jq -r '.disablePush' "$V6/.obsidian/plugins/obsidian-git/data.json")" = "true" ]; then
    ok "no remotes left → Obsidian Git auto-sync flipped OFF"
  else
    bad "auto-sync not flipped off: $(cat "$V6/.obsidian/plugins/obsidian-git/data.json")"
  fi
fi

# ---- 7. fork pinned in .base-url: flagged, but non-interactive fix refuses --
V7="$WORK/v7"; mk_vault "$V7"
( cd "$V7"
  echo "https://example.com/me/my-base-fork.git" > .agents/.base-url
  git remote add base https://example.com/me/my-base-fork.git )
out=$(doctor "$V7"); rc=$?
if [ "$rc" -eq 3 ] && printf '%s' "$out" | grep -q "fork pin"; then
  ok "pinned fork base remote flagged (exit 3)"
else
  bad "pinned fork base remote not flagged (exit $rc): $out"
fi
out=$(doctor "$V7" --fix-tracking 2>&1); rc=$?
if [ "$rc" -eq 0 ] && ( cd "$V7" && git remote get-url base ) >/dev/null 2>&1 \
   && printf '%s' "$out" | grep -q "NOT auto-removing"; then
  ok "non-interactive fix refuses to remove a fork-pin match"
else
  bad "fork-pin match handling wrong (exit $rc): $out"
fi

# ---- 8. template checkout exemption (anchored, prose mention ignored) ------
V8="$WORK/v8"; mk_vault "$V8"
( cd "$V8"
  mkdir -p .agents
  printf -- '---\nvault_name:  "{{VAULT_NAME}}"\n---\n' > .agents/vault-profile.md
  git remote add origin https://github.com/Object-3/obsidian-base.git
  git config branch.main.remote origin
  git config branch.main.merge refs/heads/main )
out=$(doctor "$V8"); rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'TEMPLATE checkout'; then
  ok "unpersonalized template checkout not flagged as drift (exit 0)"
else
  bad "template checkout handling wrong (exit $rc): $out"
fi
out=$(doctor "$V8" --fix-tracking); rc=$?
if [ "$rc" -eq 0 ] && ( cd "$V8" && git remote get-url origin ) >/dev/null 2>&1 \
   && [ "$(cd "$V8" && git config --get branch.main.remote)" = "origin" ]; then
  ok "--fix-tracking skips a template checkout (origin + tracking intact)"
else
  bad "--fix-tracking touched a template checkout (exit $rc): $out"
fi
# Personalized profile that MENTIONS the placeholder in prose → checks stay live.
( cd "$V8"
  printf -- '---\nvault_name:  "My Vault"\n---\nThe init script replaces {{VAULT_NAME}} everywhere.\n' > .agents/vault-profile.md )
out=$(doctor "$V8"); rc=$?
if [ "$rc" -eq 3 ] && printf '%s' "$out" | grep -q "✗ tracking"; then
  ok "prose mention of the placeholder does not disable the check"
else
  bad "prose mention wrongly treated as template checkout (exit $rc): $out"
fi

# ---- 9. 0-byte stub scan ----------------------------------------------------
V9="$WORK/v9"; mk_vault "$V9"
( cd "$V9"
  : > placeholder.md            # 0-byte but TRACKED (committed on HEAD) → never flagged
  G add placeholder.md && G commit -q -m placeholder
  : > "old-name.md"             # 0-byte, untracked, stale → the race signature
  : > "-dash-stub.md"           # same, with a leading-dash name
  : > "fresh-note.md"           # 0-byte but BRAND-NEW → mtime guard must skip it
  mkdir -p _sensitive raw
  : > _sensitive/secret-stub.md # never scanned
  : > raw/raw-stub.md )         # never scanned
age "$V9/old-name.md" "$V9/-dash-stub.md" "$V9/placeholder.md" \
    "$V9/_sensitive/secret-stub.md" "$V9/raw/raw-stub.md"
out=$(doctor "$V9"); rc=$?
if [ "$rc" -eq 3 ] && printf '%s' "$out" | grep -q 'old-name.md' \
   && printf '%s' "$out" | grep -q -- '-dash-stub.md' \
   && ! printf '%s' "$out" | grep -q 'placeholder.md' \
   && ! printf '%s' "$out" | grep -q 'fresh-note.md' \
   && ! printf '%s' "$out" | grep -q 'secret-stub' \
   && ! printf '%s' "$out" | grep -q 'raw-stub'; then
  ok "stubs flagged; tracked-empty, fresh, _sensitive/ and raw/ files ignored (exit 3)"
else
  bad "stub scan wrong (exit $rc): $out"
fi
# Explicit-path fix: deletes the reviewed stubs, refuses a path that changed.
echo "content grew" > "$V9/old-name.md"; age "$V9/old-name.md"
out=$(doctor "$V9" --fix-stubs old-name.md -dash-stub.md 2>&1); rc=$?
if [ "$rc" -eq 0 ] && [ ! -f "$V9/-dash-stub.md" ] \
   && [ -f "$V9/old-name.md" ] && printf '%s' "$out" | grep -q "skipped 'old-name.md'" \
   && [ -f "$V9/_sensitive/secret-stub.md" ] && [ -f "$V9/raw/raw-stub.md" ] \
   && [ -f "$V9/placeholder.md" ] && [ -f "$V9/fresh-note.md" ]; then
  ok "--fix-stubs <paths> deleted the dash stub, refused the changed path, touched nothing else"
else
  bad "--fix-stubs explicit-path handling wrong (exit $rc): $out"
fi

# ---- 10. master-canonical repo with a STALE local main ---------------------
V10="$WORK/v10"; mk_vault "$V10"
( cd "$V10"
  git branch -m main master            # canonical branch is master...
  git branch main HEAD                 # ...and a 'main' still exists, about to go stale
  : > team-placeholder.md
  G add team-placeholder.md && G commit -q -m "placeholder on master" )  # main now lacks it
age "$V10/team-placeholder.md"
out=$(doctor "$V10"); rc=$?
if [ "$rc" -eq 0 ] && ! printf '%s' "$out" | grep -q 'team-placeholder'; then
  ok "tracked empty file on HEAD not flagged despite stale local main"
else
  bad "stale-main false positive (exit $rc): $out"
fi
doctor "$V10" --fix-stubs >/dev/null 2>&1
if [ -f "$V10/team-placeholder.md" ]; then
  ok "--fix-stubs leaves the committed placeholder alone"
else
  bad "--fix-stubs deleted a committed placeholder (stale-main data loss)"
fi

# ---- 11. connect-github.sh guard (gh stubbed) ------------------------------
V11="$WORK/v11"; mk_vault "$V11"
cp "$CONNECT_SRC" "$V11/setup/connect-github.sh"; chmod +x "$V11/setup/connect-github.sh"
( cd "$V11"
  git remote add origin https://github.com/Object-3/obsidian-base.git
  git config branch.main.remote origin
  git config branch.main.merge refs/heads/main )
mkdir -p "$WORK/bin"
cat > "$WORK/bin/gh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$WORK/bin/gh"
out=$( cd "$V11" && PATH="$WORK/bin:$PATH" ./setup/connect-github.sh </dev/null 2>&1 ); rc=$?
if printf '%s' "$out" | grep -q "PUBLIC base template" \
   && printf '%s' "$out" | grep -q "Creating" \
   && ! ( cd "$V11" && git config --get branch.main.remote ) >/dev/null 2>&1; then
  # The stubbed gh "creates" without re-adding origin — what matters is the
  # base-pointing origin was removed (tracking gone) and the create path ran.
  ok "connect-github guard removed base origin and reached the create path"
else
  bad "connect-github guard wrong (exit $rc): $out"
fi

# ---- 12. unbacked-vault note (check 1b) ------------------------------------
# Zero remotes → the report surfaces "local-only, nothing backing it up" on
# every run — informational only, never drift (exit stays 0 on an otherwise
# clean vault). A vault WITH a remote must not print it.
V12="$WORK/v12"; mk_vault "$V12"
out=$(doctor "$V12"); rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '· backup: this vault has NO git remote'; then
  ok "zero-remote vault surfaces the unbacked note without drift (exit 0)"
else
  bad "unbacked note missing or drift exit (exit $rc): $out"
fi
( cd "$V12" && git remote add origin https://github.com/someone/private-vault.git )
out=$(doctor "$V12"); rc=$?
if [ "$rc" -eq 0 ] && ! printf '%s' "$out" | grep -q '· backup:'; then
  ok "vault with a remote does not print the unbacked note"
else
  bad "unbacked note printed despite a remote (exit $rc): $out"
fi

# ---- 13. connect-github.sh visibility guard (gh stubbed) -------------------
# VISIBILITY=public in a NON-interactive run cannot be confirmed → falls back
# to private; a typo'd value falls back too. (Interactive re-type path needs a
# tty, so the non-interactive fallback is what's assertable here.)
V13="$WORK/v13"; mk_vault "$V13"
cp "$CONNECT_SRC" "$V13/setup/connect-github.sh"; chmod +x "$V13/setup/connect-github.sh"
out=$( cd "$V13" && PATH="$WORK/bin:$PATH" VISIBILITY=public OWNER=o REPO_NAME=r ./setup/connect-github.sh </dev/null 2>&1 ); rc=$?
if printf '%s' "$out" | grep -q "can't confirm 'public'" \
   && printf '%s' "$out" | grep -q "(private)"; then
  ok "non-interactive VISIBILITY=public falls back to a private repo"
else
  bad "public-visibility fallback wrong (exit $rc): $out"
fi
out=$( cd "$V13" && PATH="$WORK/bin:$PATH" VISIBILITY=Pulbic OWNER=o REPO_NAME=r ./setup/connect-github.sh </dev/null 2>&1 ); rc=$?
if printf '%s' "$out" | grep -q "Unrecognized visibility" \
   && printf '%s' "$out" | grep -q "(private)"; then
  ok "typo'd visibility falls back to a private repo"
else
  bad "typo'd-visibility fallback wrong (exit $rc): $out"
fi

echo
echo "vault-git-doctor smoke: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
