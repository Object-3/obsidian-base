#!/usr/bin/env bash
# ===========================================================================
# Integration test for setup/add-vault.sh — offline, end to end.
# ===========================================================================
# Builds a minimal local "base" repo (no network), simulates an existing vault
# with a legacy `mcp-obsidian` connection, then runs add-vault.sh and asserts:
#   - the legacy connection was migrated to the existing vault's name
#   - the new vault was created, personalized, and provisioned on a FREE port
#   - the new vault is wired under obsidian-<slug> across all clients
#   - the two vaults have isolated ports; the existing entry is preserved
#
#   bash setup/test-add-vault-integration.sh
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SB="$(mktemp -d)"; trap 'rm -rf "$SB"' EXIT
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  \033[1;32mok\033[0m   %s\n' "$*"; }
bad(){ FAIL=$((FAIL+1)); printf '  \033[1;31mFAIL\033[0m %s\n' "$*"; }
chk(){ if eval "$2"; then ok "$1"; else bad "$1"; fi; }

# ---- stub CLIs -------------------------------------------------------------
mkdir -p "$SB/bin"; CLST="$SB/claude.txt"; : > "$CLST"
cat > "$SB/bin/claude" <<STUB
#!/usr/bin/env bash
state="$CLST"; [ "\$1" = mcp ] || exit 0; shift
case "\$1" in
  add) l="\$2"; p=""; while [ \$# -gt 0 ]; do [ "\$1" = --env ] && case "\$2" in OBSIDIAN_PORT=*) p="\${2#OBSIDIAN_PORT=}";; esac; shift; done; grep -q "^\$l " "\$state" || echo "\$l \$p" >> "\$state";;
  get) grep -q "^\$2 " "\$state" || exit 1;;
  remove) grep -v "^\$2 " "\$state" > "\$state.t" 2>/dev/null; mv "\$state.t" "\$state";;
  list) awk '{print \$1}' "\$state";;
esac
STUB
printf '#!/usr/bin/env bash\nexit 0\n' > "$SB/bin/codex"
printf '#!/usr/bin/env bash\nexit 0\n' > "$SB/bin/curl"   # offline: release lookups fail gracefully
chmod +x "$SB/bin/"*
export PATH="$SB/bin:$PATH"
export CLAUDE_DESKTOP_CONFIG="$SB/cd.json" CODEX_HOME="$SB/.codex" NO_OPEN=1 LIB_FAKE_LISTENING=""

# ---- minimal local base repo ----------------------------------------------
BASE="$SB/base"
mkdir -p "$BASE/setup" "$BASE/.agents/scripts" "$BASE/.obsidian/plugins/obsidian-local-rest-api" "$BASE/.githooks"
cp "$REPO/setup/lib.sh" "$BASE/setup/lib.sh"
# Ship the REAL update-base.sh in the base so the created vault can run it below (asserting
# the ephemeral `base` remote leaves nothing standing).
cp "$REPO/.agents/scripts/update-base.sh" "$BASE/.agents/scripts/update-base.sh"
chmod +x "$BASE/.agents/scripts/update-base.sh"
printf 'vault_name:  "{{VAULT_NAME}}"\n' > "$BASE/.agents/vault-profile.md"
cat > "$BASE/.agents/scripts/init-vault.sh" <<'IV'
#!/usr/bin/env bash
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
sed -i.bak "s/{{VAULT_NAME}}/${VAULT_NAME:-KB}/" "$ROOT/.agents/vault-profile.md" && rm -f "$ROOT/.agents/vault-profile.md.bak"
IV
chmod +x "$BASE/.agents/scripts/init-vault.sh"
: > "$BASE/.obsidian/plugins/obsidian-local-rest-api/main.js"   # so data.json is written
# Pin the base's default branch to `main` — update-base.sh fetches BASE_REF (default main).
( cd "$BASE" && git init -q && git add -A && git -c user.name=t -c user.email=t@t commit -qm base && git branch -M main )

