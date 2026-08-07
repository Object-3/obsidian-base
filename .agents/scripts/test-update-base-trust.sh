#!/usr/bin/env bash
# ── ENGINE FILE (base-owned) — AGENT NOTICE ─────────────────────────────────
# In a DERIVED VAULT (git origin is not the obsidian-base repo): if this script
# is buggy, do NOT fix it here and do NOT open a PR against the base repo —
# FILE A GITHUB ISSUE against the upstream base (.agents/.base-url if present,
# else Object-3/obsidian-base) with the error + proposed fix in the issue body.
# Local patches are overwritten by the next update-base and help no other clone.
# See AGENTS.md → "Engine bugs & improvements found in a derived vault".
# ─────────────────────────────────────────────────────────────────────────────
# Smoke test for the "make update-base trustworthy" batch (issues #42, #59, #70):
#
#   1. .githooks/pre-commit.d/ SURVIVES an update-base overlay (never pruned) and
#      is exempt from the pre-commit engine guard, so a derived vault can commit
#      its own guards there.
#   2. A vault-local (non-base) file under .claude/hooks/ is still pruned, but the
#      run REPORTS it loudly ("NON-BASE file … will be DELETED") instead of
#      deleting silently.
#   3. A 'vault-local'-marked addition inside a base-owned file (.githooks/
#      pre-commit) gets a loud drop-warning when the overlay rewrites the file.
#   4. update-base writes .agents/.base-sync ("<sha> <ref> <iso-timestamp>") with
#      the resolved base SHA, and stages it.
#   5. Scenario B — injection defense + steady state: a base-SHIPPED file under
#      .githooks/pre-commit.d/ is NEVER checked out into the vault ("never
#      overlaid" holds in both directions), a vault with committed pre-commit.d
#      guards still reaches "Already up to date" (no per-run sync noise / warning
#      fatigue), a surviving marked guard raises NO false drop-warning, and the
#      no-op run announces the staged .base-sync stamp.
#   6. .githooks/pre-commit executes the guards in .githooks/pre-commit.d/:
#      passing guard → commit allowed; failing guard → blocked; non-executable
#      file → ignored.
#
# Fully offline: throwaway git repos in a temp dir, local-path fetches only.
#
#   .agents/scripts/test-update-base-trust.sh
#
# Exits non-zero if any assertion fails. Requires git + jq (same as update-base).
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

fail=0
ok()  { printf '  ok: %s\n' "$*"; }
bad() { printf '  FAIL: %s\n' "$*"; fail=1; }

