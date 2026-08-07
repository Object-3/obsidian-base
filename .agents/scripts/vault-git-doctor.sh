#!/usr/bin/env bash
# ── ENGINE FILE (base-owned) — AGENT NOTICE ─────────────────────────────────
# In a DERIVED VAULT (git origin is not the obsidian-base repo): if this script
# is buggy, do NOT fix it here and do NOT open a PR against the base repo —
# FILE A GITHUB ISSUE against the upstream base (.agents/.base-url if present,
# else Object-3/obsidian-base) with the error + proposed fix in the issue body.
# Local patches are overwritten by the next update-base and help no other clone.
# See AGENTS.md → "Engine bugs & improvements found in a derived vault".
# ─────────────────────────────────────────────────────────────────────────────
# Live-vault git sync health: report drift, repair only on request.
#
# CHECK 1 — base tracking (issue #37). A personal vault's branch must NEVER
#   track a remote that points at the BASE template (public default
#   Object-3/obsidian-base, or the fork pinned in .agents/.base-url). The
#   shipped Obsidian Git config auto-pulls+merges once 'origin' is connected,
#   so a base-tracking branch continuously merges the public template into the
#   personal vault (conflict-copy junk committed to history, content-bleed
#   risk). The base is only ever reached via update-base's EPHEMERAL remote —
#   no standing remote may carry its URL.
#
# CHECK 2 — 0-byte rename stubs (issue #43). When a rename/move merge lands
#   while Obsidian is open on the live vault, Obsidian can leave a 0-byte file
#   at the OLD path. Signature: an EMPTY .md file in the working tree at a path
#   NOT present on main. Content is safe in git; the stub is junk. The scan
#   never touches _sensitive/, _local/, raw/, or dot-folders.
#
# Usage:
#   vault-git-doctor.sh                  # report both checks; exit 0 = clean, 3 = drift
#   vault-git-doctor.sh --fix-tracking   # detach base tracking + remove base-URL remotes
#   vault-git-doctor.sh --fix-stubs      # delete the reported 0-byte stubs
#   vault-git-doctor.sh --fix            # both fixes
# Fix modes print only what they change (quiet when already clean), so
# init-vault.sh can run --fix-tracking unconditionally at init time.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"; cd "$ROOT"

# Shared base-URL identity (DEFAULT_BASE_REPO_URL, resolve_base_url,
# lib_norm_git_url, lib_is_base_url) — single source of truth in setup/lib.sh.
# shellcheck disable=SC1091
. "$ROOT/setup/lib.sh"

FIX_TRACKING=""; FIX_STUBS=""; REPORT=1
for arg in "$@"; do
  case "$arg" in
    --fix)          FIX_TRACKING=1; FIX_STUBS=1; REPORT="" ;;
    --fix-tracking) FIX_TRACKING=1; REPORT="" ;;
    --fix-stubs)    FIX_STUBS=1; REPORT="" ;;
    *) echo "usage: vault-git-doctor.sh [--fix-tracking] [--fix-stubs] [--fix]" >&2; exit 2 ;;
  esac
done

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  [ -n "$REPORT" ] && echo "not a git repo — nothing to check"; exit 0; }

drift=0

# In the BASE repo itself (or a contributor checkout) 'origin' legitimately IS
# the base URL — flagging or stripping it there would break the maintainer's
# checkout. Distinguisher: an unpersonalized {{VAULT_NAME}} placeholder in
# vault-profile.md means "template checkout, not a personal vault"; init-vault.sh
# runs the tracking fix AFTER personalization, so the primary
# cloned-the-base-directly path still gets repaired at init time.
TEMPLATE_CHECKOUT=""
grep -q '{{VAULT_NAME}}' "$ROOT/.agents/vault-profile.md" 2>/dev/null && TEMPLATE_CHECKOUT=1

# ---- check 1: no branch tracking / standing remote on the base URL ---------
branch="$(git symbolic-ref --short -q HEAD || echo main)"
upstream_remote="$(git config --get "branch.$branch.remote" 2>/dev/null || true)"

tracking_drift=""
if [ -n "$upstream_remote" ] && [ "$upstream_remote" != "." ]; then
  upstream_url="$(git remote get-url "$upstream_remote" 2>/dev/null || true)"
  if [ -n "$upstream_url" ] && lib_is_base_url "$upstream_url" "$ROOT"; then
    tracking_drift=1
  fi
fi

# Any standing remote on the base URL is drift, whatever its name — update-base
# reaches the base via its own ephemeral remote only. (A leftover
# `base-ephemeral` from a hard-killed run is included: update-base would reclaim
# it, but until then it sits in Obsidian Git's remote picker like any other.)
base_remotes=()
while IFS= read -r r; do
  [ -n "$r" ] || continue
  url="$(git remote get-url "$r" 2>/dev/null || true)"
  if [ -n "$url" ] && lib_is_base_url "$url" "$ROOT"; then base_remotes+=("$r"); fi
done < <(git remote)

