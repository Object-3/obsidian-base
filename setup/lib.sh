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
#   - lib_slugify / lib_npx_bin / lib_platform            (small helpers)
#   - lib_gh_release_dl / lib_provision_plugins           (Obsidian plugin setup)
#   - lib_alloc_free_port                                 (per-vault port allocation)
#   - an MCP client-adapter registry (wires the Local REST API plugin's own
#     /mcp/ endpoint — NOT the abandoned uvx mcp-obsidian server; see below):
#       mcp_client_present <client>
#       mcp_wire   <client> <label> <port> <key>
#       mcp_unwire <client> <label>
#       mcp_exists <client> <label>
#       mcp_is_legacy <client> <label>         (still the old uvx mcp-obsidian?)
#       mcp_ensure <client> <label> <port> <key>  (wire | rewire-if-legacy | no-op)
#       mcp_list   <client>                    (obsidian-* / legacy labels)
#       mcp_rename <client> <old> <new> <port> <key>   (= wire new + unwire old)
#       for_each_client <op> <args...>         (op ∈ wire|unwire|rename|ensure)
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

lib_platform() { case "$(uname -s)" in Darwin) echo mac ;; Linux) echo linux ;; MINGW*|MSYS*|CYGWIN*) echo win ;; *) echo other ;; esac; }

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

# Resolve npx to an ABSOLUTE path. Claude Desktop and Codex launch stdio MCP
# servers with a stripped PATH and don't source the shell, so a bare "npx"
# silently never starts. Claude Code inherits the shell PATH, so bare "npx" is
# fine there. (npx runs the `mcp-remote` stdio→HTTP bridge — see below.)
lib_npx_bin() { command -v npx 2>/dev/null || echo npx; }

# --- the Obsidian MCP endpoint (plugin-native, port-in-the-URL) -------------
# We no longer wire the third-party `uvx mcp-obsidian` stdio server: it hardcodes
# port 27124 and ignores OBSIDIAN_PORT, so any 2nd+ vault (which must use a
# distinct port) could never authenticate. Instead we point every client at the
# Local REST API plugin's OWN built-in MCP server ("Streamable HTTP at /mcp/",
# plugin v4+), reached over the vault's loopback HTTP (insecure) port. Because
# the port lives in the URL, that whole class of bug is impossible, and there is
# no Python/uvx runtime to install.
#
# The insecure (plain-HTTP, 127.0.0.1-only) port is the HTTPS port - 1; the
# plugin serves /mcp/ there when enableInsecureServer is on (lib_provision_plugins
# sets it). HTTP-on-loopback avoids the self-signed-cert rejection that blocks
# HTTPS for Node-based clients, and the API key still authenticates every call.
lib_insecure_port() { printf '%s' "$(( $1 - 1 ))"; }
lib_mcp_url()       { printf 'http://127.0.0.1:%s/mcp/' "$(lib_insecure_port "$1")"; }
# The mcp-remote bridge argv (a JSON/TOML array of strings) for a stdio client.
# Claude Code speaks HTTP natively and skips the bridge; Claude Desktop and Codex
# use it because their native HTTP paths can't carry an inline bearer key cleanly.
lib_bridge_args_json() { # url key -> ["-y","mcp-remote",<url>,"--header","Authorization: Bearer <key>","--allow-http"]
  jq -cn --arg u "$1" --arg a "Authorization: Bearer $2" \
    '["-y","mcp-remote",$u,"--header",$a,"--allow-http"]'
}

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

