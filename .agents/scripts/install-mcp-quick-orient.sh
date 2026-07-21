#!/usr/bin/env bash
# ── ENGINE FILE (base-owned) — AGENT NOTICE ─────────────────────────────────
# In a DERIVED VAULT (git origin is not the obsidian-base repo): if this script
# is buggy, do NOT fix it here and do NOT open a PR against the base repo —
# FILE A GITHUB ISSUE against the upstream base (.agents/.base-url if present,
# else Object-3/obsidian-base) with the error + proposed fix in the issue body.
# Local patches are overwritten by the next update-base and help no other clone.
# See AGENTS.md → "Engine bugs & improvements found in a derived vault".
# ─────────────────────────────────────────────────────────────────────────────
# ===========================================================================
# install-mcp-quick-orient.sh — install the fast Obsidian MCP orientation
# instruction into a user's GLOBAL agent config, for every tool present
# ===========================================================================
# `.agents/mcp-quick-orient.md` (in this repo) teaches an agent to orient in
# any obsidian-base-derived vault using the fewest possible Obsidian MCP tool
# calls: fetch `.agents/vault-profile.md` once (only when a vault-specific
# fact is actually needed), and treat the rest of the directory/skill
# scaffolding as already known — because it's IDENTICAL across every
# obsidian-base fork. It was produced and measured by a `/ce-optimize` run
# (see .context/compound-engineering/ce-optimize/obsidian-mcp-quick-orient/).
#
# The content itself is tool-agnostic (plain instructions; the one concrete
# tool name it references, obsidian_get_file_contents, is defined by the
# mcp-obsidian MCP SERVER, not by any particular client) — so the same block
# installs unmodified into every supported tool's global config. It only
# helps if it's in each tool's GLOBAL instructions, not just this repo — so
# it applies automatically in every other project. This script does that,
# idempotently (safe to re-run after a base update refreshes the candidate
# text), and is fully non-interactive so an agent can run it directly (a
# calling skill/agent should still confirm with the human first, since this
# writes outside the repo, to the user's personal global config).
#
# Supported targets (each maps to that tool's own global-instructions file):
#   claude-code   ~/.claude/CLAUDE.md
#   codex         ~/.codex/AGENTS.md   (OpenAI Codex CLI; shared by Codex-
#                                        backed surfaces like the ChatGPT
#                                        desktop app's Codex integration)
#
# Subcommands:
#   detect              (default) Show install status per target. Read-only.
#   install             Write/update the managed block in every target that
#                        exists on this machine (its config DIR is present).
#                        Idempotent.
#   explain              Print a plain-English "here's what this does" card.
#
# Flags:
#   --targets a,b       Only operate on these target names (default: every
#                        target whose config dir is detected on this machine)
#
# Override a target's path for testing:  CLAUDE_CODE_TARGET=/path ... or
#                                          CODEX_TARGET=/path ...
set -euo pipefail

VAULT_ROOT="${VAULT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
SOURCE_FILE="$VAULT_ROOT/.agents/mcp-quick-orient.md"
BEGIN_MARK="<!-- BEGIN obsidian-mcp-quick-orient (managed by install-mcp-quick-orient.sh) -->"
END_MARK="<!-- END obsidian-mcp-quick-orient -->"

# name -> "config_dir|target_file|human_label"
TARGET_TABLE=(
  "claude-code|$HOME/.claude|${CLAUDE_CODE_TARGET:-$HOME/.claude/CLAUDE.md}|Claude Code"
  "codex|$HOME/.codex|${CODEX_TARGET:-$HOME/.codex/AGENTS.md}|OpenAI Codex CLI"
)

require_source() {
  if [[ ! -f "$SOURCE_FILE" ]]; then
    echo "Error: $SOURCE_FILE not found. This script must be run from an obsidian-base checkout." >&2
    exit 1
  fi
}

target_row() {
  local name="$1" row
  for row in "${TARGET_TABLE[@]}"; do
    [[ "${row%%|*}" == "$name" ]] && { echo "$row"; return 0; }
  done
  return 1
}

