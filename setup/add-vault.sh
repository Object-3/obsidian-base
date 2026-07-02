#!/usr/bin/env bash
# ===========================================================================
# obsidian-base — ADD ANOTHER VAULT beside an existing one (macOS / Linux)
# ===========================================================================
# For when you already have one working base vault and want a second topic
# vault (e.g. "Obsidian Puma" beside "Obsidian Strategy"), reachable by your
# AI assistant at the SAME time, each addressable by its own name.
#
# Run it from inside an existing vault:
#   ./setup/add-vault.sh
#   VAULT_NAME="Obsidian Puma" PRIMARY_TAG=puma ./setup/add-vault.sh --yes
#
# Unlike setup.sh it does NOT install prerequisites — it assumes your first
# vault already set the machine up. It:
#   1. (first run) migrates the legacy `mcp-obsidian` connection to a vault name
#   2. creates the new vault from the same base your current vault tracks
#   3. provisions its Obsidian bridge on a fresh, auto-allocated free port + key
#   4. APPENDS a vault-named MCP server (obsidian-<slug>) into every local client
#      (Claude Desktop, Claude Code, Codex) WITHOUT touching existing vaults
#
# Idempotent and override-friendly (same env vars as setup.sh). Use --yes for
# a non-interactive run.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
. "$ROOT/setup/lib.sh"

# ---- config (env-overridable) --------------------------------------------
# Clone the SAME base your current vault tracks, so a new vault inherits whatever base
# version you're on. The `base` git remote is no longer standing (see update-base.sh), so
# read the persisted URL from .agents/.base-url; fall back to a legacy standing `base`
# remote (older vaults), then the public base.
BASE_REPO_URL="${BASE_REPO_URL:-$(
  if [ -s "$ROOT/.agents/.base-url" ]; then tr -d '[:space:]' <"$ROOT/.agents/.base-url"
  else git -C "$ROOT" remote get-url base 2>/dev/null || echo https://github.com/Object-3/obsidian-base.git
  fi
)}"
# New vault lands beside the current one by default.
VAULT_PARENT="${VAULT_PARENT:-$(dirname "$ROOT")}"
VAULT_NAME="${VAULT_NAME:-}"                 # prompted if empty
MCP_CLIENTS="${MCP_CLIENTS:-all}"            # all | desktop | code | codex | both | none | "<list>"
NO_OPEN="${NO_OPEN:-}"
ASSUME_YES=""; [ "${1:-}" = "--yes" ] && ASSUME_YES=1

ask() { # var prompt default
  local var="$1" prompt="$2" def="${3:-}" val
  [ -n "${!var:-}" ] && return
  if [ -n "$ASSUME_YES" ] || [ ! -t 0 ]; then printf -v "$var" '%s' "$def"; return; fi
  read -r -p "$prompt${def:+ [$def]}: " val || true
  printf -v "$var" '%s' "${val:-$def}"
}

have git || die "git is required."
have jq  || die "jq is required."

# ---- 1. migrate the existing vault's legacy connection (first run only) ----
# Before adding a second vault, give the first one a vault-name so both follow
# the same scheme. No-op once already migrated.
lib_migrate_legacy_mcp "$ROOT" || warn "legacy migration skipped"

# ---- 2. create the new vault from the base --------------------------------
ask VAULT_NAME "Name your new vault" "My Second Vault"
slug="$(lib_slugify "$VAULT_NAME")"
[ -n "$slug" ] || die "could not derive a folder name from '$VAULT_NAME'."
VAULT_DIR="$VAULT_PARENT/$slug"
LABEL="$(lib_mcp_label "$VAULT_NAME")"
[ -e "$VAULT_DIR" ] && die "a folder already exists at $VAULT_DIR. Pick another name, or run setup.sh to re-provision it."

mkdir -p "$VAULT_PARENT"
say "Creating your new vault at $VAULT_DIR (from $BASE_REPO_URL)…"
git clone --depth 1 "$BASE_REPO_URL" "$VAULT_DIR"
cd "$VAULT_DIR"
rm -rf .git                       # make it YOURS, not a clone of the base
# No standing `base` git remote (see update-base.sh: it adds one ephemerally per fetch and
# removes it, so `base` can't be mis-picked in Obsidian Git and push private notes to the
# public template). Persist a NON-DEFAULT base URL so this vault's /update-base finds the
# same fork/custom base; the public default needs nothing. Clear any .base-url the clone
# source carried first, so the new vault's base is exactly what setup resolved — not a
# stowaway inherited from the clone.
rm -f .agents/.base-url
if [ "$BASE_REPO_URL" != "https://github.com/Object-3/obsidian-base.git" ]; then
  printf '%s\n' "$BASE_REPO_URL" > .agents/.base-url
fi
git init -q && git add -A
git -c user.name="${GIT_AUTHOR_NAME:-Vault Owner}" -c user.email="${GIT_AUTHOR_EMAIL:-vault@localhost}" \
    commit -q -m "Initial vault from obsidian-base"
git config core.hooksPath .githooks 2>/dev/null || true
chmod +x .githooks/* .agents/scripts/*.sh setup/*.sh 2>/dev/null || true

# ---- 3. personalize -------------------------------------------------------
if [ -n "$ASSUME_YES" ]; then
  VAULT_NAME="$VAULT_NAME" PRIMARY_TAG="${PRIMARY_TAG:-kb}" .agents/scripts/init-vault.sh --yes || warn "init-vault skipped"
else
  .agents/scripts/init-vault.sh || warn "init-vault skipped (run it later)"
fi

# ---- 4. provision plugins on a fresh free port ----------------------------
have uv || warn "uv not found — the MCP runtime (uvx mcp-obsidian) may not start."
PORT="$(lib_alloc_free_port)"
lib_provision_plugins "$VAULT_DIR" "$PORT"
KEY="$(cat "$VAULT_DIR/.obsidian/.rest-api-key" 2>/dev/null || echo "")"
[ -n "$KEY" ] || die "provisioning did not produce a REST API key; aborting before wiring."

# ---- 5. APPEND the vault-named MCP into every selected client -------------
SEL="$(lib_select_clients "$MCP_CLIENTS")"
if [ -n "$SEL" ]; then
  say "Wiring the new vault MCP ($LABEL, port $PORT) into: $SEL"
  MCP_ALL_CLIENTS="$SEL" for_each_client wire "$LABEL" "$PORT" "$KEY"
fi

# ---- 6. open + report ------------------------------------------------------
if [ -z "$NO_OPEN" ] && [ "$(lib_platform)" = mac ]; then
  open -a Obsidian "$VAULT_DIR" 2>/dev/null || true
fi

cat <<EOF

$(printf '\033[1;32m✓ Added your new vault.\033[0m')  $VAULT_DIR

You now have more than one vault, each reachable by its own name:
  • This new one is wired as  "$LABEL"  (port $PORT).
  • Your existing vault keeps its own name and port.

TWO things to know so both work at the same time:
  1. Open BOTH vaults in Obsidian. A vault is only reachable by your assistant
     while its window is OPEN — the little bridge (Local REST API) only runs for
     an open vault. Closed vault → "$LABEL" will just say it can't connect.
  2. Start a FRESH assistant session so it picks up the new connection:
       • Claude Desktop: fully quit and reopen.
       • Claude Code / Codex: start a new session.
  To check: ask your assistant to "list the files in $LABEL".

Optional cloud backup for the new vault, anytime:
  cd "$VAULT_DIR" && ./setup/connect-github.sh
EOF
