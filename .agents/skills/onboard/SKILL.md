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
Pass `--yes` and env vars (`VAULT_NAME`, `MCP_CLIENTS=both|desktop|code`,
`MIRROR_SKILLS=yes|no`) for an unattended run. The script: installs prereqs
(Homebrew/winget, git, jq, uv, Obsidian),
creates a LOCAL vault from this base (no GitHub needed), provisions the Obsidian Git +
Local REST API plugins, pre-generates the REST API key, wires the MCP, and opens Obsidian.
Interactively it also offers to mirror the portable skills into your machine's user-scope
(so they work in *every* project); `MIRROR_SKILLS=yes` opts in unattended, `no` skips —
the `install-skills` skill enables or refreshes it later either way.

**Personalization is the `setup-vault` step.** The script runs `init-vault.sh`
(vault name, tagline, purpose, primary tag) automatically. If you ran the bootstrap
non-interactively, or the user wants to (re)personalize, invoke the **`setup-vault`**
skill — it's the same profile step and is safe to run anytime.

## 2. Verify — and fix what's broken (use tools)
Check each; if a check fails, investigate and repair, then re-check:
- **Vault exists** and is its own git repo (`git -C <vault> rev-parse --is-inside-work-tree`).
  By design there is **no** standing `base` remote — `/update-base` adds one only for the
  fetch and removes it; a fork/custom base URL is persisted in `.agents/.base-url`. Don't
  "repair" a missing `base` remote by re-adding one.
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

## 4. Mention the optional next steps
- **Cloud backup** whenever they want it (under their own account or an org): the
  **`connect-github`** skill (or `./setup/connect-github.sh`/`.ps1` directly). Not
  required to use the vault.
- **Confidential material? Set up the Sensitive plane** (only if relevant): if they'll
  keep NDA-bound / third-party / regulated notes, run **`/setup-sensitive-plane`** to back
  the gitignored `_sensitive/` folder with an org-tenant cloud-synced folder — durable and
  multi-device, but never in git. It **ends by telling them, in plain language, that they
  have a private folder and how to use it.** Skip for purely personal, single-machine use.
- **Proactive recall from any project** (recommended): with the MCP at `--scope user`,
  the vault is reachable from every Claude Code session — but the agent won't *consult*
  it on its own unless told to. Offer to add a short standing rule to their global
  `~/.claude/CLAUDE.md` so agents proactively search the vault for questions their own
  notes would inform (past decisions, prior research, project context, preferences),
  read/search only, fall back gracefully when Obsidian is closed, and never write
  without an explicit ask. Keep the trigger scoped so it helps without hammering the MCP.
- **Capture knowledge back to the vault** (recommended, pairs with the above): also
  offer a standing global rule so that when work in *another* project produces a
  durable, reusable artifact (e.g. from `kw-compound`/`kw-plan`, `ce-compound`, or a
  research/decision/playbook write-up) with value beyond that one repo, the agent
  **asks** whether to add it to the vault — then, on yes, reads the vault's conventions
  via the MCP and writes a conformant note (right folder, frontmatter, `index.md` +
  `log.md`). This is the explicit-ask exception to no-MCP-writes. Don't prompt for
  project-only artifacts.
- **When adding either rule to `~/.claude/CLAUDE.md`, wrap the inserted block** in
  `<!-- BEGIN obsidian-base vault rules (managed by obsidian-base setup; safe to
  remove) -->` … `<!-- END obsidian-base vault rules -->` sentinels. This is what lets
  the **`offboard`** skill (and a careful human) remove exactly our block later
  without disturbing the rest of the user's global config.

## Notes
- **Local-first**: everything works with no GitHub account. `update-base` pulls engine
  updates from the public base repo without auth (via an ephemeral `base` remote it adds
  for the fetch and then removes).
- **Don't make non-technical users think in repos.** Their mental model is simply
  *"I write in Obsidian; my agents can read it and, with my OK, add to it."* Obsidian
  Git syncs underneath; the MCP is how agents reach in. Never tell them to `cd` into a
  checkout or work "out of the repo" — the two standing rules above (recall + capture)
  give them the agent-side behavior without exposing the mechanism. (Technical users
  who want branch/PR discipline can still work directly in the vault checkout for
  intentional KB work; that's their choice, not a requirement.)
- Re-running the script is safe (idempotent). When stuck, prefer reading the script and
  running its steps one at a time over guessing.
- This skill is hand-authored and repo-local (not vendored); `sync-skills.sh` won't
  overwrite it, and `update-base` propagates it to the fleet.
