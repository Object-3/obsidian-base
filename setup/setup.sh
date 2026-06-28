#!/usr/bin/env bash
# ===========================================================================
# obsidian-base — clean-slate, LOCAL-FIRST onboarding (macOS / Linux)
# ===========================================================================
# Run on a brand-new machine. No GitHub account or prior tools required. It:
#   1. installs prerequisites (Homebrew if missing, git, jq, Obsidian, uv)
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
MCP_CLIENTS="${MCP_CLIENTS:-both}"           # desktop | code | both | none
OBSIDIAN_HOST="${OBSIDIAN_HOST:-127.0.0.1}"
OBSIDIAN_PORT="${OBSIDIAN_PORT:-27124}"
SKIP_PREREQS="${SKIP_PREREQS:-}"             # set=1 to skip installing brew/git/jq/uv/Obsidian
NO_OPEN="${NO_OPEN:-}"                        # set=1 to not launch Obsidian at the end
CLAUDE_DESKTOP_CONFIG="${CLAUDE_DESKTOP_CONFIG:-}"   # override Claude Desktop config path (testing)
ASSUME_YES=""; [ "${1:-}" = "--yes" ] && ASSUME_YES=1

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
    local pkgs=(git jq uv) ; for p in "${pkgs[@]}"; do have "$p" || { say "brew install $p"; brew install "$p"; }; done
    have obsidian || [ -d "/Applications/Obsidian.app" ] || { say "Installing Obsidian…"; brew install --cask obsidian; }
  else
    # Linux: best-effort via apt; otherwise ask the user to install manually.
    if have apt-get; then
      sudo apt-get update -y && sudo apt-get install -y git jq curl
    fi
    have uv || curl -LsSf https://astral.sh/uv/install.sh | sh
    [ -d "$HOME/.local/share/applications" ] || true
    warn "On Linux, install Obsidian from https://obsidian.md/download if it isn't already."
  fi
  have git || die "git is required and could not be installed."
  have jq  || die "jq is required and could not be installed."
}

