#!/usr/bin/env bash
# ===========================================================================
# obsidian-base — migrate the legacy `mcp-obsidian` connection to a vault name
# ===========================================================================
# Older setups wired a single MCP server literally named "mcp-obsidian". Once
# you run more than one vault, connections are named per vault (obsidian-<slug>).
# This renames the legacy entry to your vault's name across every local client
# (Claude Desktop, Claude Code, Codex), keeping the same port + API key.
#
# Run it from inside the vault whose connection you want to rename:
#   ./setup/migrate-mcp-names.sh
#   ./setup/migrate-mcp-names.sh obsidian-strategy   # force the target label
#
# Idempotent and safe to re-run: a clean no-op once migrated. add-vault.sh calls
# this automatically on its first run, so you rarely need it directly.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
. "$ROOT/setup/lib.sh"

have jq || die "jq is required."

MCP_CLIENTS="${MCP_CLIENTS:-all}"
SEL="$(lib_select_clients "$MCP_CLIENTS")"
[ -n "$SEL" ] || { say "No clients selected (MCP_CLIENTS=none) — nothing to do."; exit 0; }

MCP_ALL_CLIENTS="$SEL" lib_migrate_legacy_mcp "$ROOT" "${1:-}"

cat <<'EOF'

If anything was renamed, start a FRESH assistant session (quit/reopen Claude
Desktop, or start a new Claude Code / Codex session) so it picks up the new name.
EOF
