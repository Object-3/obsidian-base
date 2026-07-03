#!/usr/bin/env bash
# ===========================================================================
# Connect an existing LOCAL vault to GitHub for backup/sync (macOS / Linux)
# ===========================================================================
# Optional, run anytime AFTER setup.sh. Creates a PRIVATE repo under your own
# GitHub account OR an org you belong to, pushes your vault, and sets it as
# 'origin' so Obsidian Git auto-syncs from then on. Idempotent.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "Run this inside your vault folder." >&2; exit 1; }
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib.sh"

ask()  { local var="$1" prompt="$2" def="${3:-}" val; [ -n "${!var:-}" ] && return
         read -r -p "$prompt${def:+ [$def]}: " val || true; printf -v "$var" '%s' "${val:-$def}"; }

# Retry a push once over HTTP/1.1 with a larger post buffer if the first attempt
# fails -- works around a transient "RPC failed; HTTP 400 ... unexpected disconnect
# while reading sideband packet" seen in practice on an otherwise-tiny repo (not a
# size issue; a known HTTP/2 flakiness pattern). The `&&` here is deliberately safe
# under `set -e`: a command's failure before the final `&&`/`||` in a list doesn't
# trigger the trap.
push_with_retry() { # remote branch
  local remote="$1" branch="$2"
  git push -u "$remote" "$branch" && return 0
  say "Push failed (transient HTTP/2 hiccups happen) — retrying once over HTTP/1.1…"
  git -c http.version=HTTP/1.1 -c http.postBuffer=524288000 push -u "$remote" "$branch"
}

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
# Default to the vault's MCP label (obsidian-<slug>), not the bare folder name, so
# the GitHub repo and the assistant-facing connection name match without a manual
# rename later. lib_mcp_label already strips a redundant "obsidian" prefix and is
# idempotent on an already-slugified string, so this reconstructs the same label
# add-vault.sh/setup.sh wired, with no dependency on reading any live MCP config.
DEFAULT_NAME="$(lib_mcp_label "$(basename "$PWD")")"
ask REPO_NAME "Repository name" "$DEFAULT_NAME"
ask VISIBILITY "Visibility (private/public)" "private"

# 3. create + push, set as origin.
if git remote get-url origin >/dev/null 2>&1; then
  say "An 'origin' already exists ($(git remote get-url origin)); pushing to it."
  push_with_retry origin "$(git branch --show-current)"
else
  say "Creating $OWNER/$REPO_NAME ($VISIBILITY) and pushing…"
  if ! gh repo create "$OWNER/$REPO_NAME" --"$VISIBILITY" --source=. --remote=origin --push; then
    say "gh repo create's push failed (the repo itself is very likely already created) — retrying the push…"
    push_with_retry origin "$(git branch --show-current)"
  fi
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
