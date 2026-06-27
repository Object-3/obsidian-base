#!/usr/bin/env bash
# One-time onboarding for a vault created from obsidian-base-vault.
# Fills {{PLACEHOLDERS}} in the per-vault files (.agents/vault-profile.md, index.md,
# llms.txt, log.md, README.md) with your vault's name, tagline, purpose, and primary
# tag — then offers to run the skill sync. AGENTS.md is base-owned and untouched.
# Fast and idempotent (re-running only replaces remaining placeholders).
#
# Non-interactive:
#   VAULT_NAME="My KB" VAULT_TAGLINE="..." VAULT_PURPOSE="..." PRIMARY_TAG=mykb \
#     .agents/scripts/init-vault.sh --yes
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

ask() { # var prompt default
  local var="$1" prompt="$2" def="${3:-}" val
  if [ -n "${!var:-}" ]; then return; fi
  if [ -t 0 ]; then read -r -p "$prompt${def:+ [$def]}: " val || true; fi
  printf -v "$var" '%s' "${val:-$def}"
}

echo "== base vault onboarding =="
ask VAULT_NAME    "Vault name"                            "My Knowledge Base"
ask VAULT_TAGLINE "One-line description (tagline)"        "An agent-ready knowledge base."
ask VAULT_PURPOSE "What this KB is about (a sentence)"    "Notes and decisions on the topics I care about."
ask PRIMARY_TAG   "Primary tag (lowercase, every note)"  "kb"
PRIMARY_TAG="$(printf '%s' "$PRIMARY_TAG" | tr '[:upper:] ' '[:lower:]-' | tr -cd 'a-z0-9-')"

# Per-vault files only — never AGENTS.md (base-owned).
FILES=(.agents/vault-profile.md index.md llms.txt log.md README.md)
sub() { # token value
  local token="$1" value="$2" f
  for f in "${FILES[@]}"; do
    [ -f "$f" ] || continue
    python3 - "$f" "$token" "$value" <<'PY'
import sys
p, tok, val = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p, encoding="utf-8").read()
open(p, "w", encoding="utf-8").write(s.replace(tok, val))
PY
  done
}
sub "{{VAULT_NAME}}"    "$VAULT_NAME"
sub "{{VAULT_TAGLINE}}" "$VAULT_TAGLINE"
sub "{{VAULT_PURPOSE}}" "$VAULT_PURPOSE"
sub "{{PRIMARY_TAG}}"   "$PRIMARY_TAG"

echo
echo "Profile set: name='$VAULT_NAME'  tag='$PRIMARY_TAG'  (see .agents/vault-profile.md)"

run="${1:-}"
if [ "$run" != "--yes" ] && [ -t 0 ]; then
  read -r -p "Run the skill sync now? [Y/n]: " a || true
  case "${a:-Y}" in [Nn]*) run="" ;; *) run="--yes" ;; esac
fi
[ "$run" = "--yes" ] && { "$ROOT/.agents/scripts/sync-skills.sh" || echo "(sync skipped/failed; run it later)"; }

echo "Done. Open the folder in Obsidian and start writing (see AGENTS.md + .agents/vault-profile.md)."
