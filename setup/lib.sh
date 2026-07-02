#!/usr/bin/env bash
# ===========================================================================
# obsidian-base — shared setup library (macOS / Linux)
# ===========================================================================
# Sourced by setup/setup.sh (first-run onboarding), setup/add-vault.sh
# (add-another-vault), setup/migrate-mcp-names.sh, and setup/uninstall.sh.
# It is the single home for the multi-vault / multi-client logic so those
# entry points stay thin and can't drift apart.
#
# It provides:
#   - lib_slugify / lib_uvx_bin / lib_platform            (small helpers)
#   - lib_gh_release_dl / lib_provision_plugins           (Obsidian plugin setup)
#   - lib_alloc_free_port                                 (per-vault port allocation)
#   - an MCP client-adapter registry:
#       mcp_client_present <client>
#       mcp_wire   <client> <label> <port> <key>
#       mcp_unwire <client> <label>
#       mcp_exists <client> <label>
#       mcp_list   <client>                    (obsidian-* / legacy labels)
#       mcp_rename <client> <old> <new> <port> <key>   (= wire new + unwire old)
#       for_each_client <op> <args...>         (op ∈ wire|unwire|rename)
#     Clients: claude_desktop | claude_code | codex_cli
#
# This file is meant to be SOURCED. It does not set -euo pipefail (that is the
# caller's job) and it defines say/warn/have/die only if the caller hasn't.
# ===========================================================================

# ---- small helpers (defined only if the caller hasn't) --------------------
if ! declare -F say  >/dev/null 2>&1; then say()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }; fi
if ! declare -F warn >/dev/null 2>&1; then warn() { printf '\033[1;33m  ! %s\033[0m\n' "$*" >&2; }; fi
if ! declare -F die  >/dev/null 2>&1; then die()  { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }; fi
if ! declare -F have >/dev/null 2>&1; then have() { command -v "$1" >/dev/null 2>&1; }; fi

lib_platform() { case "$(uname -s)" in Darwin) echo mac ;; Linux) echo linux ;; *) echo other ;; esac; }

# Vault name -> filesystem/label slug (lowercase, [a-z0-9-] only). Also the
# basis for the per-vault MCP label `obsidian-<slug>`.
lib_slugify() { printf '%s' "$1" | tr '[:upper:] ' '[:lower:]-' | tr -cd 'a-z0-9-'; }

# Vault name -> MCP server label `obsidian-<clean-slug>`. Strips a redundant
# leading "obsidian"/"obsidian-" from the slug so a vault literally named
# "Obsidian Puma" becomes `obsidian-puma`, not `obsidian-obsidian-puma`.
lib_mcp_label() {
  local slug; slug="$(lib_slugify "$1")"
  slug="${slug#obsidian-}"; slug="${slug#obsidian}"; slug="${slug#-}"
  [ -n "$slug" ] || slug="vault"
  printf 'obsidian-%s' "$slug"
}

# Resolve uvx to an ABSOLUTE path. Claude Desktop and Codex launch stdio MCP
# servers with a stripped PATH and don't source the shell, so a bare "uvx"
# (under ~/.local/bin or Homebrew) silently never starts. Claude Code inherits
# the shell PATH, so a bare "uvx" is fine there.
lib_uvx_bin() { command -v uvx 2>/dev/null || echo uvx; }

# ---- Obsidian plugin provisioning ----------------------------------------
lib_gh_release_dl() { # repo destdir  (downloads main.js, manifest.json, styles.css from latest release)
  local repo="$1" dest="$2" base tag
  mkdir -p "$dest"
  tag="$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest" | jq -r .tag_name)"
  [ -n "$tag" ] && [ "$tag" != null ] || { warn "no release for $repo"; return 1; }
  base="https://github.com/$repo/releases/download/$tag"
  curl -fsSL "$base/manifest.json" -o "$dest/manifest.json" || return 1
  curl -fsSL "$base/main.js"       -o "$dest/main.js"       || return 1
  curl -fsSL "$base/styles.css"    -o "$dest/styles.css" 2>/dev/null || true
}

