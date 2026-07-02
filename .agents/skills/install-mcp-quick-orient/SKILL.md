---
name: install-mcp-quick-orient
description: Install the fast Obsidian MCP vault-orientation instruction into every detected AI coding tool's GLOBAL config (Claude Code's ~/.claude/CLAUDE.md, OpenAI Codex CLI's ~/.codex/AGENTS.md — including ChatGPT desktop's Codex-backed sessions), so any of those tools, in any project, orients quickly the moment it connects to an obsidian-base-derived vault via the Obsidian MCP connector — instead of exploring the whole vault first. Use when the user says "install the quick-orient instruction globally", "make MCP orientation fast everywhere", "install mcp-quick-orient", or after a `/ce-optimize` run has produced a winning `.agents/mcp-quick-orient.md`.
---

# Install the fast Obsidian MCP orientation instruction (globally, every tool)

`.agents/mcp-quick-orient.md` in this repo teaches an agent to orient in any
obsidian-base-derived vault using the fewest possible Obsidian MCP tool calls.
It only helps if it's in each tool's **global** instructions — not just this
one repo — so it applies automatically in every other project. The content
is tool-agnostic (the one concrete tool name it references is defined by the
mcp-obsidian MCP *server*, not by any client), so the same block installs
unmodified everywhere. This skill installs it, fully non-interactively — an
agent can run it directly.

## Steps

1. **Check current state** (shows every known target, found or not):
   ```bash
   .agents/scripts/install-mcp-quick-orient.sh detect
   ```

2. **Confirm with the user** what will change and where before writing —
   these are personal global config files, outside this repo.

3. **Install** into every tool detected on this machine (idempotent — safe
   to re-run, e.g. after a base update refreshes the candidate text):
   ```bash
   .agents/scripts/install-mcp-quick-orient.sh install
   ```
   To target specific tools only: `... install --targets claude-code,codex`

4. **Explain in plain language** what changed and how it behaves going
   forward:
   ```bash
   .agents/scripts/install-mcp-quick-orient.sh explain
   ```

## Notes

- Hand-authored, repo-local skill — not vendored, so `sync-skills.sh` won't
  overwrite it.
- Only ever writes between the `<!-- BEGIN obsidian-mcp-quick-orient -->` /
  `<!-- END ... -->` markers it manages — never touches the rest of any
  target file.
- Supported targets today: `claude-code` (`~/.claude/CLAUDE.md`), `codex`
  (`~/.codex/AGENTS.md`). Override a path for testing with
  `CLAUDE_CODE_TARGET=/path` / `CODEX_TARGET=/path`.
- Adding another tool (Gemini CLI, Cursor, etc.) means adding one row to
  `TARGET_TABLE` in the script with that tool's global-instructions path —
  the write/detect/explain logic is already generic.
