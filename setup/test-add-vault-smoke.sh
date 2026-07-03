#!/usr/bin/env bash
# ===========================================================================
# Smoke test for setup/lib.sh + setup/sync-mcp.sh — the multi-vault /
# multi-client wiring core (plugin /mcp/ endpoint edition).
# ===========================================================================
# Runs fully offline in a sandbox: temp Claude Desktop config, a stub `claude`
# CLI, a stub `codex` CLI, and a temp CODEX_HOME. Asserts free-port allocation,
# append-only + idempotent wiring across all three clients on the plugin
# endpoint, legacy uvx detection + eradication (mcp_ensure), rename, unwire,
# sync-mcp convergence, and that unrelated Codex config survives edits.
#
#   bash setup/test-add-vault-smoke.sh
#
# Exits non-zero on the first failed assertion.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  \033[1;32mok\033[0m   %s\n' "$*"; }
bad()  { FAIL=$((FAIL+1)); printf '  \033[1;31mFAIL\033[0m %s\n' "$*"; }
check(){ if eval "$2"; then ok "$1"; else bad "$1 (expr: $2)"; fi; }

# ---- stub CLIs -------------------------------------------------------------
# The claude stub records `label<space>detail`, where detail is the /mcp/ URL for
# the new native-http wiring, or the literal "uvx-mcp-obsidian" for a legacy
# `-- uvx mcp-obsidian` add (so is_legacy detection can be exercised).
mkdir -p "$SANDBOX/bin"
CLAUDE_STATE="$SANDBOX/claude-servers.txt"; : > "$CLAUDE_STATE"
cat > "$SANDBOX/bin/claude" <<STUB
#!/usr/bin/env bash
state="$CLAUDE_STATE"
[ "\$1" = mcp ] || exit 0
shift
case "\$1" in
  add)
    label="\$2"; detail=""; shift 2
    while [ \$# -gt 0 ]; do
      case "\$1" in
        --transport) [ "\$2" = http ] && { detail="\$3"; shift; }; shift ;;
        mcp-obsidian) detail="uvx-mcp-obsidian" ;;
      esac
      shift
    done
    grep -q "^\$label " "\$state" 2>/dev/null || echo "\$label \$detail" >> "\$state" ;;
  get)   grep -q "^\$2 " "\$state" 2>/dev/null || exit 1
         echo "\$2"; echo "  \$(grep "^\$2 " "\$state" | head -1 | cut -d' ' -f2-)" ;;
  remove) grep -v "^\$2 " "\$state" > "\$state.tmp" 2>/dev/null; mv "\$state.tmp" "\$state" ;;
  list)  awk '{print \$1}' "\$state" 2>/dev/null ;;
esac
STUB
cat > "$SANDBOX/bin/codex" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
# stub curl so lib_provision_plugins runs offline (release lookup fails gracefully)
cat > "$SANDBOX/bin/curl" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
chmod +x "$SANDBOX/bin/claude" "$SANDBOX/bin/codex" "$SANDBOX/bin/curl"
export PATH="$SANDBOX/bin:$PATH"

# ---- sandbox env -----------------------------------------------------------
export CLAUDE_DESKTOP_CONFIG="$SANDBOX/claude_desktop_config.json"
export CODEX_HOME="$SANDBOX/.codex"
mkdir -p "$CODEX_HOME"
cat > "$CODEX_HOME/config.toml" <<'TOML'
model = "gpt-5-codex"

[mcp_servers.unrelated]
command = "foo"
args = ["bar"]
TOML

# shellcheck disable=SC1091
. "$ROOT/setup/lib.sh"

echo "== url / insecure-port helpers =="
check "insecure port of 27124 is 27123" "[ \"\$(lib_insecure_port 27124)\" = 27123 ]"
check "mcp url for 27124 targets 27123"  "[ \"\$(lib_mcp_url 27124)\" = 'http://127.0.0.1:27123/mcp/' ]"

echo "== free-port allocation (reads ports out of /mcp/ URLs) =="
export LIB_FAKE_LISTENING=""   # hermetic: nothing listening on this host
p1="$(lib_alloc_free_port)"
check "first allocation is 27124" "[ '$p1' = 27124 ]"
LIB_FAKE_LISTENING="27124 27123" p_live="$(lib_alloc_free_port)"
check "listening 27124 forces 27126" "[ '$p_live' = 27126 ]"
# wiring a vault at 27124 must reserve it via its URL's insecure port (27123)
mcp_claude_desktop_wire "obsidian-alpha" 27124 "keyA" >/dev/null 2>&1
p2="$(lib_alloc_free_port)"
check "URL-reserved 27124 skips to 27126" "[ '$p2' = 27126 ]"