command -v git >/dev/null || { echo "git required"; exit 1; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
base="$tmp/base"; fork="$tmp/fork"

# ── Base: this repo's committed HEAD, on a `main` branch (the default BASE_REF).
git clone -q --local "$ROOT" "$base"
git -C "$base" checkout -q -B main
base_sha="$(git -C "$base" rev-parse main)"

# ── Fork: clone the base, then layer on the three vault-local customizations
# from issue #42's real-world report (all COMMITTED, so the old uncommitted-only
# warning would never have fired).
git clone -q --local "$base" "$fork"
git -C "$fork" checkout -q -B main
mkdir -p "$fork/.githooks/pre-commit.d"
printf '#!/usr/bin/env bash\n# vault-local: surviving guard — its marker must NOT trigger a drop warning\nexit 0\n' \
  > "$fork/.githooks/pre-commit.d/my-guard.sh"
chmod +x "$fork/.githooks/pre-commit.d/my-guard.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$fork/.claude/hooks/vault-only-hook.sh"
chmod +x "$fork/.claude/hooks/vault-only-hook.sh"
printf '\n# vault-local: extra confidential-names check appended by this vault\n' \
  >> "$fork/.githooks/pre-commit"
git -C "$fork" add .githooks/pre-commit.d/my-guard.sh .claude/hooks/vault-only-hook.sh .githooks/pre-commit
git -C "$fork" -c user.email=t@t -c user.name=t commit -q -m "vault-local guards + marked addition"

# ── Run update-base in the fork against the local base.
echo "== running update-base.sh in the customized fork =="
( cd "$fork" && BASE_REPO_URL="$base" BASE_REF=main .agents/scripts/update-base.sh ) >"$tmp/out.log" 2>&1
run_rc=$?
sed 's/^/     | /' "$tmp/out.log"
[ "$run_rc" -eq 0 ] && ok "update-base exited 0" || bad "update-base exited $run_rc"

# 1. Extension point survives the overlay.
if [ -x "$fork/.githooks/pre-commit.d/my-guard.sh" ] \
   && git -C "$fork" ls-files --error-unmatch .githooks/pre-commit.d/my-guard.sh >/dev/null 2>&1; then
  ok "pre-commit.d/ guard survived the overlay (present + still tracked)"
else
  bad "pre-commit.d/ guard was pruned or untracked by the overlay"
fi

# 2. Non-base file under .claude/hooks/ is reported loudly when pruned.
if grep -q "pruned NON-BASE file '.claude/hooks/vault-only-hook.sh'" "$tmp/out.log"; then
  ok "prune loudly reported the non-base .claude/hooks/ file"
else
  bad "no loud NON-BASE prune report for .claude/hooks/vault-only-hook.sh"
fi
if [ ! -f "$fork/.claude/hooks/vault-only-hook.sh" ]; then
  ok "non-base .claude/hooks/ file was pruned (deletion visible, not silent)"
else
  bad "non-base .claude/hooks/ file was not pruned"
fi

# 3. '# vault-local:' marker drop-warning on the overlaid pre-commit (diff-based),
# and NO warning about the surviving guard in pre-commit.d/ (it also carries the
# marker, but it is not being dropped — a count-based heuristic would false-alarm).
if grep -q "'.githooks/pre-commit': 1 '# vault-local:'-marked line" "$tmp/out.log"; then
  ok "marker drop-warning fired for .githooks/pre-commit"
else
  bad "no '# vault-local:' drop-warning for .githooks/pre-commit"
fi
if grep -q "'.githooks/pre-commit.d/my-guard.sh'" "$tmp/out.log"; then
  bad "false loss warning about the SURVIVING pre-commit.d/ guard"
else
  ok "no false loss warning about the surviving pre-commit.d/ guard"
fi
if cmp -s "$base/.githooks/pre-commit" "$fork/.githooks/pre-commit"; then
  ok "pre-commit restored byte-identical to base (overlay itself still works)"
else
  bad "pre-commit differs from base after overlay"
fi

# 4. .base-sync stamp: "<sha> <ref> <iso-timestamp>", correct SHA, staged.
stamp="$fork/.agents/.base-sync"
if [ -f "$stamp" ]; then
  read -r s_sha s_ref s_ts < "$stamp"
  [ "$s_sha" = "$base_sha" ] && ok "stamp SHA matches the fetched base" \
                             || bad "stamp SHA '$s_sha' != base '$base_sha'"
  [ "$s_ref" = "main" ] && ok "stamp ref is 'main'" || bad "stamp ref '$s_ref' != 'main'"
  case "$s_ts" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T*Z) ok "stamp timestamp is ISO-8601 UTC" ;;
    *) bad "stamp timestamp '$s_ts' not ISO-8601 UTC" ;;
  esac
  git -C "$fork" diff --cached --name-only | grep -qxF ".agents/.base-sync" \
    && ok "stamp is staged" || bad "stamp not staged"
else
  bad ".agents/.base-sync was not written"
fi

# ── Scenario B: injection defense + steady state ──
# base2 SHIPS a file under .githooks/pre-commit.d/ (a compromised upstream planting
# an auto-running, engine-guard-exempt executable). fork2 carries its own committed
# guard there. The run must (a) NOT inject the base file, (b) keep the vault guard,
# and (c) still report "Already up to date" — the extension point must not keep the
# vault permanently "dirty" against the base.
echo "== scenario B: base-shipped pre-commit.d file + steady state =="
base2="$tmp/base2"; fork2="$tmp/fork2"
git clone -q --local "$base" "$base2"
git -C "$base2" checkout -q -B main
mkdir -p "$base2/.githooks/pre-commit.d"
printf '#!/usr/bin/env bash\necho pwned\n' > "$base2/.githooks/pre-commit.d/injected.sh"
chmod +x "$base2/.githooks/pre-commit.d/injected.sh"
git -C "$base2" add .githooks/pre-commit.d/injected.sh
git -C "$base2" -c user.email=t@t -c user.name=t commit -q -m "base ships a pre-commit.d file (must never propagate)"

git clone -q --local "$base" "$fork2"
git -C "$fork2" checkout -q -B main
mkdir -p "$fork2/.githooks/pre-commit.d"
printf '#!/usr/bin/env bash\n# vault-local: steady-state guard\nexit 0\n' > "$fork2/.githooks/pre-commit.d/local-guard.sh"
chmod +x "$fork2/.githooks/pre-commit.d/local-guard.sh"
git -C "$fork2" add .githooks/pre-commit.d/local-guard.sh
git -C "$fork2" -c user.email=t@t -c user.name=t commit -q -m "vault-local guard (steady state)"

( cd "$fork2" && BASE_REPO_URL="$base2" BASE_REF=main .agents/scripts/update-base.sh ) >"$tmp/out2.log" 2>&1
run2_rc=$?
sed 's/^/     | /' "$tmp/out2.log"
[ "$run2_rc" -eq 0 ] && ok "run B exited 0" || bad "run B exited $run2_rc"