# Provision the Git + Local REST API plugins for a vault, pinned to a specific
# HTTPS port (insecure port = port-1). Generates a REST API key if one isn't
# supplied and writes it to <vault>/.obsidian/.rest-api-key (gitignored). All
# informational output goes to stderr so callers can capture nothing on stdout.
lib_provision_plugins() { # vault_dir https_port [key]
  local vault_dir="$1" port="$2" key="${3:-}" insecure
  insecure=$((port - 1))
  cd "$vault_dir" || { warn "provision: cannot cd to $vault_dir"; return 1; }
  say "Installing Obsidian plugins (Git + Local REST API)…" >&2
  lib_gh_release_dl "Vinzent03/obsidian-git" ".obsidian/plugins/obsidian-git" >&2 || warn "obsidian-git download failed"
  lib_gh_release_dl "coddingtonbear/obsidian-local-rest-api" ".obsidian/plugins/obsidian-local-rest-api" >&2 || warn "local-rest-api download failed"
  [ -n "$key" ] || key="$(openssl rand -hex 32 2>/dev/null || head -c 32 /dev/urandom | xxd -p | tr -d '\n')"
  printf '%s' "$key" > "$vault_dir/.obsidian/.rest-api-key"   # gitignored; our reference
  local lr=".obsidian/plugins/obsidian-local-rest-api/data.json"
  if [ -f ".obsidian/plugins/obsidian-local-rest-api/main.js" ]; then
    jq -n --arg k "$key" --argjson p "$port" --argjson ip "$insecure" \
      '{apiKey:$k, crypto:null, port:$p, insecurePort:$ip, enableInsecureServer:true, bindingHost:"127.0.0.1"}' > "$lr"
  fi
  jq -n '["obsidian-local-rest-api","obsidian-git"]' > .obsidian/community-plugins.json
}

# ---- per-vault free-port allocation ---------------------------------------
# Obsidian's Local REST API binds one port per open vault and does NOT
# auto-allocate. Multiple vaults reachable at once therefore need DISTINCT
# ports. We allocate HTTPS ports in steps of 2 from 27124 (even), so the
# derived insecure port (https-1, odd) can never collide with another vault's
# HTTPS port. A candidate is free only when the HTTPS port AND its insecure
# partner are both (a) unreferenced by any wired MCP client and (b) not live.
_lib_port_listening() { # port
  local p="$1"
  # Test hook: when LIB_FAKE_LISTENING is set (even to ""), treat it as the
  # authoritative space-separated list of "listening" ports and skip the real
  # probe. Lets the smoke test run deterministically regardless of the host.
  if [ -n "${LIB_FAKE_LISTENING+set}" ]; then
    case " $LIB_FAKE_LISTENING " in *" $p "*) return 0 ;; *) return 1 ;; esac
  fi
  if command -v lsof >/dev/null 2>&1; then
    lsof -nP -iTCP:"$p" -sTCP:LISTEN >/dev/null 2>&1 && return 0 || return 1
  fi
  (exec 3<>"/dev/tcp/127.0.0.1/$p") >/dev/null 2>&1 && { exec 3>&- 2>/dev/null; return 0; }
  return 1
}

# All OBSIDIAN_PORT values already claimed across every wired client, one per line.
_lib_used_ports() {
  local cfg
  cfg="$(_cd_config_path)"
  if [ -f "$cfg" ]; then
    jq -r '(.mcpServers // {}) | to_entries[] | .value.env.OBSIDIAN_PORT // empty' "$cfg" 2>/dev/null || true
  fi
  local toml; toml="$(_cx_config_path)"
  if [ -f "$toml" ]; then
    grep -E '^[[:space:]]*OBSIDIAN_PORT[[:space:]]*=' "$toml" 2>/dev/null \
      | sed -E 's/.*=[[:space:]]*"?([0-9]+)"?.*/\1/' || true
  fi
  if have claude; then
    # Best-effort: claude mcp get prints the env; scrape any OBSIDIAN_PORT it shows.
    local lbl
    for lbl in $(mcp_list claude_code 2>/dev/null); do
      claude mcp get "$lbl" 2>/dev/null | grep -Eo 'OBSIDIAN_PORT[^0-9]*[0-9]+' | grep -Eo '[0-9]+' || true
    done
  fi
}

lib_alloc_free_port() { # -> echoes an even HTTPS port >= 27124
  local used p
  used=" $(_lib_used_ports | tr '\n' ' ' ) "
  p=27124
  while :; do
    if [[ "$used" != *" $p "* ]] && [[ "$used" != *" $((p-1)) "* ]] \
       && ! _lib_port_listening "$p" && ! _lib_port_listening "$((p-1))"; then
      echo "$p"; return 0
    fi
    p=$((p + 2))
    [ "$p" -gt 27999 ] && { warn "no free port found below 28000; defaulting to 27124"; echo 27124; return 1; }
  done
}

