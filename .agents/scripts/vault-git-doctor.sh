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
#   Base identity comes from ON-DISK PINNED STATE only (lib_base_url_kind:
#   public default + .agents/.base-url) — never the BASE_REPO_URL/BASE_REPO
#   env and never a remote's NAME — so an ambient export equal to the user's
#   origin, or a remote merely CALLED 'base' that points at their private
#   repo, is never misclassified as the template. A match on the public
#   default is fixed automatically on request; a match on the .base-url fork
#   pin could be a legitimate private-fork backup, so it is only removed after
#   an interactive yes (skipped with a warning in non-interactive runs).
#
# CHECK 1b — unbacked vault (report only, PR #75 review). A personalized vault
#   with NO git remote at all gets an informational '· backup:' line on every
#   report run — e.g. after --fix-tracking removed a fork-as-base backup, when
#   pushes stop by design with only a one-time message. Never a drift exit:
#   a deliberately local-only vault is legitimate; the state just stays visible.
#
# CHECK 2 — 0-byte rename stubs (issue #43). When a rename/move merge lands
#   while Obsidian is open on the live vault, Obsidian can leave a 0-byte file
#   at the OLD path. Signature: an EMPTY, UNTRACKED .md file in the working
#   tree at a path not present on the CURRENT branch (HEAD — never a possibly
#   stale local 'main'). Content is safe in git; the stub is junk. Files
#   tracked in the index are never flagged, 0-byte files younger than 10
#   minutes are never flagged (Obsidian materializes brand-new notes as 0-byte
#   immediately), and the scan never touches _sensitive/, _local/, raw/, or
#   dot-folders.
#
# Usage:
#   vault-git-doctor.sh                        # report both checks; exit 0 = clean, 3 = drift
#   vault-git-doctor.sh --fix-tracking         # detach base tracking + remove base-URL remotes
#   vault-git-doctor.sh --fix-stubs [path...]  # delete stubs; pass the REPORTED paths so the
#                                              #   fix consumes the list you reviewed (each is
#                                              #   re-validated) instead of re-scanning blind
#   vault-git-doctor.sh --fix                  # both fixes
# Fix modes print only what they change (quiet when already clean), so
# init-vault.sh can run --fix-tracking unconditionally at init time.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"; cd "$ROOT"

# Shared base-URL identity (DEFAULT_BASE_REPO_URL, lib_norm_git_url,
# lib_base_url_kind) — single source of truth in setup/lib.sh.
# shellcheck disable=SC1091
. "$ROOT/setup/lib.sh"

FIX_TRACKING=""; FIX_STUBS=""; REPORT=1; STUB_PATHS=()
usage() { echo "usage: vault-git-doctor.sh [--fix-tracking] [--fix-stubs [path...]] [--fix]" >&2; exit 2; }
for arg in "$@"; do
  case "$arg" in
    --fix)          FIX_TRACKING=1; FIX_STUBS=1; REPORT="" ;;
    --fix-tracking) FIX_TRACKING=1; REPORT="" ;;
    --fix-stubs)    FIX_STUBS=1; REPORT="" ;;
    --*)            usage ;;
    *)              STUB_PATHS+=("$arg") ;;
  esac
done
if [ "${#STUB_PATHS[@]}" -gt 0 ] && [ -z "$FIX_STUBS" ]; then usage; fi

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  [ -n "$REPORT" ] && echo "not a git repo — nothing to check"; exit 0; }
# The vault root may sit below the git toplevel; commit paths need this prefix.
GIT_PREFIX="$(git rev-parse --show-prefix 2>/dev/null || true)"

drift=0

# In the BASE repo itself (or a contributor checkout) 'origin' legitimately IS
# the base URL — flagging or stripping it there would break the maintainer's
# checkout. Distinguisher: an UNPERSONALIZED vault_name frontmatter field
# (still the {{VAULT_NAME}} placeholder) in vault-profile.md means "template
# checkout, not a personal vault". Anchored to the field so a personalized
# profile that merely MENTIONS the placeholder in prose doesn't disable the
# check; a missing vault-profile.md counts as personalized. init-vault.sh runs
# the tracking fix AFTER personalization, so the primary
# cloned-the-base-directly path still gets repaired at init time.
TEMPLATE_CHECKOUT=""
grep -Eq '^vault_name:[[:space:]]*.*[{][{]VAULT_NAME[}][}]' "$ROOT/.agents/vault-profile.md" 2>/dev/null \
  && TEMPLATE_CHECKOUT=1