# ---- 2. create the local vault from the base template ---------------------
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
  git init -q && git add -A
  git -c user.name="${GIT_AUTHOR_NAME:-Vault Owner}" -c user.email="${GIT_AUTHOR_EMAIL:-vault@localhost}" \
      commit -q -m "Initial vault from obsidian-base"
  git remote add base "$BASE_REPO_URL"   # for /update-base (public; no auth needed)
  git config core.hooksPath .githooks 2>/dev/null || true
  chmod +x .githooks/* .agents/scripts/*.sh 2>/dev/null || true
  say "Vault is a fresh LOCAL git repo. 'base' remote set for future updates."
}

# ---- 3. fill profile + sync skills ---------------------------------------
configure_vault() {
  cd "$VAULT_DIR"
  if [ -n "$ASSUME_YES" ]; then
    VAULT_NAME="$VAULT_NAME" PRIMARY_TAG="${PRIMARY_TAG:-kb}" .agents/scripts/init-vault.sh --yes || warn "init-vault skipped"
  else
    .agents/scripts/init-vault.sh || warn "init-vault skipped (run it later)"
  fi
}

# ---- 4. provision Obsidian plugins + REST API key ------------------------
gh_release_dl() { # repo destdir  (downloads main.js, manifest.json, styles.css from latest release)
  local repo="$1" dest="$2" base tag
  mkdir -p "$dest"
  tag="$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest" | jq -r .tag_name)"
  [ -n "$tag" ] && [ "$tag" != null ] || { warn "no release for $repo"; return 1; }
  base="https://github.com/$repo/releases/download/$tag"
  curl -fsSL "$base/manifest.json" -o "$dest/manifest.json" || return 1
  curl -fsSL "$base/main.js"       -o "$dest/main.js"       || return 1
  curl -fsSL "$base/styles.css"    -o "$dest/styles.css" 2>/dev/null || true
}

provision_plugins() {
  cd "$VAULT_DIR"
  say "Installing Obsidian plugins (Git + Local REST API)…"
  gh_release_dl "Vinzent03/obsidian-git" ".obsidian/plugins/obsidian-git" || warn "obsidian-git download failed"
  gh_release_dl "coddingtonbear/obsidian-local-rest-api" ".obsidian/plugins/obsidian-local-rest-api" || warn "local-rest-api download failed"
  # generate a REST API key and pre-seed the plugin so the MCP can auth without manual copy
  API_KEY="$(openssl rand -hex 32 2>/dev/null || head -c 32 /dev/urandom | xxd -p | tr -d '\n')"
  printf '%s' "$API_KEY" > "$VAULT_DIR/.obsidian/.rest-api-key"   # gitignored; for our reference
  local lr=".obsidian/plugins/obsidian-local-rest-api/data.json"
  if [ -f ".obsidian/plugins/obsidian-local-rest-api/main.js" ]; then
    jq -n --arg k "$API_KEY" '{apiKey:$k, crypto:null, port: 27124, insecurePort: 27123, enableInsecureServer:true, bindingHost:"127.0.0.1"}' > "$lr"
  fi
  # enable community plugins
  jq -n '["obsidian-local-rest-api","obsidian-git"]' > .obsidian/community-plugins.json
}

# ---- 5. wire the Obsidian MCP into Claude Desktop and/or Claude Code ------
configure_mcp() {
  [ "$MCP_CLIENTS" = none ] && return
  have uv || warn "uv not found — the MCP runtime (uvx mcp-obsidian) may not start."
  local key; key="$(cat "$VAULT_DIR/.obsidian/.rest-api-key" 2>/dev/null || echo "")"
  [ -n "$key" ] || { warn "no REST API key; skipping MCP wiring"; return; }

  if [ "$MCP_CLIENTS" = desktop ] || [ "$MCP_CLIENTS" = both ]; then
    local cfg="$CLAUDE_DESKTOP_CONFIG"
    if [ -z "$cfg" ]; then
      [ "$PLATFORM" = mac ] && cfg="$HOME/Library/Application Support/Claude/claude_desktop_config.json" \
                            || cfg="$HOME/.config/Claude/claude_desktop_config.json"
    fi
    mkdir -p "$(dirname "$cfg")"; [ -f "$cfg" ] || echo '{}' > "$cfg"
    say "Wiring MCP into Claude Desktop…"
    jq --arg k "$key" --arg h "$OBSIDIAN_HOST" --arg p "$OBSIDIAN_PORT" '
      .mcpServers = (.mcpServers // {}) |
      .mcpServers["mcp-obsidian"] = {command:"uvx", args:["mcp-obsidian"],
        env:{OBSIDIAN_API_KEY:$k, OBSIDIAN_HOST:$h, OBSIDIAN_PORT:$p}}' \
      "$cfg" > "$cfg.tmp" && mv "$cfg.tmp" "$cfg"
  fi
  if [ "$MCP_CLIENTS" = code ] || [ "$MCP_CLIENTS" = both ]; then
    if have claude; then
      say "Wiring MCP into Claude Code…"
      # --scope user → available across ALL the user's projects, not just this
      # directory (default scope is "local"). The vault is a consume-from-anywhere
      # knowledge base, so the MCP must be reachable from every Claude Code session.
      claude mcp add mcp-obsidian --scope user --env OBSIDIAN_API_KEY="$key" --env OBSIDIAN_HOST="$OBSIDIAN_HOST" \
        --env OBSIDIAN_PORT="$OBSIDIAN_PORT" -- uvx mcp-obsidian 2>/dev/null \
        || warn "couldn't add MCP to Claude Code (add it manually: see SETUP.md)"
    else
      warn "Claude Code CLI not found; skipping (install it, then re-run with MCP_CLIENTS=code)."
    fi
  fi
}

open_vault() {
  [ -n "$NO_OPEN" ] && { say "Skipping Obsidian launch (NO_OPEN set)."; return; }
  say "Opening your vault in Obsidian…"
  if [ "$PLATFORM" = mac ]; then open -a Obsidian "$VAULT_DIR" 2>/dev/null || open "obsidian://open?path=$(python3 -c 'import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))' "$VAULT_DIR")" 2>/dev/null || true; fi
}

# ---- run ------------------------------------------------------------------
install_prereqs
create_vault
configure_vault
provision_plugins
configure_mcp
open_vault

printf '\n\033[1;32m✓ Done.\033[0m Your vault: %s\n\n' "$VAULT_DIR"
cat <<EOF
Next (one-time, in Obsidian):
  - When Obsidian opens, click "Trust author and enable plugins" if prompted.
  - That's it: start writing notes. Your agent can read/write the vault via MCP.

Optional, whenever you want cloud backup / sync (private repo under your account or an org):
  cd "$VAULT_DIR" && ./setup/connect-github.sh

Pull future base improvements anytime:
  cd "$VAULT_DIR" && .agents/scripts/update-base.sh
EOF
