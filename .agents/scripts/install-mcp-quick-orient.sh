#!/usr/bin/env bash
# ===========================================================================
# install-mcp-quick-orient.sh — install the fast Obsidian MCP orientation
# instruction into a user's GLOBAL agent config
# ===========================================================================
# `.agents/mcp-quick-orient.md` (in this repo) teaches an agent to orient in
# any obsidian-base-derived vault using the fewest possible Obsidian MCP tool
# calls: fetch `.agents/vault-profile.md` once (only when a vault-specific
# fact is actually needed), and treat the rest of the directory/skill
# scaffolding as already known — because it's IDENTICAL across every
# obsidian-base fork. It was produced and measured by a `/ce-optimize` run
# (see .context/compound-engineering/ce-optimize/obsidian-mcp-quick-orient/).
#
# That candidate only helps if it's in the agent's GLOBAL instructions, not
# just this one repo — so it applies automatically in every other project,
# whenever the Obsidian MCP happens to be connected. This script installs it
# there, idempotently (safe to re-run after a base update refreshes the
# candidate text).
#
# Subcommands:
#   detect    (default) Show whether it's already installed and where. Read-only.
#   install   Write/update the managed block in the target file. Idempotent.
#   explain   Print a plain-English "here's what this does" card. Read-only.
#
# Override the target file for testing:  TARGET_FILE=/path/to/file ...
set -euo pipefail

VAULT_ROOT="${VAULT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
SOURCE_FILE="$VAULT_ROOT/.agents/mcp-quick-orient.md"
TARGET_FILE="${TARGET_FILE:-$HOME/.claude/CLAUDE.md}"
BEGIN_MARK="<!-- BEGIN obsidian-mcp-quick-orient (managed by install-mcp-quick-orient.sh) -->"
END_MARK="<!-- END obsidian-mcp-quick-orient -->"

require_source() {
  if [[ ! -f "$SOURCE_FILE" ]]; then
    echo "Error: $SOURCE_FILE not found. This script must be run from an obsidian-base checkout." >&2
    exit 1
  fi
}

is_installed() {
  [[ -f "$TARGET_FILE" ]] && grep -qF "$BEGIN_MARK" "$TARGET_FILE"
}

cmd_detect() {
  require_source
  echo "Source:  $SOURCE_FILE"
  echo "Target:  $TARGET_FILE"
  if is_installed; then
    echo "Status:  installed"
  elif [[ -f "$TARGET_FILE" ]]; then
    echo "Status:  not installed (target file exists, no managed block yet)"
  else
    echo "Status:  not installed (target file doesn't exist yet)"
  fi
}

cmd_install() {
  require_source
  python3 - "$SOURCE_FILE" "$TARGET_FILE" "$BEGIN_MARK" "$END_MARK" <<'PY'
import sys, os

source_file, target_file, begin_mark, end_mark = sys.argv[1:5]

with open(source_file) as f:
    body = f.read().strip("\n")

# Drop the file's own leading HTML-comment header (optimize-run bookkeeping,
# not meant for the installed/global copy) if present.
if body.startswith("<!--"):
    close = body.find("-->")
    if close != -1:
        body = body[close + 3:].lstrip("\n")

block = begin_mark + "\n" + body + "\n" + end_mark

os.makedirs(os.path.dirname(target_file), exist_ok=True)
existing = ""
if os.path.exists(target_file):
    with open(target_file) as f:
        existing = f.read()

if begin_mark in existing and end_mark in existing:
    pre, rest = existing.split(begin_mark, 1)
    _, post = rest.split(end_mark, 1)
    new_content = pre + block + post
    action = "updated"
else:
    sep = "\n\n" if existing and not existing.endswith("\n\n") else ""
    new_content = existing + sep + block + "\n"
    action = "installed"

with open(target_file, "w") as f:
    f.write(new_content)

print(action)
PY
}

cmd_explain() {
  cat <<EOF

What just happened, in plain terms:

Your global Claude Code instructions file ($TARGET_FILE) now has a short,
clearly-marked section (between "$BEGIN_MARK"
and "$END_MARK") that tells any Claude Code
session — in ANY project, not just this vault — how to quickly get its
bearings in an Obsidian vault reached through the Obsidian MCP connector,
as long as that vault is one built from this same "obsidian-base" template.

In practice: instead of poking around the whole vault the first time it
needs an answer, it fetches one small file (the vault's own profile) and
already knows the rest of the layout, because every vault built from this
template shares it. Fewer steps, faster answers, same accuracy.

You don't need to do anything else — it applies automatically the next time
you start a Claude Code session anywhere, whenever an Obsidian vault is
connected. Re-run "install" any time this file changes upstream (e.g. after
a base update) to refresh it; it's safe to run repeatedly.
EOF
}

SUBCOMMAND="${1:-detect}"
case "$SUBCOMMAND" in
  detect) cmd_detect ;;
  install)
    RESULT=$(cmd_install)
    echo "Target:  $TARGET_FILE"
    echo "Status:  $RESULT"
    ;;
  explain) cmd_explain ;;
  *)
    echo "Usage: $0 [detect|install|explain]" >&2
    exit 1
    ;;
esac
