#!/usr/bin/env bash
# ===========================================================================
# obsidian-base — reverse the agent integration (macOS / Linux)
# ===========================================================================
# Undoes what setup.sh wired up, WITHOUT EVER TOUCHING YOUR NOTES. By default
# it only DISCONNECTS the integration:
#   1. removes the mcp-obsidian server from Claude Desktop's config
#   2. removes the mcp-obsidian server from Claude Code (claude mcp remove)
#   3. removes the managed block from ~/.claude/CLAUDE.md (between sentinels)
#
# It does NOT delete your vault, and it does NOT uninstall prerequisites
# (git, jq, uv, Obsidian, Homebrew) — those are general-purpose tools you may
# rely on elsewhere. Your notes are never deleted by this script. If you ever
# want the vault gone, delete the folder yourself — it prints the location.
#
# Optional flag:
#   --remove-plugins   also remove the Local REST API + Git plugins and the
#                      REST API key from the vault's .obsidian/ (reversible —
#                      just re-run setup.sh). Needs the vault: run this inside
#                      it, or pass VAULT_DIR=/path/to/vault.
#
# Idempotent — safe to re-run. Override paths with CLAUDE_DESKTOP_CONFIG,
# CLAUDE_MD, VAULT_DIR.
set -euo pipefail

CLAUDE_DESKTOP_CONFIG="${CLAUDE_DESKTOP_CONFIG:-}"
CLAUDE_MD="${CLAUDE_MD:-$HOME/.claude/CLAUDE.md}"
VAULT_DIR="${VAULT_DIR:-}"
REMOVE_PLUGINS=""
for arg in "$@"; do
  case "$arg" in
    --remove-plugins) REMOVE_PLUGINS=1 ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "unknown option: $arg (try --help)" >&2; exit 2 ;;
  esac
done

say()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m  ! %s\033[0m\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }

OS="$(uname -s)"
case "$OS" in Darwin) PLATFORM=mac ;; Linux) PLATFORM=linux ;; *) PLATFORM=other ;; esac

# ---- 1. Claude Desktop config --------------------------------------------
remove_desktop() {
  local cfg="$CLAUDE_DESKTOP_CONFIG"
  if [ -z "$cfg" ]; then
    [ "$PLATFORM" = mac ] && cfg="$HOME/Library/Application Support/Claude/claude_desktop_config.json" \
                          || cfg="$HOME/.config/Claude/claude_desktop_config.json"
  fi
  [ -f "$cfg" ] || { say "No Claude Desktop config at $cfg — skipping."; return; }
  have jq || { warn "jq not found; edit $cfg by hand and delete the \"mcp-obsidian\" entry under .mcpServers."; return; }
  if jq -e '.mcpServers["mcp-obsidian"]' "$cfg" >/dev/null 2>&1; then
    jq 'if .mcpServers then .mcpServers |= del(.["mcp-obsidian"]) else . end' "$cfg" > "$cfg.tmp" && mv "$cfg.tmp" "$cfg"
    say "Removed mcp-obsidian from Claude Desktop config."
  else
    say "mcp-obsidian not present in Claude Desktop config — nothing to do."
  fi
}

# ---- 2. Claude Code ------------------------------------------------------
remove_code() {
  have claude || { say "Claude Code CLI not found — skipping."; return; }
  # setup adds it at user scope; try that first, then a plain remove as fallback.
  if claude mcp remove mcp-obsidian --scope user >/dev/null 2>&1; then
    say "Removed mcp-obsidian from Claude Code (user scope)."
  elif claude mcp remove mcp-obsidian >/dev/null 2>&1; then
    say "Removed mcp-obsidian from Claude Code."
  else
    say "mcp-obsidian not registered in Claude Code — nothing to do."
  fi
}

# ---- 3. global ~/.claude/CLAUDE.md ----------------------------------------
remove_global_rule() {
  [ -f "$CLAUDE_MD" ] || { say "No $CLAUDE_MD — skipping."; return; }
  if grep -q "BEGIN obsidian-base vault rules" "$CLAUDE_MD"; then
    awk '
      /<!-- BEGIN obsidian-base vault rules/ {skip=1; next}
      /<!-- END obsidian-base vault rules -->/ {skip=0; next}
      !skip {print}
    ' "$CLAUDE_MD" > "$CLAUDE_MD.tmp" && mv "$CLAUDE_MD.tmp" "$CLAUDE_MD"
    say "Removed the managed vault-rules block from $CLAUDE_MD."
    grep -q '[^[:space:]]' "$CLAUDE_MD" || warn "$CLAUDE_MD is now empty — delete it if you like."
  else
    warn "No managed sentinels found in $CLAUDE_MD."
    warn "If you added the vault rules by hand, remove the \"## Obsidian knowledge base\" section yourself."
  fi
}

# ---- 4. optional: Obsidian plugins in the vault --------------------------
remove_plugins() {
  local v="$VAULT_DIR"
  [ -z "$v" ] && v="$(git rev-parse --show-toplevel 2>/dev/null || echo "")"
  if [ -z "$v" ] || [ ! -d "$v/.obsidian" ]; then
    warn "Couldn't locate a vault (run inside it or pass VAULT_DIR=…). Skipping plugin removal."
    return
  fi
  say "Removing Local REST API + Git plugins from $v/.obsidian …"
  rm -rf "$v/.obsidian/plugins/obsidian-local-rest-api" "$v/.obsidian/plugins/obsidian-git"
  rm -f  "$v/.obsidian/.rest-api-key"
  [ -f "$v/.obsidian/community-plugins.json" ] && echo '[]' > "$v/.obsidian/community-plugins.json"
  say "Plugins removed (re-run setup.sh to restore them)."
}

say "Reversing the obsidian-base agent integration — your notes will NOT be touched…"
remove_desktop
remove_code
remove_global_rule
[ -n "$REMOVE_PLUGINS" ] && remove_plugins

VLOC="$VAULT_DIR"; [ -z "$VLOC" ] && VLOC="$(git rev-parse --show-toplevel 2>/dev/null || echo "")"
printf '\n\033[1;32m✓ Disconnected.\033[0m Restart Claude Desktop / start a fresh Claude Code session to drop the server.\n'
if [ -n "$VLOC" ] && [ -d "$VLOC/.obsidian" ]; then
  echo "Your vault (your notes) is untouched at: $VLOC"
else
  echo "Your vault was not deleted. If you want it gone, delete the vault folder yourself."
fi