# ---- check 1: no branch tracking / standing remote on the base URL ---------
branch="$(git symbolic-ref --short -q HEAD || echo main)"
upstream_remote="$(git config --get "branch.$branch.remote" 2>/dev/null || true)"

tracking_drift=""
if [ -n "$upstream_remote" ] && [ "$upstream_remote" != "." ]; then
  upstream_url="$(git remote get-url "$upstream_remote" 2>/dev/null || true)"
  if [ -n "$upstream_url" ] && lib_base_url_kind "$upstream_url" "$ROOT" >/dev/null; then
    tracking_drift=1
  fi
fi

# Any standing remote on the base URL is drift, whatever its name — update-base
# reaches the base via its own ephemeral remote only. (A leftover
# `base-ephemeral` from a hard-killed run is included: update-base would reclaim
# it, but until then it sits in Obsidian Git's remote picker like any other.)
base_remotes=(); base_kinds=()
while IFS= read -r r; do
  [ -n "$r" ] || continue
  url="$(git remote get-url "$r" 2>/dev/null || true)"
  [ -n "$url" ] || continue
  if kind="$(lib_base_url_kind "$url" "$ROOT")"; then
    base_remotes+=("$r"); base_kinds+=("$kind")
  fi
done < <(git remote)

kind_label() { # default|pin -> human phrase
  case "$1" in
    default) echo "the PUBLIC base template" ;;
    pin)     echo "your .agents/.base-url fork pin" ;;
  esac
}

template_note=""
if [ -n "$TEMPLATE_CHECKOUT" ]; then
  if [ -n "$REPORT" ] && { [ -n "$tracking_drift" ] || [ "${#base_remotes[@]}" -gt 0 ]; }; then
    template_note=1
    echo "· tracking: base-URL remote/tracking present, but this looks like a TEMPLATE checkout"
    echo "    (vault-profile.md still has the {{VAULT_NAME}} placeholder) — expected in the base repo itself."
    echo "    For a personal vault, run .agents/scripts/init-vault.sh first; it personalizes and then repairs tracking."
  elif [ -z "$REPORT" ] && [ -n "$FIX_TRACKING" ]; then
    echo "skip: template checkout (vault-profile.md still has the {{VAULT_NAME}} placeholder) — not touching remotes/tracking."
  fi
  tracking_drift=""; base_remotes=(); base_kinds=(); FIX_TRACKING=""
fi

if [ -n "$REPORT" ]; then
  if [ -n "$tracking_drift" ]; then
    drift=1
    echo "✗ tracking: branch '$branch' tracks '$upstream_remote' → $(git remote get-url "$upstream_remote") — the BASE template."
    echo "    Obsidian Git auto-pull would keep merging the template into this vault (issue #37)."
    echo "    fix: .agents/scripts/vault-git-doctor.sh --fix-tracking"
  fi
  if [ "${#base_remotes[@]}" -gt 0 ]; then
    drift=1
    i=0
    for r in ${base_remotes[@]+"${base_remotes[@]}"}; do
      echo "✗ remote: standing remote '$r' → $(git remote get-url "$r") matches $(kind_label "${base_kinds[$i]}")."
      i=$((i+1))
    done
    echo "    The base is only reached via update-base's ephemeral remote; no standing remote may carry it."
    echo "    fix: .agents/scripts/vault-git-doctor.sh --fix-tracking"
    echo "    (a .base-url fork-pin match is only removed after you confirm — it could be your own fork backup)"
  fi
  if [ -z "$tracking_drift" ] && [ "${#base_remotes[@]}" -eq 0 ] && [ -z "$template_note" ]; then
    echo "✓ tracking: no branch tracks the base template; no standing base-URL remote."
  fi
fi