echo "== provision writes the allocated port into data.json =="
FAKE_VAULT="$SANDBOX/vault"
mkdir -p "$FAKE_VAULT/.obsidian/plugins/obsidian-local-rest-api"
: > "$FAKE_VAULT/.obsidian/plugins/obsidian-local-rest-api/main.js"
lib_provision_plugins "$FAKE_VAULT" 27126 "provKey" >/dev/null 2>&1
dj="$FAKE_VAULT/.obsidian/plugins/obsidian-local-rest-api/data.json"
check "data.json https port = 27126"    "[ \"\$(jq -r .port '$dj')\" = 27126 ]"
check "data.json insecure port = 27125" "[ \"\$(jq -r .insecurePort '$dj')\" = 27125 ]"
check "data.json insecure server on"    "[ \"\$(jq -r .enableInsecureServer '$dj')\" = true ]"
check "rest-api-key file written"       "[ \"\$(cat '$FAKE_VAULT/.obsidian/.rest-api-key')\" = provKey ]"

echo "== wire across all present clients (plugin endpoint) =="
for_each_client wire "obsidian-beta" "$p2" "keyB" >/dev/null 2>&1
check "desktop has obsidian-beta"      "mcp_exists claude_desktop obsidian-beta"
check "claude code has obsidian-beta"  "mcp_exists claude_code obsidian-beta"
check "codex has obsidian-beta"        "mcp_exists codex_cli obsidian-beta"
check "desktop entry is mcp-remote bridge" "jq -e '.mcpServers[\"obsidian-beta\"].args | index(\"mcp-remote\")' '$CLAUDE_DESKTOP_CONFIG' >/dev/null"
check "desktop entry targets insecure 27125" "jq -r '.mcpServers[\"obsidian-beta\"].args[]' '$CLAUDE_DESKTOP_CONFIG' | grep -q '127.0.0.1:27125/mcp/'"
check "desktop entry has NO OBSIDIAN_PORT env" "! jq -e '.mcpServers[\"obsidian-beta\"].env.OBSIDIAN_PORT' '$CLAUDE_DESKTOP_CONFIG' >/dev/null 2>&1"
check "codex entry targets insecure 27125" "grep -q '127.0.0.1:27125/mcp/' '$CODEX_HOME/config.toml'"
check "codex toml still has unrelated table" "grep -q '\\[mcp_servers.unrelated\\]' '$CODEX_HOME/config.toml'"
check "codex toml still has top-level model"  "grep -q '^model = ' '$CODEX_HOME/config.toml'"

echo "== append-only / idempotent (no clobber) =="
mcp_claude_desktop_wire "obsidian-beta" 29999 "keyX" >/dev/null 2>&1
check "desktop re-wire did not change the URL" "jq -r '.mcpServers[\"obsidian-beta\"].args[]' '$CLAUDE_DESKTOP_CONFIG' | grep -q '127.0.0.1:27125/mcp/'"
beta_count="$(grep -c '^\[mcp_servers.obsidian-beta\]$' "$CODEX_HOME/config.toml")"
check "codex re-wire did not duplicate table" "[ '$beta_count' = 1 ]"

echo "== legacy uvx detection + eradication (mcp_ensure) =="
# forge a legacy uvx entry on every client, as an old setup.sh would have left it
jq '.mcpServers["obsidian-legacy"] = {command:"/x/uvx", args:["mcp-obsidian"], env:{OBSIDIAN_API_KEY:"k",OBSIDIAN_PORT:"27124"}}' \
  "$CLAUDE_DESKTOP_CONFIG" > "$CLAUDE_DESKTOP_CONFIG.t" && mv "$CLAUDE_DESKTOP_CONFIG.t" "$CLAUDE_DESKTOP_CONFIG"
printf '\n[mcp_servers.obsidian-legacy]\ncommand = "/x/uvx"\nargs = ["mcp-obsidian"]\n\n[mcp_servers.obsidian-legacy.env]\nOBSIDIAN_PORT = "27124"\n' >> "$CODEX_HOME/config.toml"
echo "obsidian-legacy uvx-mcp-obsidian" >> "$CLAUDE_STATE"
check "desktop detects legacy uvx"  "mcp_is_legacy claude_desktop obsidian-legacy"
check "codex detects legacy uvx"    "mcp_is_legacy codex_cli obsidian-legacy"
check "claude code detects legacy uvx" "mcp_is_legacy claude_code obsidian-legacy"
check "a plugin-endpoint entry is NOT legacy" "! mcp_is_legacy claude_desktop obsidian-beta"
for_each_client ensure "obsidian-legacy" 27124 "legKey" >/dev/null 2>&1
check "ensure rewrote desktop off uvx"  "! mcp_is_legacy claude_desktop obsidian-legacy"
check "ensure rewrote codex off uvx"    "! mcp_is_legacy codex_cli obsidian-legacy"
check "ensure desktop now targets 27123" "jq -r '.mcpServers[\"obsidian-legacy\"].args[]' '$CLAUDE_DESKTOP_CONFIG' | grep -q '127.0.0.1:27123/mcp/'"
check "ensure of a correct entry is a no-op" "mcp_ensure claude_desktop obsidian-beta 27126 keyB; jq -r '.mcpServers[\"obsidian-beta\"].args[]' '$CLAUDE_DESKTOP_CONFIG' | grep -q '127.0.0.1:27125/mcp/'"
for_each_client unwire "obsidian-legacy" >/dev/null 2>&1

