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
  `claude mcp list` shows `mcp-obsidian`. Fix the config if missing.
- **MCP runtime**: `uvx mcp-obsidian` is resolvable (uv installed). If not, install uv.
- **REST API reachable** (after the human enables plugins): the Local REST API answers
  on `https://127.0.0.1:27124` with the key. If not yet, that's the human's trust click.

## 3. Hand off the human-only steps
First, **is an AI assistant even installed?** The script wires the MCP config but does
not install Claude itself. If neither `/Applications/Claude.app` (Desktop) nor the
`claude` CLI (Code) is present, tell the user to install one first — Claude Desktop:
https://claude.ai/download, Claude Code: https://claude.com/claude-code — then continue.

Then tell the user, plainly:
1. In Obsidian, click **"Trust author and enable plugins"** if prompted (one time).
   This switches on the Local REST API — the bridge the MCP talks to. Until they do
   this, the assistant cannot read or write the vault.
2. **Start a new session so the MCP loads:** fully quit and reopen Claude Desktop, or
   start a fresh Claude Code session (the running one won't see the new server).
Then confirm the agent can list files in the vault via the Obsidian MCP.

## 4. Mention the optional next step
Cloud backup whenever they want it (under their own account or an org):
`./setup/connect-github.sh` (or `.ps1`). Not required to use the vault.

## Notes
- **Local-first**: everything works with no GitHub account. `update-base` pulls engine
  updates from the public base remote without auth.
- Re-running the script is safe (idempotent). When stuck, prefer reading the script and
  running its steps one at a time over guessing.
- This skill is hand-authored and repo-local (not vendored); `sync-skills.sh` won't
  overwrite it, and `update-base` propagates it to the fleet.