if [ -n "$FIX_TRACKING" ]; then
  fixed_any=""
  i=0
  for r in ${base_remotes[@]+"${base_remotes[@]}"}; do
    kind="${base_kinds[$i]}"; i=$((i+1))
    url="$(git remote get-url "$r" 2>/dev/null || true)"
    if [ "$kind" = pin ]; then
      # Could be the user's own private fork serving as their backup — never
      # auto-remove. Interactive: ask. Non-interactive (init --yes, cron): skip.
      if [ -t 0 ]; then
        ans=""
        read -r -p "Remote '$r' ($url) matches your .agents/.base-url fork pin — it may be your own fork BACKUP. Remove it? [y/N]: " ans || true
        case "$ans" in [Yy]*) : ;; *) echo "kept: remote '$r' ($url) — not removed."; continue ;; esac
      else
        echo "  ! remote '$r' ($url) matches your .agents/.base-url fork pin — NOT auto-removing (could be your fork backup)." >&2
        echo "  ! re-run .agents/scripts/vault-git-doctor.sh --fix-tracking interactively to decide." >&2
        continue
      fi
    fi
    if [ "$upstream_remote" = "$r" ]; then
      git branch --unset-upstream "$branch" 2>/dev/null \
        || { git config --unset "branch.$branch.remote" 2>/dev/null || true
             git config --unset "branch.$branch.merge"  2>/dev/null || true; }
      echo "fixed: branch '$branch' no longer tracks '$r'."
    fi
    git remote remove "$r"
    fixed_any=1
    echo "fixed: removed base-URL remote '$r' ($url)."
    if [ "$r" = "origin" ]; then
      echo "  'origin' pointed at the base template — reconnect your OWN backup repo with setup/connect-github.sh."
    fi
  done
  if [ -n "$fixed_any" ]; then
    echo "  Base updates still work: update-base.sh uses its own ephemeral remote."
    # Aftermath 1: a legitimate (non-base) 'origin' survived but the branch lost
    # its upstream — re-point tracking so Obsidian Git pushes/pulls the right place.
    if ! git config --get "branch.$branch.remote" >/dev/null 2>&1 \
       && git remote get-url origin >/dev/null 2>&1; then
      if git rev-parse -q --verify "refs/remotes/origin/$branch" >/dev/null 2>&1; then
        git branch --set-upstream-to "origin/$branch" "$branch" >/dev/null 2>&1 \
          && echo "fixed: branch '$branch' now tracks origin/$branch."
      else
        echo "  note: 'origin' has no fetched '$branch' yet — run: git fetch origin && git branch --set-upstream-to origin/$branch"
      fi
    fi
    # Aftermath 2: no remotes left at all → flip Obsidian Git auto-sync back OFF
    # (mirror of connect-github.sh's enable), or a non-technical user gets pull
    # errors on every boot / 10-minute cycle until a real origin exists again.
    if [ -z "$(git remote)" ]; then
      GIT_PLUGIN_DATA="$ROOT/.obsidian/plugins/obsidian-git/data.json"
      if [ -f "$GIT_PLUGIN_DATA" ] && command -v jq >/dev/null 2>&1; then
        jq '.autoSaveInterval = 0 | .autoPullInterval = 0 | .autoPullOnBoot = false
            | .autoBackupAfterFileChange = false | .disablePush = true' \
          "$GIT_PLUGIN_DATA" > "$GIT_PLUGIN_DATA.tmp" && mv "$GIT_PLUGIN_DATA.tmp" "$GIT_PLUGIN_DATA"
        echo "fixed: no remotes remain — turned Obsidian Git auto-sync OFF (connect-github.sh re-enables it with a real origin)."
      else
        echo "  note: no remotes remain — turn Obsidian Git auto-sync off, or run setup/connect-github.sh to connect your own repo."
      fi
    fi
  fi
fi

# ---- check 1b: unbacked vault — no remote at all (report only) -------------
# After a --fix-tracking removes a vault's ONLY remote (e.g. a repaired
# fork-as-base backup), pushes stop by design — with only a one-time console
# message. Nothing else ever re-surfaces "this vault is local-only", so the
# doctor does, on every report run. Informational, NOT drift (no exit 3): a
# deliberately local-only vault is legitimate; the point is that the state is
# seen recurringly, never silent. Skipped for template checkouts.
if [ -n "$REPORT" ] && [ -z "$TEMPLATE_CHECKOUT" ] && [ -z "$(git remote)" ]; then
  echo "· backup: this vault has NO git remote — it exists only on this machine, nothing is"
  echo "    backing it up, and Obsidian Git has nowhere to push. If that's deliberate, fine;"
  echo "    otherwise connect your own repo: setup/connect-github.sh (or /connect-github)."
