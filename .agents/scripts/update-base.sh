#!/usr/bin/env bash
# Pull the latest BASE LAYER (engine) from the upstream base repo into THIS vault,
# WITHOUT touching your notes, vault-profile, or content.
#
# GIT-NATIVE: every vault is already a git repo (Obsidian Git needs one), so we use a
# short-lived git remote instead of downloading tarballs. That makes this host-agnostic
# (any git URL, not just GitHub), pinnable to a tag/SHA, and able to prune files the
# base removed. It overlays ONLY the base-owned engine paths below.
#
# What it refreshes (base-owned engine only):
#   AGENTS.md, CLAUDE.md, .gitignore, .gitattributes, .agents/SKILLS.md,
#   .agents/skill-sources.json, .agents/scripts/* (incl. dream-scan.sh + test-dream-smoke.sh),
#   .claude/hooks/* (incl. dream-if-stale.sh), .claude/settings.json,
#   .githooks/*, setup/*, SETUP.md, EVERY base-AUTHORED skill under .agents/skills/
#   (auto-discovered from the fetched base tree — never a hand-kept list; see the
#   "base-authored skills" derivation below; this is how vault-dream propagates), and the
#   one base-owned Obsidian snippet .obsidian/snippets/hide-engine-files.css
#
# What it NEVER touches (yours):
#   your notes, .agents/vault-profile.md, .agents/skill-sources.local.json, the VENDORED
#   skills/agents (those come via sync-skills), your own hand-authored skills, index.md,
#   log.md, hot.md, .agents/dream-state (per-vault backbone/state — overlaying the watermark
#   would reset your dream progress; init-vault seeds them), llms.txt, README.md, docs/,
#   plans/, raw/, and all of .obsidian/ EXCEPT the single base-owned snippet above (your own
#   snippets, workspace, graph, appearance, and which snippets you've enabled all stay yours)
#
# Config (override via env, or pin persistently in .agents/.base-{url,ref}):
#   BASE_REPO=Object-3/obsidian-base                  # owner/name (GitHub shorthand)
#   BASE_REPO_URL=https://github.com/Object-3/obsidian-base.git   # full URL (any host)
#   BASE_REF=main | v1.2.0 | <sha>                    # branch, tag, or commit to pull
#   .agents/.base-url                                 # persisted base URL (fork/custom base)
#
# The fetch remote is EPHEMERAL: this script adds a dedicated `base-ephemeral` remote only for
# the fetch and removes it on exit (see below) — it never touches a `base` remote you keep.
# Nothing base-related is left standing, so a fork's/custom base's URL is remembered in the
# tracked .agents/.base-url file instead (written by setup only when a non-default URL is used).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"; cd "$ROOT"

# Base repo URL precedence: BASE_REPO_URL env → BASE_REPO env (owner/name shorthand)
# → persisted .agents/.base-url → an already-configured `base` remote (legacy vaults that
# still keep a standing one) → public template. This is what lets a fork/custom base survive
# now that the `base` remote is ephemeral rather than standing.
if [ -n "${BASE_REPO_URL:-}" ]; then
  :
elif [ -n "${BASE_REPO:-}" ]; then
  BASE_REPO_URL="https://github.com/${BASE_REPO}.git"
elif [ -s .agents/.base-url ] && BASE_REPO_URL="$(tr -d '[:space:]' <.agents/.base-url)" && [ -n "$BASE_REPO_URL" ]; then
  :   # persisted fork/custom base URL (a blank/whitespace-only file falls through)
elif BASE_REPO_URL="$(git remote get-url base 2>/dev/null)" && [ -n "$BASE_REPO_URL" ]; then
  :   # legacy vault with a standing `base` remote — honor its URL
else
  BASE_REPO_URL="https://github.com/Object-3/obsidian-base.git"
fi
BASE_REF="${BASE_REF:-$( [ -f .agents/.base-ref ] && tr -d '[:space:]' <.agents/.base-ref || echo main )}"