# ===========================================================================
# MCP client-adapter registry
# ===========================================================================
# Each client is one adapter implementing wire/unwire/exists/list. The public
# entry points dispatch to `mcp_<client>_<op>`. Adding a client = one adapter;
# nothing outside an adapter should know a client's on-disk config format.
MCP_ALL_CLIENTS="${MCP_ALL_CLIENTS:-claude_desktop claude_code codex_cli}"
OBSIDIAN_HOST="${OBSIDIAN_HOST:-127.0.0.1}"

# --- config path helpers (env-overridable for testing) ---------------------
_cd_config_path() {
  if [ -n "${CLAUDE_DESKTOP_CONFIG:-}" ]; then printf '%s' "$CLAUDE_DESKTOP_CONFIG"; return; fi
  if [ "$(lib_platform)" = mac ]; then
    printf '%s' "$HOME/Library/Application Support/Claude/claude_desktop_config.json"
  else
    printf '%s' "$HOME/.config/Claude/claude_desktop_config.json"
  fi
}
_cx_config_path() { printf '%s' "${CODEX_HOME:-$HOME/.codex}/config.toml"; }

# --- presence: is this client worth wiring on this machine? ----------------
# claude_desktop is pre-wired optimistically (the config file activates the
# moment the app is installed), so it is always "present". claude_code and
# codex_cli require their CLI to be installed.
mcp_client_present() {
  case "$1" in
    claude_desktop) return 0 ;;
    claude_code)    have claude ;;
    codex_cli)      have codex ;;
    *) return 1 ;;
  esac
}

# Map a user-facing MCP_CLIENTS selector to concrete adapter names (echoes an
# empty string for "none"). Shared by setup.sh and add-vault.sh.
lib_select_clients() {
  case "$1" in
    desktop) echo "claude_desktop" ;;
    code)    echo "claude_code" ;;
    codex)   echo "codex_cli" ;;
    both)    echo "claude_desktop claude_code" ;;
    all|"")  echo "claude_desktop claude_code codex_cli" ;;
    none)    echo "" ;;
    *)       echo "$1" ;;   # explicit space-separated adapter list
  esac
}

