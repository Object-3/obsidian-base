#!/usr/bin/env bash
# ── ENGINE FILE (base-owned) — AGENT NOTICE ─────────────────────────────────
# In a DERIVED VAULT (git origin is not the obsidian-base repo): if this script
# is buggy, do NOT fix it here and do NOT open a PR against the base repo —
# FILE A GITHUB ISSUE against the upstream base (.agents/.base-url if present,
# else Object-3/obsidian-base) with the error + proposed fix in the issue body.
# Local patches are overwritten by the next update-base and help no other clone.
# See AGENTS.md → "Engine bugs & improvements found in a derived vault".
# ─────────────────────────────────────────────────────────────────────────────
# Smoke test for the shipped Obsidian config contract (.obsidian/).
#
# Self-contained and offline — read-only assertions over tracked files. Run
# from anywhere in the repo:
#
#   .agents/scripts/test-obsidian-config-smoke.sh
#
# Guards the split introduced by #41 / PR #77: MCP readability comes from
# keeping dot-folders and log.md OUT of userIgnoreFilters (the Local REST API
# honors that setting even for direct-path reads), while explorer hiding is
# the CSS snippet's job. Covers:
#   1. .obsidian/app.json parses as valid JSON
#   2. userIgnoreFilters contains NONE of .agents/ .claude/ .codex/ log.md
#      (the regression that broke the MCP fast-orient fetch)
#   3. the hide-engine-files.css snippet exists and covers log.md
#   4. appearance.json enables the hide-engine-files snippet
#
# Exits non-zero if any assertion fails.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_JSON="$ROOT/.obsidian/app.json"
APPEARANCE_JSON="$ROOT/.obsidian/appearance.json"
SNIPPET="$ROOT/.obsidian/snippets/hide-engine-files.css"

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "  ok: $*"; }
bad()  { FAIL=$((FAIL+1)); echo "  FAIL: $*"; }
note() { echo "$*"; }

# ── JSON helper: jq if present, else python3 ─────────────────────────────────
json_valid() {
  if command -v jq >/dev/null 2>&1; then jq -e . "$1" >/dev/null 2>&1
  elif command -v python3 >/dev/null 2>&1; then python3 -m json.tool "$1" >/dev/null 2>&1
  else return 2
  fi
}

ignore_filters() {  # print userIgnoreFilters entries, one per line
  if command -v jq >/dev/null 2>&1; then
    jq -r '(.userIgnoreFilters // [])[]' "$1" 2>/dev/null
  else
    python3 -c 'import json,sys
print("\n".join(json.load(open(sys.argv[1])).get("userIgnoreFilters", [])))' "$1" 2>/dev/null
  fi
}

css_snippet_enabled() {  # $1=appearance.json  $2=snippet name
  if command -v jq >/dev/null 2>&1; then
    jq -e --arg s "$2" '(.enabledCssSnippets // []) | index($s) != null' "$1" >/dev/null 2>&1
  else
    python3 -c 'import json,sys
sys.exit(0 if sys.argv[2] in json.load(open(sys.argv[1])).get("enabledCssSnippets", []) else 1)' "$1" "$2" 2>/dev/null
  fi
}

command -v jq >/dev/null 2>&1 || command -v python3 >/dev/null 2>&1 || {
  echo "need jq or python3 to parse JSON"; exit 1; }

# ── 1. app.json parses ───────────────────────────────────────────────────────
note "== app.json validity =="
if [ -f "$APP_JSON" ] && json_valid "$APP_JSON"; then
  ok "app.json parses as valid JSON"
else
  bad "app.json missing or not valid JSON ($APP_JSON)"
fi

# ── 2. no MCP-breaking entries in userIgnoreFilters ──────────────────────────
note "== userIgnoreFilters (MCP readability, #41) =="
filters="$(ignore_filters "$APP_JSON")"
for banned in ".agents/" ".claude/" ".codex/" "log.md"; do
  if printf '%s\n' "$filters" | grep -Fxq "$banned"; then
    bad "userIgnoreFilters contains '$banned' — hides it from the Local REST API and breaks MCP direct-path reads (#41)"
  else
    ok "userIgnoreFilters does not contain '$banned'"
  fi
done

# ── 3. CSS snippet exists and covers log.md ──────────────────────────────────
note "== hide-engine-files.css (explorer hiding) =="
if [ -f "$SNIPPET" ]; then
  ok "snippet exists ($SNIPPET)"
  if grep -Fq 'data-path="log.md"' "$SNIPPET"; then
    ok "snippet hides log.md from the file explorer"
  else
    bad "snippet does not cover log.md — it must, since log.md is no longer in userIgnoreFilters"
  fi
else
  bad "snippet missing ($SNIPPET)"
fi

# ── 4. snippet is enabled in appearance.json ─────────────────────────────────
note "== appearance.json (snippet enabled) =="
if [ -f "$APPEARANCE_JSON" ] && json_valid "$APPEARANCE_JSON" \
   && css_snippet_enabled "$APPEARANCE_JSON" "hide-engine-files"; then
  ok "hide-engine-files listed in enabledCssSnippets"
else
  bad "appearance.json missing/invalid or hide-engine-files not in enabledCssSnippets"
fi

# ── verdict ──────────────────────────────────────────────────────────────────
echo
if [ "$FAIL" -eq 0 ]; then
  echo "PASS: obsidian config smoke ($PASS checks)"
  exit 0
else
  echo "FAIL: obsidian config smoke ($FAIL failure(s), $PASS ok)"
  exit 1
fi
