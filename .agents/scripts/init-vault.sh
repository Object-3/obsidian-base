#!/usr/bin/env bash
# ── ENGINE FILE (base-owned) — AGENT NOTICE ─────────────────────────────────
# In a DERIVED VAULT (git origin is not the obsidian-base repo): if this script
# is buggy, do NOT fix it here and do NOT open a PR against the base repo —
# FILE A GITHUB ISSUE against the upstream base (.agents/.base-url if present,
# else Object-3/obsidian-base) with the error + proposed fix in the issue body.
# Local patches are overwritten by the next update-base and help no other clone.
# See AGENTS.md → "Engine bugs & improvements found in a derived vault".
# ─────────────────────────────────────────────────────────────────────────────
# One-time onboarding for a vault created from obsidian-base-vault.
# Fills {{PLACEHOLDERS}} in the per-vault files (.agents/vault-profile.md, index.md,
# llms.txt, log.md, README.md) with your vault's name, tagline, purpose, and primary
# tag — clears the base's own example notes (flagged `base_seed: true`), then offers
# to run the skill sync. AGENTS.md is base-owned and untouched.
# Fast and idempotent (re-running only replaces remaining placeholders; the clear step
# only ever removes flagged base notes, never your own).
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

# Wire the repo's tracked git hooks (e.g. the large-file size guard). Idempotent.
if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 && [ -d "$ROOT/.githooks" ]; then
  git -C "$ROOT" config core.hooksPath .githooks
  chmod +x "$ROOT/.githooks/"* 2>/dev/null || true
  echo "git hooks enabled (core.hooksPath=.githooks)"
fi

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

# Seed the self-improvement backbone (the /vault-dream loop). BOTH are created only if
# ABSENT, so re-running init on a live vault never resets an advanced watermark (which
# otherwise advances only when the dream's PR merges) or clobbers a populated hot.md. A
# fresh vault gets a baseline watermark; the first dream then consolidates from there.
if [ ! -f "$ROOT/.agents/dream-state" ]; then
  date -u +"%Y-%m-%dT%H:%M:%SZ" > "$ROOT/.agents/dream-state"
fi
if [ ! -s "$ROOT/hot.md" ]; then
  cat > "$ROOT/hot.md" <<'HOT'
# Hot — recent context

> **Read this first.** A short (~500-word) cache of *what changed recently* and *what's
> active right now* — the fast-orient layer above [`index.md`](index.md) (the full
> catalog) and [`log.md`](log.md) (the full history). Skim `hot.md` to get current fast;
> drop to `index.md` when you need the whole map.

_Empty until the first consolidation pass._ The **`/vault-dream`** skill refreshes this
file at the end of each run — it distills the most recent additions, decisions, and open
threads here so the next agent (or you) starts oriented without reading the whole log.
Until then, start from `index.md`.
HOT
fi
echo "Seeded dream watermark (.agents/dream-state) + hot.md recent-context cache."

# Clear the base's own example notes (flagged `base_seed: true` in frontmatter). They
# document how the base itself was built — useful in the base repo, noise in a fork.
# Only flagged notes are ever removed, so YOUR notes are always safe, even on a re-run.
seeds=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  rm -f "$f" && seeds=$((seeds+1))
done < <(grep -rl --include='*.md' --exclude-dir='.*' -E '^base_seed:[[:space:]]*true' . 2>/dev/null || true)
if [ "$seeds" -gt 0 ]; then
  echo "Cleared $seeds base example note(s); docs/knowledge/ now fills with YOUR learnings as you work."
fi

run="${1:-}"
if [ "$run" != "--yes" ] && [ -t 0 ]; then
  read -r -p "Run the skill sync now? [Y/n]: " a || true
  case "${a:-Y}" in [Nn]*) run="" ;; *) run="--yes" ;; esac
fi
[ "$run" = "--yes" ] && { "$ROOT/.agents/scripts/sync-skills.sh" || echo "(sync skipped/failed; run it later)"; }

echo "Done. Open the folder in Obsidian and start writing (see AGENTS.md + .agents/vault-profile.md)."
