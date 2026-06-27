#!/usr/bin/env bash
# Pull the latest BASE LAYER (engine) from the upstream base repo into THIS vault,
# WITHOUT touching your notes, vault-profile, or content.
#
# GIT-NATIVE: every vault is already a git repo (Obsidian Git needs one), so we use a
# `base` git remote instead of downloading tarballs. That makes this host-agnostic
# (any git URL, not just GitHub), pinnable to a tag/SHA, and able to prune files the
# base removed. It overlays ONLY the base-owned engine paths below.
#
# What it refreshes (base-owned engine only):
#   AGENTS.md, CLAUDE.md, .gitignore, .gitattributes, .agents/SKILLS.md,
#   .agents/skill-sources.json, .agents/scripts/*, .claude/hooks/*, .claude/settings.json,
#   and the base-AUTHORED skills .agents/skills/{update-base,setup-vault}
#
# What it NEVER touches (yours):
#   your notes, .agents/vault-profile.md, .agents/skill-sources.local.json, the VENDORED
#   skills/agents (those come via sync-skills), your own hand-authored skills, index.md,
#   log.md, llms.txt, README.md, docs/, plans/, raw/, .obsidian/
#
# Config (override via env, or pin persistently in .agents/.base-ref):
#   BASE_REPO=Object-3/obsidian-base                  # owner/name (GitHub shorthand)
#   BASE_REPO_URL=https://github.com/Object-3/obsidian-base.git   # full URL (any host)
#   BASE_REF=main | v1.2.0 | <sha>                    # branch, tag, or commit to pull
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"; cd "$ROOT"

BASE_REPO_URL="${BASE_REPO_URL:-https://github.com/${BASE_REPO:-Object-3/obsidian-base}.git}"
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
  # Base-AUTHORED skills (hand-written here, not vendored from an upstream), so
  # improvements to them propagate. Vendored skills come via sync-skills, not here.
  ".agents/skills/update-base"
  ".agents/skills/setup-vault"
)

# Wire up / refresh the `base` remote, then fetch just the wanted ref (shallow).
if git remote get-url base >/dev/null 2>&1; then git remote set-url base "$BASE_REPO_URL"
else git remote add base "$BASE_REPO_URL"; fi
echo "Fetching base layer from $BASE_REPO_URL @ $BASE_REF ..."
git fetch -q --depth 1 base "$BASE_REF" || {
  echo "Could not fetch $BASE_REPO_URL @ $BASE_REF. Set BASE_REPO_URL / BASE_REF and retry." >&2; exit 1; }

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

  # Overlay base content into working tree + index.
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
  echo "  2. This is an ENGINE change — commit on a branch and open a PR (don't let the"
  echo "     live auto-syncing vault sweep a half-applied engine update onto main)."
  echo "Note: your '.agents/skill-sources.local.json' (custom sources) was NOT touched."
fi
