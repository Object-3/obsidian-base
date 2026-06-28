---
name: offboard
description: Reverse the obsidian-base agent integration WITHOUT deleting the user's notes. Removes the Obsidian MCP from Claude Desktop and Claude Code and the managed rules block from the global ~/.claude/CLAUDE.md; optionally removes the Obsidian plugins. Never deletes the vault and never uninstalls prerequisites. Use when someone says "uninstall this", "disconnect my vault", "remove the obsidian MCP", "undo the setup", "reverse onboarding", or reports the integration is causing problems. Drives setup/uninstall.sh (macOS/Linux) or setup/uninstall.ps1 (Windows) and SELF-HEALS with tools when steps differ or fail.
---

# Offboard a vault (reverse the integration, keep the notes)

Your job: cleanly **disconnect** the agent integration that `onboard`/`setup` wired up,
**without ever deleting the user's vault or notes**. Prefer running the script; use your
tools to diagnose and finish anything it can't.

**The one rule you must not break: never delete the vault.** Notes are the user's data.
The script is built so it *cannot* delete the vault — keep it that way. If the user
explicitly wants the vault gone, tell them the folder path and let *them* delete it.

## 0. Read the situation
- Detect the OS (`uname` / `$OS`). macOS/Linux → `setup/uninstall.sh`; Windows → `setup/uninstall.ps1`.
- Confirm intent with the user: this **disconnects** the integration (MCP wiring +
  global rules). Their notes stay; prerequisites (git, jq, uv, Obsidian) stay.
- Ask whether they also want the **Obsidian plugins** removed (`--remove-plugins` /
  `-RemovePlugins`). Default is no — leaving them is harmless and keeps Obsidian Git
  syncing if they still use it.

## 1. Run it
```bash
./setup/uninstall.sh                  # macOS/Linux  (add --remove-plugins to also strip plugins)
```
```powershell
./setup/uninstall.ps1                 # Windows      (add -RemovePlugins)
```
The script: removes `mcp-obsidian` from the Claude Desktop config, runs
`claude mcp remove mcp-obsidian --scope user`, and deletes the managed block from
`~/.claude/CLAUDE.md` (the span between the `BEGIN/END obsidian-base vault rules`
sentinels). It prints the vault location and leaves the notes untouched.

## 2. Verify — and fix what's left (use tools)
- **Claude Desktop**: `.mcpServers["mcp-obsidian"]` no longer in
  `~/Library/Application Support/Claude/claude_desktop_config.json` (macOS) /
  `%APPDATA%\Claude\claude_desktop_config.json` (Windows). Other servers untouched.
- **Claude Code**: `claude mcp list` no longer shows `mcp-obsidian`.
- **Global rules**: no `obsidian-base vault rules` block in `~/.claude/CLAUDE.md`, and
  the rest of the file is intact. If there were **no sentinels** (the user added the
  rules by hand), don't guess — point them at the `## Obsidian knowledge base` section
  to remove manually.
- **Vault still present**: confirm the vault folder and its notes are exactly as before.

## 3. Hand off
Tell the user, plainly:
1. **Start a fresh assistant session** so the removed server actually drops: fully quit
   and reopen Claude Desktop, or start a new Claude Code session.
2. Their **vault and notes are untouched** at the printed path. To re-enable later, just
   re-run `setup.sh` / `setup.ps1`.

## Notes
- **Never deletes the vault, never uninstalls prerequisites.** Those are deliberate
  safety limits — don't add a vault-purge flag.
- Removal is **surgical**: the Desktop config and Claude Code server are keyed by the
  name `mcp-obsidian`; the global-rules block is bounded by sentinels written at
  install time (see the `onboard` skill). That's why install wraps the block.
- Idempotent — safe to re-run. When stuck, prefer reading the script and running its
  steps one at a time over guessing.
- This skill is hand-authored and repo-local (not vendored); `sync-skills.sh` won't
  overwrite it, and `update-base` propagates it to the fleet.