fi

# ---- check 2: 0-byte, untracked .md stubs missing from the current branch --
# A path qualifies as a deletable stub only when ALL hold: it sits under the
# vault root in an allowed area (never _sensitive/, _local/, raw/, dot-paths),
# is a regular 0-byte .md file OLDER than ~10 minutes, is NOT tracked in the
# index (the #43 race leaves untracked stubs only — a tracked empty file is a
# deliberate placeholder), and does NOT exist on HEAD (the checked-out branch;
# a stale local 'main' in a master-canonical or mid-feature-branch repo must
# never make a legitimately committed file look deletable).
stub_ok() { # path relative to vault root, no leading ./
  local p="$1"
  case "$p" in
    /*|../*|*/../*) return 1 ;;
    _sensitive/*|_local/*|raw/*) return 1 ;;
    .*|*/.*) return 1 ;;
    *.md) : ;;
    *) return 1 ;;
  esac
  [ -f "$p" ] && [ ! -s "$p" ] || return 1
  [ -n "$(find "./$p" -maxdepth 0 -mmin +10 -print 2>/dev/null)" ] || return 1  # too young → skip (./ so a leading-dash name isn't an option)
  git ls-files --error-unmatch -- "$p" >/dev/null 2>&1 && return 1            # tracked → skip
  git cat-file -e "HEAD:$GIT_PREFIX$p" 2>/dev/null && return 1                # on HEAD → skip
  return 0
}

stubs=()
if git rev-parse -q --verify HEAD >/dev/null 2>&1; then
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    p="${f#./}"
    stub_ok "$p" || continue
    stubs+=("$p")
  done < <(find . -mindepth 1 \
             \( -name '.?*' -o -name _sensitive -o -name _local -o -name raw \) -prune \
             -o -type f -name '*.md' -size 0 -mmin +10 -print 2>/dev/null)
elif [ -n "$REPORT" ]; then
  echo "· stubs: repo has no commits yet — skipping the stub scan."
fi

if [ -n "$REPORT" ]; then
  if [ "${#stubs[@]}" -gt 0 ]; then
    drift=1
    echo "✗ stubs: ${#stubs[@]} empty (0-byte), untracked note(s) at paths not on '$branch' — the Obsidian-open-during-rename-merge signature (issue #43):"
    for p in ${stubs[@]+"${stubs[@]}"}; do echo "    $p"; done
    echo "    Content is safe in git; these are working-tree junk. But VERIFY none is a note you deliberately created empty."
    echo "    fix (pass the reviewed paths so the fix deletes exactly this list, not a fresh rescan):"
    printf '    .agents/scripts/vault-git-doctor.sh --fix-stubs'
    for p in ${stubs[@]+"${stubs[@]}"}; do printf ' %q' "$p"; done
    printf '\n'
  elif git rev-parse -q --verify HEAD >/dev/null 2>&1; then
    echo "✓ stubs: no 0-byte untracked notes at paths missing from '$branch'."
  fi
fi

if [ -n "$FIX_STUBS" ]; then
  if [ "${#STUB_PATHS[@]}" -gt 0 ]; then
    # Explicit list = the paths the user reviewed in the report. Each is
    # re-validated against the full stub predicate before deletion, so a path
    # that changed since the report (grew content, got tracked/committed, or
    # was replaced by a fresh new note) is refused rather than deleted.
    for p in ${STUB_PATHS[@]+"${STUB_PATHS[@]}"}; do
      p="${p#./}"
      if stub_ok "$p"; then
        rm -f -- "$p"
        echo "fixed: removed 0-byte stub $p"
      else
        echo "  ! skipped '$p' — no longer a deletable stub (missing, non-empty, tracked, on '$branch', too new, or excluded)." >&2
      fi
    done
  else
    for p in ${stubs[@]+"${stubs[@]}"}; do
      rm -f -- "$p"
      echo "fixed: removed 0-byte stub $p"
    done
  fi
fi

if [ -n "$REPORT" ] && [ "$drift" -ne 0 ]; then exit 3; fi
exit 0