command -v git >/dev/null || { echo "git is required" >&2; exit 1; }
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "not a git repo: $ROOT" >&2; exit 1; }

# The ONLY paths this overlays. Whole files and whole directories (recursive).
PATHS=(
  "AGENTS.md"
  "CLAUDE.md"
  ".gitignore"
  ".gitattributes"
  ".agents/SKILLS.md"
  ".agents/skill-sources.json"
  ".agents/scripts"
  ".claude/hooks"
  ".claude/settings.json"
  ".githooks"
  # NOTE: base-AUTHORED skills under .agents/skills/ are deliberately NOT listed here.
  # They're auto-discovered from the fetched base tree and appended to PATHS below
  # (search "base-authored skills"), so adding a new base skill (e.g. vault-dream) never
  # needs an edit here.
  "setup"
  "SETUP.md"
  # The one base-owned Obsidian snippet: the rule for which engine files to hide from
  # the explorer is engine, not content, so it stays in sync. Targeted at the exact
  # FILE (not .obsidian/snippets/) so your own snippets and the rest of .obsidian/ are
  # left untouched. A vault that wants extra hides adds a separate *.local.css snippet.
  ".obsidian/snippets/hide-engine-files.css"
)

# The fetch remote is EPHEMERAL. /update-base needs a remote to fetch from, but leaving one
# STANDING is a footgun: once `origin` exists a user could pick it in Obsidian Git's remote
# picker and push PRIVATE vault content into the (public) template repo. So we use a DEDICATED
# name this script owns end to end — `base-ephemeral` — never the bare `base`:
#   * any stray `base-ephemeral` from a crashed/SIGKILLed prior run is reclaimed at the START
#     of every run, so a hard-kill orphan can never be silently promoted to a permanent remote;
#   * it's added only for this fetch; and
#   * the trap removes it on exit (normal exit, `set -e` error, and SIGINT/SIGTERM).
# A user's or legacy vault's own `base` remote is NEVER added, removed, or repointed here — its
# URL is only READ for the precedence chain above — so we can't clobber a remote someone kept.
# (`base-ephemeral` is a reserved name this script owns; don't use it for your own remote.)
EPHEMERAL_REMOTE="base-ephemeral"
cleanup_base_remote() { git remote remove "$EPHEMERAL_REMOTE" 2>/dev/null || true; }
trap cleanup_base_remote EXIT
git remote remove "$EPHEMERAL_REMOTE" 2>/dev/null || true   # reclaim a crash/SIGKILL orphan
git remote add "$EPHEMERAL_REMOTE" "$BASE_REPO_URL"
echo "Fetching base layer from $BASE_REPO_URL @ $BASE_REF ..."
git fetch -q --depth 1 "$EPHEMERAL_REMOTE" "$BASE_REF" || {
  echo "Could not fetch $BASE_REPO_URL @ $BASE_REF. Set BASE_REPO_URL / BASE_REF and retry." >&2; exit 1; }

# base-authored skills — DERIVE them, don't hand-maintain a list.
# A hardcoded list silently drifts every time a base skill is added (the add-vault /
# install-mcp-quick-orient miss that motivated this). Instead we compute it from the
# fetched base tree: a skill dir under .agents/skills/ that the base did NOT vendor —
# i.e. is absent from the base's committed lock (.agents/skill-sources.lock.json's
# .skills[]) — is base-authored, so it propagates. Vendored skills arrive via
# sync-skills, never here; overlaying one could clobber a fork's pinned/overridden
# copy, so we must not. Correctness rests on the base committing its lock alongside
# its vendored skills (sync-skills always rewrites both together). If the lock is
# missing/unparseable — or jq is absent — we can't tell authored from vendored, so we
# skip skill overlay this run and warn, rather than risk clobbering a vendored skill.
if ! command -v jq >/dev/null 2>&1; then
  echo "  ! jq not found; skipping base-authored skill sync this run (install jq — sync-skills needs it too)" >&2
