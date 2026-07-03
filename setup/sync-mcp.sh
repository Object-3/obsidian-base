#!/usr/bin/env bash
# ===========================================================================
# obsidian-base — reconcile every vault's Obsidian MCP into every AI client
# ===========================================================================
# The convergence "doctor" for MCP wiring. It makes the invariant true no matter
# how a machine drifted into its current state:
#
#   every vault on this machine  ×  every AI client installed
#     → wired to that vault's Local REST API plugin /mcp/ endpoint, under one
#       canonical name, with the abandoned `uvx mcp-obsidian` server ERADICATED.
#
# Why this exists: setup.sh wires the FIRST vault into whatever clients exist at
# that moment; add-vault.sh adds the NEW vault. Neither backfills a pre-existing
# vault into a client installed later, and nothing repairs a hand-edited config.
# So surfaces drift into different subsets (Desktop has vault A, Codex has vault
# B, …). This command converges them. It also replaces the old port-hardcoding
# `uvx mcp-obsidian` wiring (which broke every 2nd+ vault) with the plugin's own
# port-native endpoint.
#
# Usage:
#   ./setup/sync-mcp.sh                 # CHECK: report drift, change nothing (default)
#   ./setup/sync-mcp.sh --fix           # apply: converge + eradicate legacy
#   ./setup/sync-mcp.sh --fix --yes     # apply without prompts
#   ./setup/sync-mcp.sh [--fix] VAULT…  # restrict to the given vault dir(s)
#
# Exit codes (CHECK mode): 0 = already converged, 3 = drift found (fixable).
# Idempotent: a clean no-op once converged. Discovers vaults from Obsidian's own
# registry (the vaults you've opened), keeping only vaults created from obsidian-base
# — i.e. folders carrying `.agents/vault-profile.md`. Pass explicit dirs to override.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
. "$ROOT/setup/lib.sh"

have jq || die "jq is required."

MODE=check; ASSUME_YES=""; VAULT_ARGS=()
for arg in "$@"; do
  case "$arg" in
    --fix)   MODE=fix ;;
    --check) MODE=check ;;
    --yes|-y) ASSUME_YES=1 ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    -*) die "unknown option: $arg (try --help)" ;;
    *)  VAULT_ARGS+=("$arg") ;;
  esac
done

# ---- where Obsidian records the vaults you've opened ----------------------
_obsidian_registry() {
  if [ "$(lib_platform)" = mac ]; then
    printf '%s' "$HOME/Library/Application Support/obsidian/obsidian.json"
  else
    printf '%s' "${XDG_CONFIG_HOME:-$HOME/.config}/obsidian/obsidian.json"
  fi
}

# Managed vault = a folder that carries the obsidian-base marker AND has the
# Local REST API plugin provisioned (a port + key to wire). Anything else in the
# Obsidian registry (a personal journal, the default sandbox) is skipped.
_is_managed_vault() { # dir
  [ -f "$1/.agents/vault-profile.md" ] \
    && [ -f "$1/.obsidian/plugins/obsidian-local-rest-api/data.json" ]
}

discover_vaults() {
  if [ "${#VAULT_ARGS[@]}" -gt 0 ]; then
    printf '%s\n' "${VAULT_ARGS[@]}"; return
  fi
  local reg; reg="$(_obsidian_registry)"
  [ -f "$reg" ] && jq -r '(.vaults // {}) | to_entries[] | .value.path' "$reg" 2>/dev/null
  # always consider the repo we're run from, even if never opened in Obsidian
  printf '%s\n' "$ROOT"
}

