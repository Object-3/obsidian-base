#!/usr/bin/env bash
# ===========================================================================
# obsidian-base — clean-slate, LOCAL-FIRST onboarding (macOS / Linux)
# ===========================================================================
# Run on a brand-new machine. No GitHub account or prior tools required. It:
#   1. installs prerequisites (Homebrew if missing, git, jq, Obsidian, node)
#   2. creates a LOCAL vault from the base template (no GitHub needed)
#   3. wires the Obsidian MCP into Claude Desktop and/or Claude Code
#   4. opens the vault in Obsidian
# GitHub backup is OPTIONAL and added later with setup/connect-github.sh.
#
# One-command install:
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Object-3/obsidian-base/main/setup/setup.sh)"
#
# Everything is idempotent — safe to re-run. Override defaults with env vars
# (see CONFIG below). Use --yes for a fully non-interactive run.
set -euo pipefail

# ---- config (env-overridable) --------------------------------------------
BASE_REPO_URL="${BASE_REPO_URL:-https://github.com/Object-3/obsidian-base.git}"
VAULT_PARENT="${VAULT_PARENT:-$HOME/Documents}"
VAULT_NAME="${VAULT_NAME:-}"                 # prompted if empty
MCP_CLIENTS="${MCP_CLIENTS:-all}"            # all | desktop | code | codex | both | none | "<space-separated client list>"
MIRROR_SKILLS="${MIRROR_SKILLS:-ask}"        # ask | yes | no — also install skills into user-scope (~/.claude, ~/.agents) so they work in EVERY project
OBSIDIAN_HOST="${OBSIDIAN_HOST:-127.0.0.1}"
OBSIDIAN_PORT="${OBSIDIAN_PORT:-}"           # empty ⇒ auto-allocate the next free port (27124+); set to force a specific HTTPS port
SKIP_PREREQS="${SKIP_PREREQS:-}"             # set=1 to skip installing brew/git/jq/node/Obsidian
NO_OPEN="${NO_OPEN:-}"                        # set=1 to not launch Obsidian at the end
CLAUDE_DESKTOP_CONFIG="${CLAUDE_DESKTOP_CONFIG:-}"   # override Claude Desktop config path (testing)
ASSUME_YES=""; [ "${1:-}" = "--yes" ] && ASSUME_YES=1
CLAUDE_DESKTOP_MISSING=""   # set by configure_mcp when the Claude Desktop app isn't installed
CLAUDE_CODE_MISSING=""      # set by configure_mcp when the Claude Code CLI isn't installed
ASSISTANT_PRESENT=""        # set by configure_mcp when at least one assistant is installed
SKILLS_MIRRORED=""          # set by configure_skill_mirror when the user-scope mirror ran

say()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m  ! %s\033[0m\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }
ask()  { # var prompt default
  local var="$1" prompt="$2" def="${3:-}" val
  [ -n "${!var:-}" ] && return
  if [ -n "$ASSUME_YES" ] || [ ! -t 0 ]; then printf -v "$var" '%s' "$def"; return; fi
  read -r -p "$prompt${def:+ [$def]}: " val || true
  printf -v "$var" '%s' "${val:-$def}"
}

OS="$(uname -s)"
case "$OS" in Darwin) PLATFORM=mac ;; Linux) PLATFORM=linux ;; *) die "unsupported OS: $OS (use setup.ps1 on Windows)";; esac