template_note=""
if [ -n "$TEMPLATE_CHECKOUT" ]; then
  if [ -n "$REPORT" ] && { [ -n "$tracking_drift" ] || [ "${#base_remotes[@]}" -gt 0 ]; }; then
    template_note=1
    echo "· tracking: base-URL remote/tracking present, but this looks like a TEMPLATE checkout"
    echo "    (vault-profile.md still has {{VAULT_NAME}}) — expected in the base repo itself."
    echo "    For a personal vault, run .agents/scripts/init-vault.sh first; it personalizes and then repairs tracking."
  elif [ -z "$REPORT" ] && [ -n "$FIX_TRACKING" ]; then
    echo "skip: template checkout (vault-profile.md still has {{VAULT_NAME}}) — not touching remotes/tracking."
  fi
  tracking_drift=""; base_remotes=(); FIX_TRACKING=""
fi

if [ -n "$REPORT" ]; then
  if [ -n "$tracking_drift" ]; then
    drift=1
    echo "✗ tracking: branch '$branch' tracks '$upstream_remote' → $(git remote get-url "$upstream_remote") — the BASE template."
    echo "    Obsidian Git auto-pull would keep merging the public template into this vault (issue #37)."
    echo "    fix: .agents/scripts/vault-git-doctor.sh --fix-tracking"
  fi
  if [ "${#base_remotes[@]}" -gt 0 ]; then
    drift=1
    for r in ${base_remotes[@]+"${base_remotes[@]}"}; do
      echo "✗ remote: standing remote '$r' → $(git remote get-url "$r") points at the BASE template."
    done
    echo "    The base is only reached via update-base's ephemeral remote; no standing remote may carry it."
    echo "    fix: .agents/scripts/vault-git-doctor.sh --fix-tracking"
  fi
  if [ -z "$tracking_drift" ] && [ "${#base_remotes[@]}" -eq 0 ] && [ -z "$template_note" ]; then
    echo "✓ tracking: no branch tracks the base template; no standing base-URL remote."
  fi
fi

if [ -n "$FIX_TRACKING" ]; then
  if [ -n "$tracking_drift" ]; then
    git branch --unset-upstream "$branch" 2>/dev/null \
      || { git config --unset "branch.$branch.remote" 2>/dev/null || true
           git config --unset "branch.$branch.merge"  2>/dev/null || true; }
    echo "fixed: branch '$branch' no longer tracks the base template ('$upstream_remote')."
  fi
  for r in ${base_remotes[@]+"${base_remotes[@]}"}; do
    url="$(git remote get-url "$r" 2>/dev/null || true)"
    git remote remove "$r"
    echo "fixed: removed base-URL remote '$r' ($url)."
    if [ "$r" = "origin" ]; then
      echo "  'origin' pointed at the PUBLIC base template — reconnect your OWN backup repo with setup/connect-github.sh."
    fi
  done
  if [ -n "$tracking_drift" ] || [ "${#base_remotes[@]}" -gt 0 ]; then
    echo "  Base updates still work: update-base.sh uses its own ephemeral remote."
  fi
fi

# ---- check 2: 0-byte .md stubs at paths not present on main ----------------
# Compare against main (the canonical vault branch); fall back to HEAD when a
# repo has no main yet. Skip _sensitive/, _local/, raw/, and dot-folders.
ref="main"; git rev-parse -q --verify "$ref" >/dev/null 2>&1 || ref="HEAD"
stubs=()
if git rev-parse -q --verify "$ref" >/dev/null 2>&1; then
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    p="${f#./}"
    git cat-file -e "$ref:$p" 2>/dev/null && continue   # on main → not the race signature
    stubs+=("$p")
  done < <(find . -mindepth 1 \
             \( -name '.?*' -o -name _sensitive -o -name _local -o -name raw \) -prune \
             -o -type f -name '*.md' -size 0 -print 2>/dev/null)
fi

if [ -n "$REPORT" ]; then
  if [ "${#stubs[@]}" -gt 0 ]; then
    drift=1
    echo "✗ stubs: ${#stubs[@]} empty (0-byte) note(s) at paths not on $ref — the Obsidian-open-during-rename-merge signature (issue #43):"
    for p in ${stubs[@]+"${stubs[@]}"}; do echo "    $p"; done
    echo "    Content is safe in git; these are working-tree junk. But VERIFY none is a brand-new note you just created empty."
    echo "    fix: .agents/scripts/vault-git-doctor.sh --fix-stubs"
  else
    echo "✓ stubs: no 0-byte notes at paths missing from $ref."
  fi
fi

if [ -n "$FIX_STUBS" ]; then
  for p in ${stubs[@]+"${stubs[@]}"}; do
    rm -f "$p"
    git rm -q --cached --ignore-unmatch -- "$p" >/dev/null 2>&1 || true
    echo "fixed: removed 0-byte stub $p"
  done
fi

if [ -n "$REPORT" ] && [ "$drift" -ne 0 ]; then exit 3; fi
exit 0
