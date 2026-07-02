#!/usr/bin/env bash
# ===========================================================================
# Connect an existing LOCAL vault to GitHub for backup/sync (macOS / Linux)
# ===========================================================================
# Optional, run anytime AFTER setup.sh. Creates a PRIVATE repo under your own
# GitHub account OR an org you belong to, pushes your vault, and sets it as
# 'origin' so Obsidian Git auto-syncs from then on. Idempotent.
set -euo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "Run this inside your vault folder." >&2; exit 1; }

say()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }
ask()  { local var="$1" prompt="$2" def="${3:-}" val; [ -n "${!var:-}" ] && return
         read -r -p "$prompt${def:+ [$def]}: " val || true; printf -v "$var" '%s' "${val:-$def}"; }

# 1. gh CLI present + authenticated (device-code flow opens your browser).
if ! have gh; then
  say "Installing GitHub CLI…"
  if have brew; then brew install gh
  elif have apt-get; then sudo apt-get install -y gh
  else echo "Install GitHub CLI from https://cli.github.com then re-run." >&2; exit 1; fi
fi
gh auth status >/dev/null 2>&1 || { say "Sign in to GitHub (a code will open in your browser)…"; gh auth login; }

# 2. where should the repo live: your account, or an org you own?
DEFAULT_OWNER="$(gh api user --jq .login 2>/dev/null || echo "")"
echo "Repo can live under your account or any org you belong to:"
gh api user/orgs --jq '.[].login' 2>/dev/null | sed 's/^/  - (org) /' || true
ask OWNER "GitHub owner (your username or an org)" "$DEFAULT_OWNER"
DEFAULT_NAME="$(basename "$PWD")"
ask REPO_NAME "Repository name" "$DEFAULT_NAME"
ask VISIBILITY "Visibility (private/public)" "private"

# 3. create + push, set as origin.
if git remote get-url origin >/dev/null 2>&1; then
  say "An 'origin' already exists ($(git remote get-url origin)); pushing to it."
  git push -u origin "$(git branch --show-current)"
else
  say "Creating $OWNER/$REPO_NAME ($VISIBILITY) and pushing…"
  gh repo create "$OWNER/$REPO_NAME" --"$VISIBILITY" --source=. --remote=origin --push
fi

# 4. 'origin' now exists, so it's safe to turn on Obsidian Git's auto-sync.
#    setup.sh/add-vault.sh ship it OFF (autoSaveInterval/autoPullInterval 0,
#    autoPullOnBoot/autoBackupAfterFileChange false, disablePush true) so a
#    vault with no 'origin' yet never auto-pushes. (The 'base' remote is no longer
#    standing — /update-base adds it only per-fetch and removes it — so it can't be
#    offered as an auto-sync target and leak private notes into the public template.)
GIT_PLUGIN_DATA=".obsidian/plugins/obsidian-git/data.json"
if [ -f "$GIT_PLUGIN_DATA" ] && have jq; then
  jq '.autoSaveInterval = 10 | .autoPullInterval = 10 | .autoPullOnBoot = true
      | .autoBackupAfterFileChange = true | .disablePush = false' \
    "$GIT_PLUGIN_DATA" > "$GIT_PLUGIN_DATA.tmp" && mv "$GIT_PLUGIN_DATA.tmp" "$GIT_PLUGIN_DATA"
  say "Enabled Obsidian Git auto-sync (commit + pull + push) now that 'origin' is connected."
fi

printf '\n\033[1;32m✓ Backed up.\033[0m %s/%s — Obsidian Git will keep it synced.\n' "$OWNER" "$REPO_NAME"
echo "Base updates still work: .agents/scripts/update-base.sh manages its own ephemeral remote."