elif base_lock="$(git show FETCH_HEAD:.agents/skill-sources.lock.json 2>/dev/null)" \
     && base_vendored="$(printf '%s' "$base_lock" | jq -r '.skills[]?' 2>/dev/null)"; then
  while IFS= read -r skdir; do
    [ -n "$skdir" ] && PATHS+=(".agents/skills/$skdir")
  done < <(comm -23 \
            <(git ls-tree -r --name-only FETCH_HEAD -- .agents/skills 2>/dev/null \
                | sed -n 's#^\.agents/skills/\([^/]*\)/SKILL\.md$#\1#p' | sort -u) \
            <(printf '%s\n' "$base_vendored" | sed '/^$/d' | sort -u))
else
  echo "  ! base has no readable/parseable .agents/skill-sources.lock.json; skipping base-authored skill sync this run" >&2
fi

# Warn about uncommitted local edits to base-owned files (they'll be overwritten).
for p in "${PATHS[@]}"; do
  if ! git diff --quiet -- "$p" 2>/dev/null; then
    echo "  ! local uncommitted changes under '$p' will be overwritten (they're in your git history)" >&2
  fi
done

changed=0; pruned=0
for p in "${PATHS[@]}"; do
  # Skip paths the base doesn't have (nothing to sync).
  git ls-tree -r --name-only FETCH_HEAD -- "$p" 2>/dev/null | grep -q . || continue

  # Prune: delete tracked files under this path that no longer exist in the base.
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    git rm -q --ignore-unmatch -- "$f" >/dev/null 2>&1 && { echo "  pruned: $f"; pruned=$((pruned+1)); }
  done < <(comm -23 \
            <(git ls-files -- "$p" | sort) \
            <(git ls-tree -r --name-only FETCH_HEAD -- "$p" | sort))

  # Overlay base content — but only if it actually differs from current HEAD, so a
  # no-op run honestly reports "up to date" instead of re-staging identical files.
  if git diff --quiet HEAD FETCH_HEAD -- "$p"; then
    continue
  fi
  git checkout FETCH_HEAD -- "$p"
  echo "  synced: $p"; changed=$((changed+1))
done

# Keep scripts/hooks executable.
chmod +x .agents/scripts/*.sh .claude/hooks/*.sh 2>/dev/null || true

if [ "$changed" -eq 0 ] && [ "$pruned" -eq 0 ]; then
  echo "Already up to date with $BASE_REPO_URL @ $BASE_REF."
else
  echo "Updated $changed path(s), pruned $pruned file(s). Changes are STAGED, not committed."
  echo "Next:"
  echo "  1. Run '.agents/scripts/sync-skills.sh' (skill-sources.json may have changed)."
  if git remote get-url origin >/dev/null 2>&1; then
    echo "  2. This is an ENGINE change — commit on a branch and open a PR (don't let the"
    echo "     live auto-syncing vault sweep a half-applied engine update onto main)."
  else
    echo "  2. No 'origin' remote yet — there's nothing to open a PR against."
    echo "     Commit directly: git add -A && git commit -m 'Update base layer from obsidian-base'."
    echo "     (Once you connect GitHub with connect-github.sh, future updates can go through"
    echo "     a branch + PR if you want that review step.)"
  fi
  echo "Note: your '.agents/skill-sources.local.json' (custom sources) was NOT touched."
fi

# If this machine has the user-scope skill mirror, those copies don't refresh
# themselves. OFFER a refresh (consent-gated — we never write user-scope from here).
MIRROR_MANIFEST="${MIRROR_MANIFEST:-${XDG_CONFIG_HOME:-$HOME/.config}/obsidian-base/skill-mirror.json}"
if [ -f "$MIRROR_MANIFEST" ]; then
  echo
  echo "Your global skills (user-scope mirror) may now be out of date. To refresh them:"
  echo "  .agents/scripts/sync-skills.sh --mirror-only   (or run the /install-skills skill)"
fi