# ---- 1. prerequisites -----------------------------------------------------
install_prereqs() {
  [ -n "$SKIP_PREREQS" ] && { say "Skipping prerequisite install (SKIP_PREREQS set)."; return; }
  say "Checking prerequisites…"
  if [ "$PLATFORM" = mac ]; then
    if ! have brew; then
      say "Installing Homebrew (you may be prompted for your password)…"
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
      # make brew available in this shell
      [ -x /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"
      [ -x /usr/local/bin/brew ]    && eval "$(/usr/local/bin/brew shellenv)"
    fi
    # node provides npx, which runs the mcp-remote bridge for Claude Desktop / Codex.
    local pkgs=(git jq node) ; for p in "${pkgs[@]}"; do have "$p" || { say "brew install $p"; brew install "$p"; }; done
    have obsidian || [ -d "/Applications/Obsidian.app" ] || { say "Installing Obsidian…"; brew install --cask obsidian; }
  else
    # Linux: best-effort via apt; otherwise ask the user to install manually.
    if have apt-get; then
      sudo apt-get update -y && sudo apt-get install -y git jq curl nodejs npm
    fi
    have npx || warn "Node/npx not found — install Node.js so the mcp-remote bridge (Claude Desktop / Codex) can start. Claude Code's native HTTP needs neither."
    [ -d "$HOME/.local/share/applications" ] || true
    warn "On Linux, install Obsidian from https://obsidian.md/download if it isn't already."
  fi
  have git || die "git is required and could not be installed."
  have jq  || die "jq is required and could not be installed."
}

# ---- 2. create the local vault from the base template ---------------------
# Deliberately does NOT commit yet — the base template's placeholder files
# ({{VAULT_NAME}} etc.) would become the vault's first commit. configure_vault
# (next) personalizes first, THEN makes the one initial commit, so vault
# history starts with real values, not template tokens.
create_vault() {
  ask VAULT_NAME "Name your knowledge vault" "My Knowledge Base"
  local slug; slug="$(printf '%s' "$VAULT_NAME" | tr '[:upper:] ' '[:lower:]-' | tr -cd 'a-z0-9-')"
  VAULT_DIR="$VAULT_PARENT/$slug"
  if [ -d "$VAULT_DIR/.git" ]; then say "Vault already exists at $VAULT_DIR — reusing it."; return; fi
  mkdir -p "$VAULT_PARENT"
  say "Creating your vault at $VAULT_DIR (from the base template)…"
  git clone --depth 1 "$BASE_REPO_URL" "$VAULT_DIR"
  cd "$VAULT_DIR"
  rm -rf .git                       # make it YOURS, not a clone of the base
  # Deliberately NO standing `base` git remote: /update-base adds one ephemerally per fetch
  # and removes it, so `base` can never be mis-picked in Obsidian Git's remote picker and
  # push private notes into the (public) template. Persist a NON-DEFAULT base URL so
  # /update-base still targets a fork/custom base; the public default needs nothing. Clear any
  # .base-url the clone source carried first, so the base is exactly what setup resolved.
  rm -f .agents/.base-url
  if [ "$BASE_REPO_URL" != "https://github.com/Object-3/obsidian-base.git" ]; then
    printf '%s\n' "$BASE_REPO_URL" > .agents/.base-url
  fi
  git init -q -b main 2>/dev/null \
    || { git init -q && git symbolic-ref HEAD refs/heads/main; }   # explicit main; fall back for git < 2.28
  git config core.hooksPath .githooks 2>/dev/null || true
  chmod +x .githooks/* .agents/scripts/*.sh 2>/dev/null || true
  say "Vault is a fresh LOCAL git repo on 'main'. Run /update-base anytime to pull base improvements."
}

# ---- 3. fill profile + sync skills, THEN make the first commit -----------
# Personalizing before committing means the vault's git history starts with
# real values (name/tagline/tag), not the base template's {{PLACEHOLDER}}
# tokens — those would otherwise sit uncommitted on disk indefinitely.
configure_vault() {
  cd "$VAULT_DIR"
  if [ -n "$ASSUME_YES" ]; then
    VAULT_NAME="$VAULT_NAME" PRIMARY_TAG="${PRIMARY_TAG:-kb}" .agents/scripts/init-vault.sh --yes || warn "init-vault skipped"
  else
    .agents/scripts/init-vault.sh || warn "init-vault skipped (run it later)"
  fi
  # Guard: if personalization left {{PLACEHOLDER}} tokens behind (init-vault failed or was
  # skipped), don't silently commit template tokens as the vault's first commit and report
  # success — surface it so the user re-runs init-vault instead of trusting a false "Done".
  if grep -lq '{{[A-Z_]*}}' .agents/vault-profile.md index.md log.md llms.txt README.md 2>/dev/null; then
    warn "vault still has {{PLACEHOLDER}} tokens — personalization didn't complete; re-run '.agents/scripts/init-vault.sh', then commit again."
  fi
  git add -A
  git -c user.name="${GIT_AUTHOR_NAME:-Vault Owner}" -c user.email="${GIT_AUTHOR_EMAIL:-vault@localhost}" \
      commit -q -m "Initial vault from obsidian-base"
}

# ---- 3b. (optional) mirror skills into user-scope ------------------------
# Opt-in: also install the vendored portable skills into the user's CLI tools so
# they work in EVERY project, not just this vault. Additive and reversible; never
# enabled silently. Uses --mirror-only (no network re-fetch — the committed set is
# already current in a fresh clone).
configure_skill_mirror() {
  cd "$VAULT_DIR"
  local choice="$MIRROR_SKILLS"
  if [ "$choice" = ask ]; then
    if [ -n "$ASSUME_YES" ] || [ ! -t 0 ]; then
      choice=no   # opt-in: never enable non-interactively unless MIRROR_SKILLS=yes was set explicitly
    else
      local ans=""; read -r -p "Make these skills available in ALL your projects, not just this vault? [y/N]: " ans || true
      case "$ans" in [Yy]*) choice=yes ;; *) choice=no ;; esac
    fi
  fi
  [ "$choice" = yes ] || { say "Skills stay scoped to this vault (run the /install-skills skill anytime to change that)."; return; }
  say "Installing skills into your user-scope (~/.claude/skills, ~/.agents/skills)…"
  if .agents/scripts/sync-skills.sh --mirror-only; then SKILLS_MIRRORED=1
  else warn "skill mirror failed — you can run it later with the /install-skills skill."; fi
}

# ---- 4. provision Obsidian plugins + REST API key ------------------------
# Delegates to setup/lib.sh (sourced after create_vault). Allocates a free port
# unless the user forced one via OBSIDIAN_PORT, so a vault created on a machine
# that already has one lands on its own port instead of colliding.
provision_plugins() {
  [ -n "$OBSIDIAN_PORT" ] || OBSIDIAN_PORT="$(lib_alloc_free_port)"
  lib_provision_plugins "$VAULT_DIR" "$OBSIDIAN_PORT"
}

# ---- 5. wire the Obsidian MCP into the local AI clients -------------------
# One vault-named server (obsidian-<slug>) appended into every selected client
# via the lib adapter registry (Claude Desktop, Claude Code, Codex CLI).
configure_mcp() {
  [ "$MCP_CLIENTS" = none ] && return
  have npx || warn "Node/npx not found — the mcp-remote bridge (Claude Desktop / Codex) may not start; Claude Code's native HTTP needs neither."
  local key; key="$(cat "$VAULT_DIR/.obsidian/.rest-api-key" 2>/dev/null || echo "")"
  [ -n "$key" ] || { warn "no REST API key; skipping MCP wiring"; return; }
  local label; label="$(lib_mcp_label "$VAULT_NAME")"

  # Assistant-presence detection drives the final "no assistant installed" note.
  if [ "$PLATFORM" = mac ]; then
    { [ -d "/Applications/Claude.app" ] || [ -d "$HOME/Applications/Claude.app" ]; } \
      && ASSISTANT_PRESENT=1 || CLAUDE_DESKTOP_MISSING=1
  else
    have claude-desktop && ASSISTANT_PRESENT=1 || CLAUDE_DESKTOP_MISSING=1
  fi
  have claude && ASSISTANT_PRESENT=1 || CLAUDE_CODE_MISSING=1
  have codex  && ASSISTANT_PRESENT=1 || true

  # Map the MCP_CLIENTS selector onto concrete adapter names.
  local sel; sel="$(lib_select_clients "$MCP_CLIENTS")"
  [ -n "$sel" ] || return
  say "Wiring the vault MCP ($label, port $OBSIDIAN_PORT) into: $sel"
  MCP_ALL_CLIENTS="$sel" for_each_client wire "$label" "$OBSIDIAN_PORT" "$key"
}

open_vault() {
  [ -n "$NO_OPEN" ] && { say "Skipping Obsidian launch (NO_OPEN set)."; return; }
  say "Opening your vault in Obsidian…"
  if [ "$PLATFORM" = mac ]; then open -a Obsidian "$VAULT_DIR" 2>/dev/null || open "obsidian://open?path=$(python3 -c 'import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))' "$VAULT_DIR")" 2>/dev/null || true; fi
}

# ---- run ------------------------------------------------------------------
install_prereqs
create_vault
# The base template (incl. setup/lib.sh) is on disk only after create_vault
# clones it — safe to source here for both piped (curl|bash) and local runs.
# shellcheck disable=SC1091
. "$VAULT_DIR/setup/lib.sh"
configure_vault
configure_skill_mirror
provision_plugins
configure_mcp
open_vault

printf '\n\033[1;32m✓ Done.\033[0m Your vault: %s\n\n' "$VAULT_DIR"

# If the user opted into the mirror, tell them their skills are now machine-wide.
if [ -n "$SKILLS_MIRRORED" ]; then
  printf '\033[1;32m✓ Skills installed to your user-scope.\033[0m They now work in every project on this\n'
  printf 'machine, not just this vault. Manage them anytime with the /install-skills skill;\n'
  printf 'they stay even if you later offboard the vault.\n\n'
fi

# If NO AI assistant is installed, the MCP we just wired has nothing to load into.
# (If at least one is present we stay quiet — the config is live for it.)
if [ -z "$ASSISTANT_PRESENT" ]; then
  printf '\033[1;33mNo AI assistant is installed yet.\033[0m The vault is ready and the\n'
  printf 'connection is pre-wired, but it only activates once the assistant is on this machine:\n'
  [ -n "$CLAUDE_DESKTOP_MISSING" ] && printf '  • Claude Desktop:  https://claude.ai/download\n'
  [ -n "$CLAUDE_CODE_MISSING" ]    && printf '  • Claude Code:     https://claude.com/claude-code\n'
  printf 'Install it, then come back to the steps below.\n\n'
fi

cat <<EOF
Next (one-time, in Obsidian):
  - When Obsidian opens, click "Trust author and enable plugins" if prompted.
    This is what switches the Local REST API on — the bridge your assistant talks to.
    Until you do this, the assistant cannot read or write the vault.

Then connect your assistant to the vault:
  - The connection (MCP) was configured during setup, but Claude only loads it when a
    session STARTS. So you must begin a NEW session before it works:
      • Claude Desktop: fully quit and reopen the app.
      • Claude Code:    start a new session (the running one won't see it).
  - To confirm it worked, ask your assistant: "list the files in my vault."
    If it lists them, the handshake is complete.

Optional, whenever you want cloud backup / sync (private repo under your account or an org):
  cd "$VAULT_DIR" && ./setup/connect-github.sh

Pull future base improvements anytime:
  cd "$VAULT_DIR" && .agents/scripts/update-base.sh
EOF
