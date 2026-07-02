---
name: install-mcp-quick-orient
description: Install the fast Obsidian MCP vault-orientation instruction into your GLOBAL agent config (e.g. ~/.claude/CLAUDE.md), so any Claude Code session, in any project, orients quickly the moment it connects to an obsidian-base-derived vault via the Obsidian MCP connector — instead of exploring the whole vault first. Use when the user says "install the quick-orient instruction globally", "make MCP orientation fast everywhere", "install mcp-quick-orient", or after a `/ce-optimize` run has produced a winning `.agents/mcp-quick-orient.md`.
---

# Install the fast Obsidian MCP orientation instruction (globally)

`.agents/mcp-quick-orient.md` in this repo teaches an agent to orient in any
obsidian-base-derived vault using the fewest possible Obsidian MCP tool calls.
It only helps if it's in the agent's **global** instructions — not just this
one repo — so it applies automatically in every other project. This skill
installs it there.

## Steps

1. **Check current state.**
   ```bash
   .agents/scripts/install-mcp-quick-orient.sh detect
   ```

2. **Confirm with the user** what will change and where (the target file,
   normally `~/.claude/CLAUDE.md`) before writing to it — this is their
   personal global config, outside this repo.

3. **Install** (idempotent — safe to re-run, e.g. after a base update
   refreshes the candidate text):
   ```bash
   .agents/scripts/install-mcp-quick-orient.sh install
   ```

4. **Explain in plain language** what changed and how it behaves going
   forward:
   ```bash
   .agents/scripts/install-mcp-quick-orient.sh explain
   ```

## Notes

- Hand-authored, repo-local skill — not vendored, so `sync-skills.sh` won't
  overwrite it.
- Only ever writes between the `<!-- BEGIN obsidian-mcp-quick-orient -->` /
  `<!-- END ... -->` markers it manages — never touches the rest of the
  target file.
- Override the target file for testing: `TARGET_FILE=/path/to/file ...`
- If the user works in a tool other than Claude Code (Codex, Gemini, etc.),
  their global config lives elsewhere — point them to their tool's
  equivalent global instructions file and offer to adapt the same block.