# --------------------------- Claude Desktop (JSON) -------------------------
mcp_claude_desktop_exists() { # label
  local cfg; cfg="$(_cd_config_path)"
  [ -f "$cfg" ] && jq -e --arg l "$1" '.mcpServers[$l]' "$cfg" >/dev/null 2>&1
}
mcp_claude_desktop_wire() { # label port key  (idempotent, never clobbers a different entry)
  local label="$1" port="$2" key="$3" cfg uvx; cfg="$(_cd_config_path)"; uvx="$(lib_uvx_bin)"
  [ "$uvx" = uvx ] && warn "uvx not resolvable; Desktop entry '$label' uses bare 'uvx' and may not start until uvx is on PATH."
  mkdir -p "$(dirname "$cfg")"; [ -f "$cfg" ] || echo '{}' > "$cfg"
  if mcp_claude_desktop_exists "$label"; then say "Claude Desktop: '$label' already present — leaving as-is." >&2; return 0; fi
  jq --arg l "$label" --arg k "$key" --arg h "$OBSIDIAN_HOST" --arg p "$port" --arg uvx "$uvx" '
    .mcpServers = (.mcpServers // {}) |
    .mcpServers[$l] = {command:$uvx, args:["mcp-obsidian"],
      env:{OBSIDIAN_API_KEY:$k, OBSIDIAN_HOST:$h, OBSIDIAN_PORT:$p}}' \
    "$cfg" > "$cfg.tmp" && mv "$cfg.tmp" "$cfg"
  say "Claude Desktop: wired '$label' (port $port)." >&2
}
mcp_claude_desktop_unwire() { # label
  local cfg; cfg="$(_cd_config_path)"
  [ -f "$cfg" ] || return 0
  jq --arg l "$1" 'if .mcpServers then .mcpServers |= del(.[$l]) else . end' "$cfg" > "$cfg.tmp" && mv "$cfg.tmp" "$cfg"
}
mcp_claude_desktop_list() { # -> obsidian-* / legacy labels
  local cfg; cfg="$(_cd_config_path)"
  [ -f "$cfg" ] || return 0
  jq -r '(.mcpServers // {}) | keys[]' "$cfg" 2>/dev/null | grep -E '^(obsidian-[a-z0-9-]+|mcp-obsidian)$' || true
}

# ---------------------------- Claude Code (CLI) ----------------------------
mcp_claude_code_exists() { have claude && claude mcp get "$1" >/dev/null 2>&1; }
mcp_claude_code_wire() { # label port key
  local label="$1" port="$2" key="$3"
  have claude || { warn "Claude Code CLI not found; skipping '$label'."; return 0; }
  if mcp_claude_code_exists "$label"; then say "Claude Code: '$label' already present — leaving as-is." >&2; return 0; fi
  # bare uvx: Claude Code inherits the shell PATH. --scope user → every project.
  claude mcp add "$label" --scope user \
    --env OBSIDIAN_API_KEY="$key" --env OBSIDIAN_HOST="$OBSIDIAN_HOST" --env OBSIDIAN_PORT="$port" \
    -- uvx mcp-obsidian >/dev/null 2>&1 \
    && say "Claude Code: wired '$label' (port $port)." >&2 \
    || warn "couldn't add '$label' to Claude Code (add it manually: see SETUP.md)"
}
mcp_claude_code_unwire() { # label
  have claude || return 0
  claude mcp remove "$1" --scope user >/dev/null 2>&1 || claude mcp remove "$1" >/dev/null 2>&1 || true
}
mcp_claude_code_list() {
  have claude || return 0
  claude mcp list 2>/dev/null | grep -Eo '(obsidian-[a-z0-9-]+|mcp-obsidian)' | sort -u || true
}

# ------------------------------- Codex (TOML) ------------------------------
# Codex CLI reads MCP servers from ${CODEX_HOME:-~/.codex}/config.toml as
# [mcp_servers.<label>] tables. We only ever write/remove tables we recognize
# (obsidian-* / mcp-obsidian) and preserve everything else in the file.
mcp_codex_cli_exists() { # label
  local toml; toml="$(_cx_config_path)"
  [ -f "$toml" ] && grep -Eq "^[[:space:]]*\[mcp_servers\.$1\][[:space:]]*$" "$toml"
}
mcp_codex_cli_wire() { # label port key
  local label="$1" port="$2" key="$3" toml uvx; toml="$(_cx_config_path)"; uvx="$(lib_uvx_bin)"
  have codex || { warn "Codex CLI not found; skipping '$label'."; return 0; }
  [ "$uvx" = uvx ] && warn "uvx not resolvable; Codex entry '$label' uses bare 'uvx' and may not start until uvx is on PATH."
  mkdir -p "$(dirname "$toml")"; [ -f "$toml" ] || : > "$toml"
  if mcp_codex_cli_exists "$label"; then say "Codex: '$label' already present — leaving as-is." >&2; return 0; fi
  # separate from any prior content with a blank line when the file is non-empty
  [ -s "$toml" ] && printf '\n' >> "$toml"
  {
    printf '[mcp_servers.%s]\n' "$label"
    printf 'command = "%s"\n' "$uvx"
    printf 'args = ["mcp-obsidian"]\n\n'
    printf '[mcp_servers.%s.env]\n' "$label"
    printf 'OBSIDIAN_API_KEY = "%s"\n' "$key"
    printf 'OBSIDIAN_HOST = "%s"\n' "$OBSIDIAN_HOST"
    printf 'OBSIDIAN_PORT = "%s"\n' "$port"
  } >> "$toml"
  say "Codex: wired '$label' (port $port)." >&2
}
mcp_codex_cli_unwire() { # label — remove [mcp_servers.<label>] and its sub-tables, keep the rest
  local label="$1" toml; toml="$(_cx_config_path)"
  [ -f "$toml" ] || return 0
  awk -v pfx="mcp_servers.$label" '
    function tname(l,   s){ s=l; sub(/^\[\[?/,"",s); sub(/\]\]?.*$/,"",s); gsub(/^[ \t]+|[ \t]+$/,"",s); return s }
    /^[ \t]*\[/ { t=tname($0); skip = (t==pfx || index(t, pfx ".")==1) ? 1 : 0 }
    skip!=1 { print }
  ' "$toml" > "$toml.tmp" && mv "$toml.tmp" "$toml"
  # collapse any run of 3+ blank lines left behind into a single blank line
  awk 'BEGIN{b=0} /^[[:space:]]*$/{b++; if(b<=1)print; next} {b=0; print}' "$toml" > "$toml.tmp" && mv "$toml.tmp" "$toml"
}
mcp_codex_cli_list() {
  local toml; toml="$(_cx_config_path)"
  [ -f "$toml" ] || return 0
  grep -Eo '^\[mcp_servers\.(obsidian-[a-z0-9-]+|mcp-obsidian)\]' "$toml" 2>/dev/null \
    | sed -E 's/^\[mcp_servers\.//; s/\]$//' | sort -u || true
}

# ------------------------------- dispatch ----------------------------------
mcp_exists() { "mcp_${1}_exists" "$2"; }
mcp_wire()   { "mcp_${1}_wire"   "$2" "$3" "$4"; }
mcp_unwire() { "mcp_${1}_unwire" "$2"; }
mcp_list()   { "mcp_${1}_list"; }
mcp_rename() { # client old new port key  == wire new + unwire old (uniform across clients)
  local client="$1" old="$2" new="$3" port="$4" key="$5"
  mcp_wire "$client" "$new" "$port" "$key" && mcp_unwire "$client" "$old"
}

# for_each_client <op> <args...> — runs <op> on every PRESENT client, skipping
# absent ones without error. op ∈ wire|unwire|rename (args match the op).
for_each_client() {
  local op="$1"; shift
  local client
  for client in $MCP_ALL_CLIENTS; do
    mcp_client_present "$client" || { say "$client not installed — skipping." >&2; continue; }
    "mcp_${op}" "$client" "$@"
  done
}

# Read one env value from a Claude Desktop server entry (fallback source when a
# vault's own key/port files are missing). label var -> value (or empty).
_cd_get_env() {
  local cfg; cfg="$(_cd_config_path)"; [ -f "$cfg" ] || return 0
  jq -r --arg l "$1" --arg v "$2" '.mcpServers[$l].env[$v] // empty' "$cfg" 2>/dev/null || true
}

# ---------------------- legacy-name migration ------------------------------
# Rename a legacy `mcp-obsidian` entry to a vault-named label (obsidian-<slug>)
# across every client that actually has it, keeping the same port + key. Only
# touches clients where the legacy entry exists (so it never fabricates entries
# in a client that never had one). Idempotent: a clean no-op once migrated.
# Reconstructs port/key from the vault itself (its data.json + .rest-api-key),
# falling back to the Claude Desktop entry's own env. Announce-before-mutate.
lib_migrate_legacy_mcp() { # vault_dir [label]
  local vault_dir="$1" label="${2:-}" client found="" name dj port key
  if [ -z "$label" ]; then
    name="$(grep -E '^vault_name:' "$vault_dir/.agents/vault-profile.md" 2>/dev/null | head -1 \
            | sed -E 's/^vault_name:[[:space:]]*"?([^"]*)"?.*/\1/')"
    [ -n "$name" ] || name="$(basename "$vault_dir")"
    label="$(lib_mcp_label "$name")"
  fi
  for client in $MCP_ALL_CLIENTS; do
    mcp_client_present "$client" || continue
    mcp_exists "$client" "mcp-obsidian" && found=1
  done
  [ -n "$found" ] || { say "No legacy 'mcp-obsidian' entry found — nothing to migrate."; return 0; }

  dj="$vault_dir/.obsidian/plugins/obsidian-local-rest-api/data.json"
  port="$(jq -r '.port // empty' "$dj" 2>/dev/null || true)"
  [ -n "$port" ] || port="$(_cd_get_env mcp-obsidian OBSIDIAN_PORT)"
  [ -n "$port" ] || port=27124
  key="$(cat "$vault_dir/.obsidian/.rest-api-key" 2>/dev/null || true)"
  [ -n "$key" ] || key="$(_cd_get_env mcp-obsidian OBSIDIAN_API_KEY)"
  [ -n "$key" ] || { warn "migration: could not determine the API key; leaving 'mcp-obsidian' untouched."; return 1; }

  say "Migrating legacy 'mcp-obsidian' → '$label' (port $port) across clients…"
  for client in $MCP_ALL_CLIENTS; do
    mcp_client_present "$client" || continue
    if mcp_exists "$client" "mcp-obsidian"; then
      mcp_rename "$client" "mcp-obsidian" "$label" "$port" "$key" && say "  $client: mcp-obsidian → $label" >&2
    fi
  done
}
