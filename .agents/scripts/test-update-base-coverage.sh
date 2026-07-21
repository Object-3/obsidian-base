#!/usr/bin/env bash
# ── ENGINE FILE (base-owned) — AGENT NOTICE ─────────────────────────────────
# In a DERIVED VAULT (git origin is not the obsidian-base repo): if this script
# is buggy, do NOT fix it here and do NOT open a PR against the base repo —
# FILE A GITHUB ISSUE against the upstream base (.agents/.base-url if present,
# else Object-3/obsidian-base) with the error + proposed fix in the issue body.
# Local patches are overwritten by the next update-base and help no other clone.
# See AGENTS.md → "Engine bugs & improvements found in a derived vault".
# ─────────────────────────────────────────────────────────────────────────────
# Completeness guard for update-base.sh's overlay coverage.
#
# THE BUG THIS EXISTS FOR (issue #38): update-base.sh's PATHS array is a
# hand-maintained allowlist of base-owned engine paths. When a new base-owned
# file is added that lives OUTSIDE an already-listed directory (e.g. a new file
# directly under .agents/, like .agents/mcp-quick-orient.md), nothing forces the
# maintainer to add it to PATHS — so a stale fork can never pick it up via
# /update-base, silently. Adding one line to PATHS fixes the instance; this test
# fixes the CLASS: it fails loudly the moment ANY tracked file is neither
# overlaid nor explicitly classified as vault-owned.
#
# HOW: every tracked file in the base repo must fall into exactly one bucket —
#   1. OVERLAID     — update-base.sh copies it into forks. Derived live from the
#                     real PATHS array + the same base-authored-skill derivation
#                     update-base itself uses (so this can't drift from the script).
#   2. VAULT-OWNED  — per-vault content update-base must NEVER touch (notes, the
#                     vendored skills/agents, vault-profile, the lock, .obsidian, …).
# A file matching NEITHER is UNCLASSIFIED → the maintainer added something without
# deciding whether forks should receive it → FAIL. Overlay wins over vault-owned
# (precedence), so the broad vault-owned buckets below can safely overlap overlay
# territory (e.g. .agents/skills holds both overlaid base skills and vendored ones;
# .obsidian holds the one overlaid snippet among vault config).
#
# Also runs a deterministic case matrix (block / pass / false-positive) proving the
# guard mechanism itself, then asserts the REAL repo tree is fully classified.
#
#   .agents/scripts/test-update-base-coverage.sh
#
# Exits non-zero if any assertion fails. Offline, no network, no side effects.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
UPDATE_BASE="$ROOT/.agents/scripts/update-base.sh"
LOCK="$ROOT/.agents/skill-sources.lock.json"

fail=0
note() { printf '%s\n' "$*"; }
ok()   { printf '  ok: %s\n' "$*"; }
bad()  { printf '  FAIL: %s\n' "$*"; fail=1; }

# ── Overlay spec, parsed from the REAL update-base.sh so it can never drift ──
# Pull the quoted entries out of the PATHS=( … ) array literal. We only take lines
# whose first non-space char is a double-quote, so the comment lines inside the
# array (some of which contain "quoted phrases") are ignored.
parse_paths_array() {
  sed -n '/^PATHS=(/,/^)/p' "$UPDATE_BASE" \
    | grep -E '^[[:space:]]*"' \
    | grep -oE '"[^"]+"' | tr -d '"'
}

# base-AUTHORED skills — mirror update-base.sh's own derivation exactly: a skill
# dir under .agents/skills/ that the base did NOT vendor (absent from the lock's
# .skills[]) is base-authored and therefore overlaid. Vendored ones arrive via
# sync-skills and are vault-owned here.
base_authored_skills() {
  command -v jq >/dev/null 2>&1 || return 0
  local vendored
  vendored="$(jq -r '.skills[]?' "$LOCK" 2>/dev/null | sort -u)" || return 0
  comm -23 \
    <(git -C "$ROOT" ls-files .agents/skills \
        | sed -n 's#^\.agents/skills/\([^/]*\)/SKILL\.md$#\1#p' | sort -u) \
    <(printf '%s\n' "$vendored") \
    | sed 's#^#.agents/skills/#'
}