# ---- read a vault's wiring facts off disk ---------------------------------
_vault_data_json() { printf '%s' "$1/.obsidian/plugins/obsidian-local-rest-api/data.json"; }
vault_port() { jq -r '.port // empty' "$(_vault_data_json "$1")" 2>/dev/null; }
vault_key()  {
  local k; k="$(cat "$1/.obsidian/.rest-api-key" 2>/dev/null || true)"
  [ -n "$k" ] || k="$(jq -r '.apiKey // empty' "$(_vault_data_json "$1")" 2>/dev/null)"
  printf '%s' "$k"
}
vault_label() { # dir → obsidian-<slug>, from vault_name, falling back to the folder
  local name; name="$(grep -E '^vault_name:' "$1/.agents/vault-profile.md" 2>/dev/null | head -1 \
                      | sed -E 's/^vault_name:[[:space:]]*"?([^"]*)"?.*/\1/')"
  [ -n "$name" ] || name="$(basename "$1")"
  lib_mcp_label "$name"
}

# The plugin only serves /mcp/ over plain HTTP when the insecure loopback server
# is on. New vaults get it from lib_provision_plugins; older ones may not — the
# plugin re-binds the port only on reload, so we flag when a reload is needed.
RELOAD_NEEDED=()
_INS=""
# Sets _INS to ok|enabled|off in the CURRENT shell (not via $(), so its append to
# the RELOAD_NEEDED global survives).
ensure_insecure_server() { # dir port
  local dj on ip; dj="$(_vault_data_json "$1")"
  on="$(jq -r '.enableInsecureServer // false' "$dj" 2>/dev/null)"
  ip="$(jq -r '.insecurePort // empty' "$dj" 2>/dev/null)"
  if [ "$on" = true ] && [ -n "$ip" ]; then _INS=ok; return; fi
  if [ "$MODE" = fix ]; then
    if jq --argjson ip "$(( $2 - 1 ))" '.enableInsecureServer = true | .insecurePort = $ip' "$dj" > "$dj.tmp" 2>/dev/null; then
      mv "$dj.tmp" "$dj"; RELOAD_NEEDED+=("$1"); _INS=enabled; return
    fi
  fi
  _INS=off
}

# ---- back up mutable client configs before the first edit -----------------
_backed_up=""
backup_configs() {
  [ "$MODE" = fix ] || return 0
  [ -z "$_backed_up" ] || return 0
  local ts; ts="$(date +%s)"
  local cd cx; cd="$(_cd_config_path)"; cx="$(_cx_config_path)"
  [ -f "$cd" ] && cp "$cd" "$cd.bak.syncmcp.$ts"
  [ -f "$cx" ] && cp "$cx" "$cx.bak.syncmcp.$ts"
  _backed_up=1
}

# ===========================================================================
say "Reconciling Obsidian MCP wiring across all clients ($MODE mode)…"
DRIFT=0; WIRED=0; VAULTS=0

# de-dupe discovered dirs (registry + repo can overlap); keep managed ones only
declare -a MANAGED=()
while IFS= read -r d; do
  [ -n "$d" ] || continue
  d="${d%/}"
  case " ${MANAGED[*]-} " in *" $d "*) continue ;; esac
  _is_managed_vault "$d" && MANAGED+=("$d")
done < <(discover_vaults)

[ "${#MANAGED[@]}" -gt 0 ] || die "No vaults created from obsidian-base found (looked for .agents/vault-profile.md + the Local REST API plugin). Pass a vault dir explicitly, or run setup.sh first."

for vault in "${MANAGED[@]}"; do
  VAULTS=$((VAULTS+1))
  label="$(vault_label "$vault")"
  port="$(vault_port "$vault")"; key="$(vault_key "$vault")"
  if [ -z "$port" ] || [ -z "$key" ]; then
    warn "$vault: missing port or key (plugin not fully provisioned) — skipping. Run setup.sh in it."
    continue
  fi
  say "• $label  ($vault)  → http 127.0.0.1:$(lib_insecure_port "$port")/mcp/"
  ensure_insecure_server "$vault" "$port"; ins="$_INS"
  [ "$ins" = off ] && { DRIFT=$((DRIFT+1)); warn "    insecure loopback server is OFF — /mcp/ won't answer over HTTP. Run --fix to enable it (then reload the vault in Obsidian)."; }

  for client in $MCP_ALL_CLIENTS; do
    mcp_client_present "$client" || continue
    if mcp_exists "$client" "$label" && ! mcp_is_legacy "$client" "$label"; then
      continue   # already on the plugin endpoint
    fi
    DRIFT=$((DRIFT+1))
    if [ "$MODE" = fix ]; then
      backup_configs
      mcp_ensure "$client" "$label" "$port" "$key" >/dev/null 2>&1 && WIRED=$((WIRED+1))
    else
      if mcp_exists "$client" "$label"; then say "    would REWIRE $client:$label (legacy uvx → plugin /mcp/)"
      else say "    would WIRE   $client:$label"; fi
    fi
  done
done

# ---- eradicate the legacy `mcp-obsidian` name from every client -----------
for client in $MCP_ALL_CLIENTS; do
  mcp_client_present "$client" || continue
  if mcp_exists "$client" "mcp-obsidian"; then
    DRIFT=$((DRIFT+1))
    if [ "$MODE" = fix ]; then
      backup_configs; mcp_unwire "$client" "mcp-obsidian" && say "  removed legacy 'mcp-obsidian' from $client."
    else
      say "  would REMOVE legacy 'mcp-obsidian' from $client."
    fi
  fi
done

echo
if [ "$MODE" = check ]; then
  if [ "$DRIFT" -eq 0 ]; then
    printf '\033[1;32m✓ MCP wiring is converged\033[0m — %d vault(s), all clients on the plugin /mcp/ endpoint.\n' "$VAULTS"
    exit 0
  fi
  printf '\033[1;33m! %d item(s) need attention.\033[0m Run:  ./setup/sync-mcp.sh --fix\n' "$DRIFT"
  exit 3
fi

printf '\033[1;32m✓ Reconciled.\033[0m %d vault(s); %d wiring(s) added/repaired.\n' "$VAULTS" "$WIRED"
if [ "${#RELOAD_NEEDED[@]}" -gt 0 ]; then
  echo
  warn "Enabled the loopback HTTP server for the vault(s) below — RELOAD each in Obsidian"
  warn "(close & reopen the vault, or toggle the Local REST API plugin) so it binds the port:"
  for v in "${RELOAD_NEEDED[@]}"; do printf '    • %s\n' "$v" >&2; done
fi
echo "Start a fresh assistant session (quit/reopen Claude Desktop; new Claude Code / Codex session) to pick up the changes."