# ---- existing vault with a legacy mcp-obsidian connection ------------------
EXIST="$SB/existing"
mkdir -p "$EXIST/setup" "$EXIST/.agents" "$EXIST/.obsidian/plugins/obsidian-local-rest-api"
cp "$REPO/setup/lib.sh" "$REPO/setup/add-vault.sh" "$EXIST/setup/"; chmod +x "$EXIST/setup/"*.sh
printf 'vault_name:  "Obsidian Strategy"\n' > "$EXIST/.agents/vault-profile.md"
printf '{"port":27124,"insecurePort":27123}' > "$EXIST/.obsidian/plugins/obsidian-local-rest-api/data.json"
printf 'strategyKey' > "$EXIST/.obsidian/.rest-api-key"
# The existing vault tracks its base via .agents/.base-url (NOT a standing `base` remote):
# add-vault inherits it from there.
printf 'file://%s\n' "$BASE" > "$EXIST/.agents/.base-url"
( cd "$EXIST" && git init -q )
# seed the legacy connection across clients (runs under this bash process)
# shellcheck disable=SC1091
. "$REPO/setup/lib.sh"
for_each_client wire "mcp-obsidian" 27124 "strategyKey" >/dev/null 2>&1
chk "seeded legacy mcp-obsidian (desktop)" "mcp_exists claude_desktop mcp-obsidian"

echo "== run add-vault.sh for 'Obsidian Puma' =="
# No BASE_REPO_URL env → add-vault must resolve the base from the existing vault's
# .agents/.base-url (the inheritance path this test now exercises).
VAULT_NAME="Obsidian Puma" PRIMARY_TAG=puma VAULT_PARENT="$SB" \
  bash "$EXIST/setup/add-vault.sh" --yes >/dev/null 2>&1

echo "== assertions =="
chk "legacy renamed → obsidian-strategy (desktop)" "mcp_exists claude_desktop obsidian-strategy"
chk "legacy mcp-obsidian removed (desktop)"        "! mcp_exists claude_desktop mcp-obsidian"
chk "legacy renamed → obsidian-strategy (codex)"   "mcp_exists codex_cli obsidian-strategy"
chk "new obsidian-puma wired (desktop)"            "mcp_exists claude_desktop obsidian-puma"
chk "new obsidian-puma wired (claude code)"        "mcp_exists claude_code obsidian-puma"
chk "new obsidian-puma wired (codex)"              "mcp_exists codex_cli obsidian-puma"
sport="$(jq -r '.mcpServers["obsidian-strategy"].env.OBSIDIAN_PORT' "$CLAUDE_DESKTOP_CONFIG")"
pport="$(jq -r '.mcpServers["obsidian-puma"].env.OBSIDIAN_PORT' "$CLAUDE_DESKTOP_CONFIG")"
chk "existing vault keeps port 27124"              "[ '$sport' = 27124 ]"
chk "new vault got a distinct free port (27126)"   "[ '$pport' = 27126 ]"
chk "new vault data.json port = 27126"             "[ \"\$(jq -r .port '$SB/obsidian-puma/.obsidian/plugins/obsidian-local-rest-api/data.json')\" = 27126 ]"
chk "new vault personalized (name filled)"         "grep -q '\"Obsidian Puma\"' '$SB/obsidian-puma/.agents/vault-profile.md'"
# The `base` remote is ephemeral now: a fresh vault carries NO standing `base` remote and
# instead resolves its base URL from the persisted .agents/.base-url it inherited.
chk "new vault has NO standing base remote"        "! git -C '$SB/obsidian-puma' remote get-url base >/dev/null 2>&1"
chk "new vault base URL persisted (.base-url)"     "grep -qF \"file://$BASE\" '$SB/obsidian-puma/.agents/.base-url'"

echo "== run update-base.sh in the new vault (base remote must not persist) =="
NEWV="$SB/obsidian-puma"
( cd "$NEWV" && bash .agents/scripts/update-base.sh ) >/dev/null 2>&1 || true
chk "no standing 'base' remote after update-base"  "! git -C '$NEWV' remote get-url base >/dev/null 2>&1"

echo
if [ "$FAIL" -eq 0 ]; then printf '\033[1;32m✓ all %d checks passed\033[0m\n' "$PASS"; exit 0
else printf '\033[1;31m✗ %d/%d failed\033[0m\n' "$FAIL" "$((PASS+FAIL))"; exit 1; fi