detected_targets() {
  # Targets whose tool config directory exists on this machine.
  local row config_dir name
  for row in "${TARGET_TABLE[@]}"; do
    IFS='|' read -r name config_dir _ _ <<<"$row"
    [[ -d "$config_dir" ]] && echo "$name"
  done
}

resolve_targets() {
  # --targets flag wins; else auto-detect; error if neither yields anything.
  if [[ -n "${TARGETS_FLAG:-}" ]]; then
    echo "${TARGETS_FLAG//,/$'\n'}"
    return
  fi
  local d
  d="$(detected_targets)"
  if [[ -z "$d" ]]; then
    echo "Error: no supported tool config directory found (checked: ~/.claude, ~/.codex). Pass --targets explicitly, e.g. --targets claude-code." >&2
    exit 1
  fi
  echo "$d"
}

is_installed() {
  local target_file="$1"
  [[ -f "$target_file" ]] && grep -qF "$BEGIN_MARK" "$target_file"
}

write_block() {
  local target_file="$1"
  python3 - "$SOURCE_FILE" "$target_file" "$BEGIN_MARK" "$END_MARK" <<'PY'
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

cmd_detect() {
  # Lists every KNOWN target (not just detected ones) so the user can see
  # what's missing; cmd_install only touches detected/selected ones.
  require_source
  echo "Source: $SOURCE_FILE"
  local row config_dir target_file label
  for row in "${TARGET_TABLE[@]}"; do
    IFS='|' read -r _ config_dir target_file label <<<"$row"
    echo
    echo "[$label]"
    echo "  Config dir: $config_dir $([[ -d "$config_dir" ]] && echo "(found)" || echo "(not found on this machine)")"
    echo "  Target:     $target_file"
    if is_installed "$target_file"; then
      echo "  Status:     installed"
    elif [[ -f "$target_file" ]]; then
      echo "  Status:     not installed (file exists, no managed block yet)"
    else
      echo "  Status:     not installed (file doesn't exist yet)"
    fi
  done
}

cmd_install() {
  require_source
  local name
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    local row config_dir target_file label result
    row="$(target_row "$name")" || { echo "Unknown target: $name" >&2; exit 1; }
    IFS='|' read -r _ config_dir target_file label <<<"$row"
    result="$(write_block "$target_file")"
    echo "[$label] $target_file -> $result"
  done < <(resolve_targets)
}

cmd_explain() {
  cat <<EOF

What just happened, in plain terms:

For each AI coding tool detected on this machine (Claude Code, and/or OpenAI
Codex CLI — including ChatGPT desktop's Codex-backed sessions, since they
read the same Codex global config), your global instructions file now has a
short, clearly-marked section (between
"$BEGIN_MARK" and "$END_MARK")
that tells that tool — in ANY project, not just this vault — how to quickly
get its bearings in an Obsidian vault reached through the Obsidian MCP
connector, as long as that vault is one built from this same "obsidian-base"
template.

In practice: instead of poking around the whole vault the first time it
needs an answer, it fetches one small file (the vault's own profile) and
already knows the rest of the layout, because every vault built from this
template shares it. Fewer steps, faster answers, same accuracy.

You don't need to do anything else — it applies automatically the next time
you start a session with that tool anywhere, whenever an Obsidian vault is
connected. Re-run "install" any time this file changes upstream (e.g. after
a base update) to refresh it in every detected tool; it's safe to run
repeatedly, and it only ever touches its own marked block — nothing else in
your global config is read or changed.
EOF
}

SUBCOMMAND="${1:-detect}"
shift || true
TARGETS_FLAG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --targets) TARGETS_FLAG="$2"; shift 2 ;;
    *) echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
done

case "$SUBCOMMAND" in
  detect) cmd_detect ;;
  install) cmd_install ;;
  explain) cmd_explain ;;
  *)
    echo "Usage: $0 [detect|install|explain] [--targets claude-code,codex]" >&2
    exit 1
    ;;
esac