# Every port already claimed across every wired client, one per line, with its
# adjacent secure/insecure partner (n-1, n, n+1). We scrape two shapes: the new
# plugin-endpoint URL (`127.0.0.1:<insecure>/mcp/`) and, for back-compat during
# migration, any leftover legacy `OBSIDIAN_PORT`. Emitting the ±1 band means a
# claim on either the secure or insecure port reserves the whole pair.
_lib_used_ports() {
  {
    local cfg toml
    cfg="$(_cd_config_path)"
    if [ -f "$cfg" ]; then
      jq -r '(.mcpServers // {}) | to_entries[] | .value.env.OBSIDIAN_PORT // empty' "$cfg" 2>/dev/null || true
      grep -Eo '127\.0\.0\.1:[0-9]+/mcp' "$cfg" 2>/dev/null | grep -Eo ':[0-9]+' | tr -d ':' || true
    fi
    toml="$(_cx_config_path)"
    if [ -f "$toml" ]; then
      grep -E '^[[:space:]]*OBSIDIAN_PORT[[:space:]]*=' "$toml" 2>/dev/null | sed -E 's/.*=[[:space:]]*"?([0-9]+)"?.*/\1/' || true
      grep -Eo '127\.0\.0\.1:[0-9]+/mcp' "$toml" 2>/dev/null | grep -Eo ':[0-9]+' | tr -d ':' || true
    fi
    if have claude; then
      local lbl out
      for lbl in $(mcp_list claude_code 2>/dev/null); do
        out="$(claude mcp get "$lbl" 2>/dev/null)"
        printf '%s\n' "$out" | grep -Eo 'OBSIDIAN_PORT[^0-9]*[0-9]+' | grep -Eo '[0-9]+' || true
        printf '%s\n' "$out" | grep -Eo '127\.0\.0\.1:[0-9]+/mcp' | grep -Eo ':[0-9]+' | tr -d ':' || true
      done
    fi
  } 2>/dev/null | while read -r n; do
    [ -n "$n" ] || continue
    echo "$((n-1))"; echo "$n"; echo "$((n+1))"
  done
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
  case "$(lib_platform)" in
    mac) printf '%s' "$HOME/Library/Application Support/Claude/claude_desktop_config.json" ;;
    win) printf '%s' "${APPDATA:-$HOME/AppData/Roaming}/Claude/claude_desktop_config.json" ;;   # Git Bash
    *)   printf '%s' "$HOME/.config/Claude/claude_desktop_config.json" ;;
  esac
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
  local label="$1" port="$2" key="$3" cfg npx url; cfg="$(_cd_config_path)"; npx="$(lib_npx_bin)"; url="$(lib_mcp_url "$port")"
  [ "$npx" = npx ] && warn "npx not resolvable; Desktop entry '$label' uses bare 'npx' and may not start until Node/npx is on PATH."
  mkdir -p "$(dirname "$cfg")"; [ -f "$cfg" ] || echo '{}' > "$cfg"
  if mcp_claude_desktop_exists "$label"; then say "Claude Desktop: '$label' already present — leaving as-is." >&2; return 0; fi
  # Claude Desktop config carries only stdio servers, so it reaches the plugin's
  # HTTP /mcp/ endpoint through the mcp-remote bridge (key inline in the args).
  if jq --arg l "$label" --arg cmd "$npx" --argjson args "$(lib_bridge_args_json "$url" "$key")" '
    .mcpServers = (.mcpServers // {}) |
    .mcpServers[$l] = {command:$cmd, args:$args}' \
    "$cfg" > "$cfg.tmp" && mv "$cfg.tmp" "$cfg"; then
    say "Claude Desktop: wired '$label' → $url (mcp-remote bridge)." >&2
  else
    rm -f "$cfg.tmp"; warn "Claude Desktop: failed to write $cfg (jq parse error?) — '$label' NOT wired."; return 1
  fi
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
  local label="$1" port="$2" key="$3" url; url="$(lib_mcp_url "$port")"
  have claude || { warn "Claude Code CLI not found; skipping '$label'."; return 0; }
  if mcp_claude_code_exists "$label"; then say "Claude Code: '$label' already present — leaving as-is." >&2; return 0; fi
  # Claude Code speaks Streamable HTTP natively and carries the bearer key inline
  # — no bridge needed. --scope user → every project.
  claude mcp add "$label" --scope user --transport http "$url" \
    --header "Authorization: Bearer $key" >/dev/null 2>&1 \
    && say "Claude Code: wired '$label' → $url (native http)." >&2 \
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
  local label="$1" port="$2" key="$3" toml npx url; toml="$(_cx_config_path)"; npx="$(lib_npx_bin)"; url="$(lib_mcp_url "$port")"
  have codex || { warn "Codex CLI not found; skipping '$label'."; return 0; }
  [ "$npx" = npx ] && warn "npx not resolvable; Codex entry '$label' uses bare 'npx' and may not start until Node/npx is on PATH."
  mkdir -p "$(dirname "$toml")"; [ -f "$toml" ] || : > "$toml"
  if mcp_codex_cli_exists "$label"; then say "Codex: '$label' already present — leaving as-is." >&2; return 0; fi
  # Codex's native HTTP transport can only read the bearer key from an env var;
  # the mcp-remote bridge keeps the key inline in the table (no env-var to manage).
  # separate from any prior content with a blank line when the file is non-empty
  [ -s "$toml" ] && printf '\n' >> "$toml"
  if {
    printf '[mcp_servers.%s]\n' "$label"
    printf 'command = "%s"\n' "$npx"
    printf 'args = ["-y", "mcp-remote", "%s", "--header", "Authorization: Bearer %s", "--allow-http"]\n' "$url" "$key"
  } >> "$toml"; then
    say "Codex: wired '$label' → $url (mcp-remote bridge)." >&2
  else
    warn "Codex: failed to write $toml — '$label' NOT wired."; return 1
  fi
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

# --------- legacy-shape detection (the abandoned uvx mcp-obsidian server) ---
# True when <label> exists on the client but is still wired to the old
# `uvx mcp-obsidian` stdio server (the one that hardcodes port 27124). The
# discriminator is the literal string "mcp-obsidian" in the entry's command/args
# (NOT the label) — the new plugin-endpoint shape uses mcp-remote / native http and
# never contains it. Scoping the match to the entry body, not its name, avoids a
# false positive on a vault whose own label legitimately contains "mcp-obsidian"
# (e.g. a vault named "MCP Obsidian" → label `obsidian-mcp-obsidian`).
# sync-mcp uses these to REPLACE stale entries in place, not just detect them.
mcp_claude_desktop_is_legacy() { # label
  local cfg; cfg="$(_cd_config_path)"; [ -f "$cfg" ] || return 1
  jq -e --arg l "$1" '[(.mcpServers[$l].command // "")] + (.mcpServers[$l].args // []) | any(test("mcp-obsidian"))' "$cfg" >/dev/null 2>&1
}
mcp_claude_code_is_legacy() { # label
  have claude || return 1
  # Scope the match to the entry body, not the echoed label: drop any line that
  # contains the label itself (a label like `obsidian-mcp-obsidian` would otherwise
  # false-positive), then look for the uvx server's "mcp-obsidian" command/arg.
  claude mcp get "$1" 2>/dev/null | grep -vF -- "$1" | grep -q 'mcp-obsidian'
}
mcp_codex_cli_is_legacy() { # label
  local toml; toml="$(_cx_config_path)"; [ -f "$toml" ] || return 1
  awk -v pfx="mcp_servers.$1" '
    function tname(l,  s){ s=l; sub(/^\[\[?/,"",s); sub(/\]\]?.*$/,"",s); gsub(/^[ \t]+|[ \t]+$/,"",s); return s }
    /^[ \t]*\[/ { t=tname($0); inb = (t==pfx || index(t, pfx ".")==1); next }
    inb && /mcp-obsidian/ { found=1 }
    END { exit(found?0:1) }
  ' "$toml"
}

# ------------------------------- dispatch ----------------------------------
mcp_exists()    { "mcp_${1}_exists"    "$2"; }
mcp_wire()      { "mcp_${1}_wire"      "$2" "$3" "$4"; }
mcp_unwire()    { "mcp_${1}_unwire"    "$2"; }
mcp_list()      { "mcp_${1}_list"; }
mcp_is_legacy() { "mcp_${1}_is_legacy" "$2"; }
mcp_rename() { # client old new port key  == wire new + unwire old (uniform across clients)
  local client="$1" old="$2" new="$3" port="$4" key="$5"
  mcp_wire "$client" "$new" "$port" "$key" && mcp_unwire "$client" "$old"
}
# Converge <label> on <client> to the CURRENT plugin-endpoint shape for port/key:
#   absent → wire; legacy uvx-mcp-obsidian shape → rewire; already-correct → no-op.
# This is the idempotent primitive sync-mcp/doctor run for every (vault × client).
mcp_ensure() { # client label port key
  local client="$1" label="$2" port="$3" key="$4"
  if mcp_exists "$client" "$label"; then
    if mcp_is_legacy "$client" "$label"; then
      say "$client: '$label' is the legacy uvx server — rewiring to the plugin /mcp/ endpoint." >&2
      mcp_unwire "$client" "$label" && mcp_wire "$client" "$label" "$port" "$key"
    else
      say "$client: '$label' already on the plugin endpoint — leaving as-is." >&2
    fi
  else
    mcp_wire "$client" "$label" "$port" "$key"
  fi
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
