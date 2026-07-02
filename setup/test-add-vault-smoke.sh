#!/usr/bin/env bash
# ===========================================================================
# Smoke test for setup/lib.sh — the multi-vault / multi-client wiring core.
# ===========================================================================
# Runs fully offline in a sandbox: temp Claude Desktop config, a stub `claude`
# CLI, a stub `codex` CLI, and a temp CODEX_HOME. Asserts free-port allocation,
# append-only + idempotent wiring across all three clients, rename, unwire, and
# that unrelated Codex config survives edits.
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
mkdir -p "$SANDBOX/bin"
CLAUDE_STATE="$SANDBOX/claude-servers.txt"; : > "$CLAUDE_STATE"
cat > "$SANDBOX/bin/claude" <<STUB
#!/usr/bin/env bash
# minimal 'claude mcp' stub: add/get/remove/list backed by $CLAUDE_STATE
state="$CLAUDE_STATE"
[ "\$1" = mcp ] || exit 0
shift
case "\$1" in
  add)
    label="\$2"; port=""
    while [ \$# -gt 0 ]; do case "\$1" in --env) case "\$2" in OBSIDIAN_PORT=*) port="\${2#OBSIDIAN_PORT=}";; esac; shift;; esac; shift; done
    grep -q "^\$label " "\$state" 2>/dev/null || echo "\$label \$port" >> "\$state" ;;
  get)   grep -q "^\$2 " "\$state" 2>/dev/null || exit 1
         echo "\$2  OBSIDIAN_PORT: \$(grep "^\$2 " "\$state" | awk '{print \$2}')" ;;
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
# a pre-existing, unrelated Codex config that must survive our edits
cat > "$CODEX_HOME/config.toml" <<'TOML'
model = "gpt-5-codex"

[mcp_servers.unrelated]
command = "foo"
args = ["bar"]
TOML

# shellcheck disable=SC1091
. "$ROOT/setup/lib.sh"

echo "== free-port allocation =="
export LIB_FAKE_LISTENING=""   # hermetic: nothing listening on this host, per the test
p1="$(lib_alloc_free_port)"
check "first allocation is 27124" "[ '$p1' = 27124 ]"
# a live socket on 27124 (and its insecure partner) forces the next even pair
LIB_FAKE_LISTENING="27124 27123" p_live="$(lib_alloc_free_port)"
check "listening 27124 forces 27126" "[ '$p_live' = 27126 ]"
# simulate 27124 already claimed by wiring a vault, then allocate again
mcp_claude_desktop_wire "obsidian-alpha" 27124 "keyA" >/dev/null 2>&1
p2="$(lib_alloc_free_port)"
check "config-reserved 27124 skips to 27126" "[ '$p2' = 27126 ]"

echo "== provision writes the allocated port into data.json =="
FAKE_VAULT="$SANDBOX/vault"
mkdir -p "$FAKE_VAULT/.obsidian/plugins/obsidian-local-rest-api"
: > "$FAKE_VAULT/.obsidian/plugins/obsidian-local-rest-api/main.js"   # so the data.json branch runs
lib_provision_plugins "$FAKE_VAULT" 27126 "provKey" >/dev/null 2>&1
dj="$FAKE_VAULT/.obsidian/plugins/obsidian-local-rest-api/data.json"
check "data.json https port = 27126"    "[ \"\$(jq -r .port '$dj')\" = 27126 ]"
check "data.json insecure port = 27125" "[ \"\$(jq -r .insecurePort '$dj')\" = 27125 ]"
check "rest-api-key file written"       "[ \"\$(cat '$FAKE_VAULT/.obsidian/.rest-api-key')\" = provKey ]"

echo "== wire across all present clients =="
for_each_client wire "obsidian-beta" "$p2" "keyB" >/dev/null 2>&1
check "desktop has obsidian-beta"      "mcp_exists claude_desktop obsidian-beta"
check "claude code has obsidian-beta"  "mcp_exists claude_code obsidian-beta"
check "codex has obsidian-beta"        "mcp_exists codex_cli obsidian-beta"
check "codex toml still has unrelated table" "grep -q '\\[mcp_servers.unrelated\\]' '$CODEX_HOME/config.toml'"
check "codex toml still has top-level model"  "grep -q '^model = ' '$CODEX_HOME/config.toml'"

echo "== append-only / idempotent (no clobber) =="
# re-wire with a DIFFERENT port; must NOT change the existing entry
mcp_claude_desktop_wire "obsidian-beta" 29999 "keyX" >/dev/null 2>&1
got="$(jq -r '.mcpServers["obsidian-beta"].env.OBSIDIAN_PORT' "$CLAUDE_DESKTOP_CONFIG")"
check "desktop re-wire did not clobber port" "[ '$got' = '$p2' ]"
beta_count="$(grep -c '^\[mcp_servers.obsidian-beta\]$' "$CODEX_HOME/config.toml")"
check "codex re-wire did not duplicate table" "[ '$beta_count' = 1 ]"

echo "== list obsidian labels =="
check "desktop lists obsidian-alpha" "mcp_list claude_desktop | grep -qx obsidian-alpha"
check "codex lists obsidian-beta"    "mcp_list codex_cli | grep -qx obsidian-beta"

echo "== rename (wire new + unwire old) across clients =="
for_each_client rename "obsidian-beta" "obsidian-gamma" "$p2" "keyB" >/dev/null 2>&1
check "desktop renamed: gamma present" "mcp_exists claude_desktop obsidian-gamma"
check "desktop renamed: beta gone"     "! mcp_exists claude_desktop obsidian-beta"
check "codex renamed: gamma present"   "mcp_exists codex_cli obsidian-gamma"
check "codex renamed: beta gone"       "! mcp_exists codex_cli obsidian-beta"
check "codex still has unrelated table after rename" "grep -q '\\[mcp_servers.unrelated\\]' '$CODEX_HOME/config.toml'"

echo "== unwire =="
for_each_client unwire "obsidian-gamma" >/dev/null 2>&1
check "desktop unwired gamma" "! mcp_exists claude_desktop obsidian-gamma"
check "codex unwired gamma"   "! mcp_exists codex_cli obsidian-gamma"
check "unwire of absent label is a no-op" "mcp_unwire codex_cli obsidian-nope; true"

echo
if [ "$FAIL" -eq 0 ]; then
  printf '\033[1;32m✓ all %d checks passed\033[0m\n' "$PASS"; exit 0
else
  printf '\033[1;31m✗ %d/%d checks failed\033[0m\n' "$FAIL" "$((PASS+FAIL))"; exit 1
fi