if [ ! -e "$fork2/.githooks/pre-commit.d/injected.sh" ] \
   && ! git -C "$fork2" diff --cached --name-only | grep -q "injected.sh"; then
  ok "base-shipped pre-commit.d file was NOT injected (not on disk, not staged)"
else
  bad "base-shipped pre-commit.d/injected.sh landed in the vault (injection!)"
fi

if [ -x "$fork2/.githooks/pre-commit.d/local-guard.sh" ]; then
  ok "vault-local guard survived run B"
else
  bad "vault-local guard lost in run B"
fi

if grep -q "Already up to date" "$tmp/out2.log"; then
  ok "steady state: committed pre-commit.d guards still reach 'Already up to date'"
else
  bad "steady state broken: run B did not report 'Already up to date'"
fi

if grep -q "!!" "$tmp/out2.log"; then
  bad "run B printed loss warnings on a steady-state vault"
else
  ok "no loss warnings on a steady-state vault"
fi

if grep -q ".base-sync was refreshed" "$tmp/out2.log"; then
  ok "no-op run announces the staged .base-sync stamp"
else
  bad "no-op run did not announce the staged stamp"
fi

base2_sha="$(git -C "$base2" rev-parse main)"
if [ "$(cut -d' ' -f1 "$fork2/.agents/.base-sync")" = "$base2_sha" ]; then
  ok "run B stamp records base2's SHA"
else
  bad "run B stamp SHA wrong"
fi

# ── 5. The pre-commit hook runs .githooks/pre-commit.d/ guards ──
echo "== pre-commit.d execution + engine-guard exemption =="
hookrepo="$tmp/hookrepo"
mkdir -p "$hookrepo/.githooks/pre-commit.d"
cp "$ROOT/.githooks/pre-commit" "$hookrepo/.githooks/pre-commit"
chmod +x "$hookrepo/.githooks/pre-commit"
git -C "$hookrepo" init -q
git -C "$hookrepo" remote add origin "https://github.com/someone/derived-vault.git"  # a DERIVED vault

# passing guard → hook passes (and the staged pre-commit.d file passes the engine guard)
printf '#!/usr/bin/env bash\nexit 0\n' > "$hookrepo/.githooks/pre-commit.d/10-pass.sh"
chmod +x "$hookrepo/.githooks/pre-commit.d/10-pass.sh"
git -C "$hookrepo" add .githooks/pre-commit.d/10-pass.sh
if ( cd "$hookrepo" && ./.githooks/pre-commit ) >"$tmp/hook1.log" 2>&1; then
  ok "passing vault-local guard → commit allowed (and pre-commit.d/ passes the engine guard)"
else
  sed 's/^/     | /' "$tmp/hook1.log"
  bad "hook failed with only a passing guard staged under pre-commit.d/"
fi

# failing guard → hook blocks with a clear message
printf '#!/usr/bin/env bash\nexit 1\n' > "$hookrepo/.githooks/pre-commit.d/20-fail.sh"
chmod +x "$hookrepo/.githooks/pre-commit.d/20-fail.sh"
if ( cd "$hookrepo" && ./.githooks/pre-commit ) >"$tmp/hook2.log" 2>&1; then
  bad "hook passed despite a failing vault-local guard"
else
  grep -q "vault-local guard failed: .githooks/pre-commit.d/20-fail.sh" "$tmp/hook2.log" \
    && ok "failing vault-local guard → commit blocked, guard named" \
    || bad "hook blocked but did not name the failing guard"
fi

# non-executable file → ignored
chmod -x "$hookrepo/.githooks/pre-commit.d/20-fail.sh"
if ( cd "$hookrepo" && ./.githooks/pre-commit ) >"$tmp/hook3.log" 2>&1; then
  ok "non-executable file in pre-commit.d/ is ignored"
else
  bad "non-executable file in pre-commit.d/ still ran/blocked"
fi

# engine guard still blocks base-owned .githooks/pre-commit itself in a derived vault
git -C "$hookrepo" add .githooks/pre-commit
if ( cd "$hookrepo" && ./.githooks/pre-commit ) >"$tmp/hook4.log" 2>&1; then
  bad "engine guard let a derived vault stage base-owned .githooks/pre-commit"
else
  grep -q "base-owned ENGINE file" "$tmp/hook4.log" \
    && ok "engine guard still blocks base-owned .githooks/pre-commit in a derived vault" \
    || bad "hook blocked staged pre-commit but not via the engine guard"
fi

echo
if [ "$fail" -eq 0 ]; then echo "PASS: update-base trustworthiness (issues #42/#59/#70)"; else echo "FAIL: update-base trustworthiness (issues #42/#59/#70)"; fi
exit "$fail"
