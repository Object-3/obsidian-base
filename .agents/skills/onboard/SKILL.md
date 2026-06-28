---
name: onboard
description: Set up a brand-new, agent-powered Obsidian knowledge vault from scratch for a non-technical user — installs prerequisites, creates a LOCAL vault from this base, wires the Obsidian MCP into Claude Desktop and/or Claude Code, and verifies it works. Use when someone points an agent at the obsidian-base repo and says "help me set one up", "set up a vault", "get me started", "create a knowledge base", "onboard me", or similar. Drives setup/setup.sh (macOS/Linux) or setup/setup.ps1 (Windows) and SELF-HEALS with tools when steps differ or fail.
---

# Onboard a new vault (drive it to a fully working state)

Your job: get a non-technical person from nothing to a working, agent-wired vault.
**Prefer running the script; use your tools to diagnose and fix anything that breaks.**
Do not just print instructions and stop — keep going until it works or you hit a step
only the human can do (GitHub signup, the Obsidian "trust" click).

## 0. Read the situation
- Detect the OS (`uname` / `$OS`). macOS/Linux → `setup/setup.sh`; Windows → `setup/setup.ps1`.
- Do you have shell access (Bash/PowerShell tool)? 
  - **Yes** → run the script yourself (below).
  - **No** (e.g. Claude Desktop with no shell) → give the human the one-line command
    from `SETUP.md` for their OS, then help them interpret output and unblock.

## 1. Run the bootstrap
From the base repo (or via the one-liner in `SETUP.md`):
```bash
./setup/setup.sh            # macOS/Linux  (or:  bash setup/setup.sh)
```
```powershell
./setup/setup.ps1           # Windows
```
Pass `--yes` and env vars (`VAULT_NAME`, `MCP_CLIENTS=both|desktop|code`) for an
unattended run. The script: installs prereqs (Homebrew/winget, git, jq, uv, Obsidian),
creates a LOCAL vault from this base (no GitHub needed), provisions the Obsidian Git +
Local REST API plugins, pre-generates the REST API key, wires the MCP, and opens Obsidian.

**Personalization is the `setup-vault` step.** The script runs `init-vault.sh`
(vault name, tagline, purpose, primary tag) automatically. If you ran the bootstrap
non-interactively, or the user wants to (re)personalize, invoke the **`setup-vault`**
skill — it's the same profile step and is safe to run anytime.

## 2. Verify — and fix what's broken (use tools)
Check each; if a check fails, investigate and repair, then re-check:
- **Vault exists** and is its own git repo with a `base` remote (`git -C <vault> remote -v`).
- **Skills synced**: `.agents/skills/INDEX.md` lists ~60 skills; pointers resolve.
- **Plugins present**: `.obsidian/plugins/obsidian-git/main.js` and
  `obsidian-local-rest-api/main.js` exist; both listed in `community-plugins.json`.
  If a release download failed, retry, or fetch the latest release assets directly
  from the plugin's GitHub `releases/latest`.
- **MCP wired**: the key in `.obsidian/.rest-api-key` matches `OBSIDIAN_API_KEY` in the
  Claude Desktop config (`~/Library/Application Support/Claude/claude_desktop_config.json`
  on macOS, `%APPDATA%\Claude\claude_desktop_config.json` on Windows) and/or
  `claude mcp list` shows `mcp-obsidian`. Fix the config if missing — when re-adding
  to Claude Code, use `claude mcp add mcp-obsidian --scope user …` so the vault is
  reachable from every project, not just the setup directory.
- **MCP runtime**: `uvx mcp-obsidian` is resolvable (uv installed). If not, install uv.
- **REST API reachable** (after the human enables plugins): the Local REST API answers
  on `https://127.0.0.1:27124` with the key. If not yet, that's the human's trust click.

## 3. Hand off the two human-only steps
Tell the user, plainly:
1. In Obsidian, click **"Trust author and enable plugins"** if prompted (one time).
2. **Restart Claude Desktop** so it loads the new MCP server (Claude Code picks it up
   on next session).
Then confirm the agent can list files in the vault via the Obsidian MCP.

## 4. Mention the optional next steps
- **Cloud backup** whenever they want it (under their own account or an org):
  `./setup/connect-github.sh` (or `.ps1`). Not required to use the vault.
- **Proactive recall from any project** (recommended): with the MCP at `--scope user`,
  the vault is reachable from every Claude Code session — but the agent won't *consult*
  it on its own unless told to. Offer to add a short standing rule to their global
  `~/.claude/CLAUDE.md` so agents proactively search the vault for questions their own
  notes would inform (past decisions, prior research, project context, preferences),
  read/search only, fall back gracefully when Obsidian is closed, and never write
  without an explicit ask. Keep the trigger scoped so it helps without hammering the MCP.

## Notes
- **Local-first**: everything works with no GitHub account. `update-base` pulls engine
  updates from the public base remote without auth.
- Re-running the script is safe (idempotent). When stuck, prefer reading the script and
  running its steps one at a time over guessing.
- This skill is hand-authored and repo-local (not vendored); `sync-skills.sh` won't
  overwrite it, and `update-base` propagates it to the fleet.
