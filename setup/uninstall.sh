#!/usr/bin/env bash
# ===========================================================================
# obsidian-base — reverse the agent integration (macOS / Linux)
# ===========================================================================
# Undoes what setup.sh / add-vault.sh wired up, WITHOUT EVER TOUCHING YOUR NOTES.
# By default it only DISCONNECTS the integration:
#   1. removes every obsidian MCP server (obsidian-* and the legacy mcp-obsidian)
#      from all local clients: Claude Desktop, Claude Code, and Codex
#   2. removes the managed block from ~/.claude/CLAUDE.md (between sentinels)
# (Removing just ONE vault's wiring is not offered — this disconnects them all.)
#
# It does NOT delete your vault, and it does NOT uninstall prerequisites
# (git, jq, uv, Obsidian, Homebrew) — those are general-purpose tools you may
# rely on elsewhere. Your notes are never deleted by this script. If you ever
# want the vault gone, delete the folder yourself — it prints the location.
#
# It also NEVER removes skills you installed into your tools' user-scope
# (~/.claude/skills, ~/.agents/skills) — once installed those are yours and you
# may rely on them in other projects. This script only informs you they remain.
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

# Use the shared adapter registry when it's next to us (the normal case). It
# knows every client (Claude Desktop, Claude Code, Codex) and every vault-named
# label. Fall back to a legacy single-name removal if the lib isn't available.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB_OK=""
# shellcheck disable=SC1091
[ -f "$ROOT/setup/lib.sh" ] && . "$ROOT/setup/lib.sh" && LIB_OK=1

# ---- 1+2. remove every obsidian MCP server from every client -------------
# Wholesale disconnect: removes all obsidian-* servers (and the legacy
# mcp-obsidian) from all clients. Removing a single vault's wiring is a separate
# concern (not offered here).
remove_all_servers() {
  if [ -n "$LIB_OK" ]; then
    local client label removed=0
    for client in $MCP_ALL_CLIENTS; do
      mcp_client_present "$client" || continue
      for label in $(mcp_list "$client"); do
        mcp_unwire "$client" "$label" && { say "Removed $label from $client."; removed=$((removed+1)); }
      done
    done
    [ "$removed" = 0 ] && say "No obsidian MCP servers found in any client — nothing to do."
    return
  fi
  # --- fallback: legacy single-name removal (lib.sh not found) ---
  warn "setup/lib.sh not found; removing only the legacy 'mcp-obsidian' entry."
  local cfg="$CLAUDE_DESKTOP_CONFIG"
  if [ -z "$cfg" ]; then
    [ "$PLATFORM" = mac ] && cfg="$HOME/Library/Application Support/Claude/claude_desktop_config.json" \
                          || cfg="$HOME/.config/Claude/claude_desktop_config.json"
  fi
  if [ -f "$cfg" ] && have jq && jq -e '.mcpServers["mcp-obsidian"]' "$cfg" >/dev/null 2>&1; then
    jq 'if .mcpServers then .mcpServers |= del(.["mcp-obsidian"]) else . end' "$cfg" > "$cfg.tmp" && mv "$cfg.tmp" "$cfg"
    say "Removed mcp-obsidian from Claude Desktop config."
  fi
  if have claude; then
    claude mcp remove mcp-obsidian --scope user >/dev/null 2>&1 \
      || claude mcp remove mcp-obsidian >/dev/null 2>&1 \
      || say "mcp-obsidian not registered in Claude Code — nothing to do."
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

# ---- 5. user-scope skills: INFORM, never remove --------------------------
# The portable skills you installed into your tools' user-scope are YOURS — they
# are left in place. We only tell you they remain (removal is your manual choice).
inform_user_scope_skills() {
  local man="${MIRROR_MANIFEST:-${XDG_CONFIG_HOME:-$HOME/.config}/obsidian-base/skill-mirror.json}"
  [ -f "$man" ] || return
  have jq || return
  local n; n="$(jq -r '.owned | length' "$man" 2>/dev/null || echo 0)"
  [ -n "$n" ] && [ "$n" != "0" ] && [ "$n" != "null" ] || return
  say "$n skill(s) you installed into user-scope are KEPT — offboarding never removes them."
  printf '    They stay in ~/.claude/skills and ~/.agents/skills, yours to use anywhere.\n'
  printf '    To remove them yourself: delete those skill dirs and %s\n' "$man"
}

say "Reversing the obsidian-base agent integration — your notes will NOT be touched…"
remove_all_servers
remove_global_rule
[ -n "$REMOVE_PLUGINS" ] && remove_plugins
inform_user_scope_skills

VLOC="$VAULT_DIR"; [ -z "$VLOC" ] && VLOC="$(git rev-parse --show-toplevel 2>/dev/null || echo "")"
printf '\n\033[1;32m✓ Disconnected.\033[0m Restart Claude Desktop / start a fresh Claude Code session to drop the server.\n'
if [ -n "$VLOC" ] && [ -d "$VLOC/.obsidian" ]; then
  echo "Your vault (your notes) is untouched at: $VLOC"
else
  echo "Your vault was not deleted. If you want it gone, delete the vault folder yourself."
fi