# ── The partition check (pure): reads a file list on stdin, prints every file
# that matches neither the OVERLAY nor the VAULT globs. Prefix-match semantics:
# a glob G matches path P when P == G or P starts with "G/" (whole file or dir),
# the same way update-base.sh treats a PATHS entry. Returns 1 if any unclassified.
# Args: writes overlay globs to $1 file, vault globs to $2 file (one per line).
partition_check() {
  local overlay_file="$1" vault_file="$2" f g matched unclassified=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    matched=0
    while IFS= read -r g; do
      [ -n "$g" ] || continue
      if [[ "$f" == "$g" || "$f" == "$g"/* ]]; then matched=1; break; fi
    done <"$overlay_file"
    if [ "$matched" -eq 0 ]; then
      while IFS= read -r g; do
        [ -n "$g" ] || continue
        if [[ "$f" == "$g" || "$f" == "$g"/* ]]; then matched=1; break; fi
      done <"$vault_file"
    fi
    [ "$matched" -eq 0 ] && { printf '%s\n' "$f"; unclassified=1; }
  done
  return "$unclassified"
}

# Vault-owned buckets (broad; overlay wins on overlap). Everything a fork owns and
# update-base must never overlay. New per-vault content lands under one of these;
# a NEW engine file will not, so it surfaces as unclassified — by design.
vault_globs() {
  cat <<'EOF'
README.md
index.md
log.md
hot.md
llms.txt
docs
plans
raw
assets
_sensitive
.agents/vault-profile.md
.agents/skill-sources.lock.json
.agents/skill-sources.local.json
.agents/dream-state
.agents/agents
.agents/skills
.claude/agents
.claude/skills
.claude/commands
.codex
.obsidian
EOF
}

# ── Case matrix: prove the mechanism on tiny synthetic inputs (no git, no agent) ──
note "== case matrix (mechanism) =="
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
ov="$tmp/ov"; va="$tmp/va"
printf '%s\n' "AGENTS.md" ".agents/scripts" ".agents/mcp-quick-orient.md" >"$ov"
vault_globs >"$va"

# A. block: a new engine-ish file under .agents/ that's in neither bucket
out="$(printf '%s\n' ".agents/scripts/foo.sh" ".agents/brand-new-engine.md" | partition_check "$ov" "$va")"; rc=$?
if [ "$rc" -ne 0 ] && [ "$out" = ".agents/brand-new-engine.md" ]; then
  ok "block: unlisted engine file flagged (.agents/brand-new-engine.md)"
else
  bad "block case: rc=$rc out='$out' (expected rc=1 flagging brand-new-engine.md)"
fi

# B. pass: every file is overlaid or vault-owned
out="$(printf '%s\n' "AGENTS.md" ".agents/scripts/foo.sh" "docs/knowledge/x.md" ".agents/skills/some-vendored/SKILL.md" | partition_check "$ov" "$va")"; rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  ok "pass: fully-classified tree reports clean"
else
  bad "pass case: rc=$rc out='$out' (expected rc=0, empty)"
fi

# C. false-positive guard: vault content under a broad bucket must NOT be flagged
out="$(printf '%s\n' "index.md" ".obsidian/app.json" ".agents/agents/foo.md" | partition_check "$ov" "$va")"; rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  ok "false-positive: vault-owned content not flagged"
else
  bad "false-positive case: rc=$rc out='$out' (expected rc=0, empty)"
fi

# D. regression: with mcp-quick-orient.md REMOVED from overlay (the pre-#38 state),
# it must surface as unclassified — proving the guard would have caught bug #1.
printf '%s\n' "AGENTS.md" ".agents/scripts" >"$ov"   # note: no mcp-quick-orient.md
out="$(printf '%s\n' ".agents/mcp-quick-orient.md" | partition_check "$ov" "$va")"; rc=$?
if [ "$rc" -ne 0 ] && [ "$out" = ".agents/mcp-quick-orient.md" ]; then
  ok "regression: pre-#38 overlay (missing mcp-quick-orient.md) flagged"
else
  bad "regression case: rc=$rc out='$out' (expected it flagged)"
fi

# ── Live guard: the REAL repo tree must be fully classified ──
note "== live guard (real repo tree) =="
{ parse_paths_array; base_authored_skills; } | sort -u >"$ov"
vault_globs >"$va"
unclassified="$(git -C "$ROOT" ls-files | partition_check "$ov" "$va")"; rc=$?
if [ "$rc" -eq 0 ] && [ -z "$unclassified" ]; then
  ok "every tracked file is overlaid or vault-owned"
else
  bad "unclassified tracked files (add to update-base.sh PATHS, or to vault_globs here):"
  printf '%s\n' "$unclassified" | sed 's/^/         /'
fi

echo
if [ "$fail" -eq 0 ]; then echo "PASS: update-base overlay coverage"; else echo "FAIL: update-base overlay coverage"; fi
exit "$fail"