echo "== list / rename / unwire =="
check "desktop lists obsidian-alpha" "mcp_list claude_desktop | grep -qx obsidian-alpha"
check "codex lists obsidian-beta"    "mcp_list codex_cli | grep -qx obsidian-beta"
for_each_client rename "obsidian-beta" "obsidian-gamma" "$p2" "keyB" >/dev/null 2>&1
check "desktop renamed: gamma present" "mcp_exists claude_desktop obsidian-gamma"
check "desktop renamed: beta gone"     "! mcp_exists claude_desktop obsidian-beta"
check "codex renamed: gamma present"   "mcp_exists codex_cli obsidian-gamma"
check "codex still has unrelated after rename" "grep -q '\\[mcp_servers.unrelated\\]' '$CODEX_HOME/config.toml'"
for_each_client unwire "obsidian-gamma" >/dev/null 2>&1
check "desktop unwired gamma" "! mcp_exists claude_desktop obsidian-gamma"
check "codex unwired gamma"   "! mcp_exists codex_cli obsidian-gamma"

echo "== mcp label derivation (no double-prefix) =="
check "'Obsidian Puma' -> obsidian-puma" "[ \"\$(lib_mcp_label 'Obsidian Puma')\" = obsidian-puma ]"
check "'My KB' -> obsidian-my-kb"        "[ \"\$(lib_mcp_label 'My KB')\" = obsidian-my-kb ]"
check "'Object3' -> obsidian-object3"    "[ \"\$(lib_mcp_label 'Object3')\" = obsidian-object3 ]"

echo "== sync-mcp: converge a vault into every client + eradicate mcp-obsidian =="
# a legacy `mcp-obsidian` name lingering on desktop must be eradicated
jq '.mcpServers["mcp-obsidian"] = {command:"/x/uvx", args:["mcp-obsidian"], env:{OBSIDIAN_PORT:"27124"}}' \
  "$CLAUDE_DESKTOP_CONFIG" > "$CLAUDE_DESKTOP_CONFIG.t" && mv "$CLAUDE_DESKTOP_CONFIG.t" "$CLAUDE_DESKTOP_CONFIG"
SV="$SANDBOX/syncvault"
mkdir -p "$SV/.agents" "$SV/.obsidian/plugins/obsidian-local-rest-api"
printf 'vault_name:  "Sync Vault"\n' > "$SV/.agents/vault-profile.md"
printf '{"port":27130,"insecurePort":27129,"enableInsecureServer":true,"apiKey":"svKey"}' > "$SV/.obsidian/plugins/obsidian-local-rest-api/data.json"
printf 'svKey' > "$SV/.obsidian/.rest-api-key"
bash "$ROOT/setup/sync-mcp.sh" --fix --yes "$SV" >/dev/null 2>&1
check "sync wired desktop obsidian-sync-vault"     "mcp_exists claude_desktop obsidian-sync-vault"
check "sync wired codex obsidian-sync-vault"        "mcp_exists codex_cli obsidian-sync-vault"
check "sync wired claude-code obsidian-sync-vault"  "mcp_exists claude_code obsidian-sync-vault"
check "sync entry targets insecure 27129"           "jq -r '.mcpServers[\"obsidian-sync-vault\"].args[]' '$CLAUDE_DESKTOP_CONFIG' | grep -q '127.0.0.1:27129/mcp/'"
check "sync eradicated legacy mcp-obsidian"          "! mcp_exists claude_desktop mcp-obsidian"
# second run is a clean no-op → exit 0 in check mode
bash "$ROOT/setup/sync-mcp.sh" --check "$SV" >/dev/null 2>&1; sync_rc=$?
check "sync-mcp --check is converged (exit 0)" "[ $sync_rc -eq 0 ]"

echo "== wholesale removal (uninstall's loop) =="
for_each_client wire "obsidian-one" 27140 "k1" >/dev/null 2>&1
for c in $MCP_ALL_CLIENTS; do
  mcp_client_present "$c" || continue
  for l in $(mcp_list "$c"); do mcp_unwire "$c" "$l"; done
done
check "desktop: no obsidian servers remain" "[ -z \"\$(mcp_list claude_desktop)\" ]"
check "codex: no obsidian servers remain"   "[ -z \"\$(mcp_list codex_cli)\" ]"
check "claude code: no obsidian servers remain" "[ -z \"\$(mcp_list claude_code)\" ]"

echo
if [ "$FAIL" -eq 0 ]; then
  printf '\033[1;32m✓ all %d checks passed\033[0m\n' "$PASS"; exit 0
else
  printf '\033[1;31m✗ %d/%d checks failed\033[0m\n' "$FAIL" "$((PASS+FAIL))"; exit 1
fi
