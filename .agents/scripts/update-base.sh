#!/usr/bin/env bash
# Pull the latest BASE LAYER (engine) from the upstream base vault into this repo,
# WITHOUT touching your notes, vault-profile, or content. Works for any downstream —
# a fork, a "Use this template" instance, or a plain clone — no git-merge needed.
#
# What it refreshes (base-owned engine only):
#   AGENTS.md, CLAUDE.md, .gitignore, .agents/SKILLS.md,
#   .agents/scripts/*.sh, .claude/hooks/*.sh, .claude/settings.json
#
# What it NEVER touches (yours):
#   your notes, .agents/vault-profile.md, .agents/skill-sources.json, the vendored
#   skills, index.md, log.md, llms.txt, README.md, docs/, plans/, raw/, .obsidian/
#
# Config (override via env):
#   BASE_REPO=Object-3/obsidian-base   BASE_REF=main   .agents/scripts/update-base.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
BASE_REPO="${BASE_REPO:-Object-3/obsidian-base}"
BASE_REF="${BASE_REF:-main}"

command -v curl >/dev/null || { echo "curl required" >&2; exit 1; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

echo "Fetching base layer from $BASE_REPO@$BASE_REF ..."
if ! curl -fsSL "https://codeload.github.com/$BASE_REPO/tar.gz/refs/heads/$BASE_REF" -o "$TMP/base.tgz"; then
  echo "Could not download $BASE_REPO@$BASE_REF. Set BASE_REPO / BASE_REF and retry." >&2
  exit 1
fi
mkdir -p "$TMP/base"
tar -xzf "$TMP/base.tgz" -C "$TMP/base" --strip-components=1

# Files (whole) and globs to refresh.
PATHS=(
  "AGENTS.md"
  "CLAUDE.md"
  ".gitignore"
  ".agents/SKILLS.md"
  ".claude/settings.json"
)
GLOBS=(
  ".agents/scripts"
  ".claude/hooks"
)

changed=0
copy_one() { # relpath
  local rel="$1" src="$TMP/base/$1"
  [ -e "$src" ] || return 0
  mkdir -p "$(dirname "$rel")"
  if [ ! -e "$rel" ] || ! cmp -s "$src" "$rel"; then
    cp "$src" "$rel"; echo "  updated: $rel"; changed=$((changed+1))
  fi
}
for p in "${PATHS[@]}"; do copy_one "$p"; done
for g in "${GLOBS[@]}"; do
  if [ -d "$TMP/base/$g" ]; then
    while IFS= read -r f; do copy_one "${f#"$TMP/base/"}"; done \
      < <(find "$TMP/base/$g" -type f)
  fi
done
chmod +x .agents/scripts/*.sh .claude/hooks/*.sh 2>/dev/null || true

if [ "$changed" -eq 0 ]; then
  echo "Already up to date with $BASE_REPO@$BASE_REF."
else
  echo "Updated $changed base file(s)."
  echo "Next: run '.agents/scripts/sync-skills.sh' (scripts may have changed), then commit."
  echo "Note: your .agents/skill-sources.json was NOT changed. If the base added new"
  echo "      skill SOURCES you want, compare it against the base copy and merge manually."
fi
