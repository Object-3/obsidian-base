---
name: add-vault
description: Create an ADDITIONAL empty knowledge vault with the exact same obsidian-base setup, beside an existing one, and wire it into your AI clients under its own name — so multiple topic vaults (e.g. "Obsidian Strategy" and "Obsidian Puma") are reachable at the same time. Use when the user says "add another vault", "second vault", "new topic knowledge base", "spin up another vault", "I want a separate vault for X", or asks how to have more than one base vault. Drives setup/add-vault.sh; also migrates the legacy single `mcp-obsidian` connection to a per-vault name.
---

# Add another vault beside this one

Stand up a **second (or third) topic vault** with the identical base setup and wire it
into every local AI client (Claude Desktop, Claude Code, OpenAI Codex) under its **own
name**, without disturbing the vault(s) you already have. Each vault gets its own
Obsidian REST API **port** and its own MCP server label `obsidian-<slug>`, so both are
reachable in the same assistant session.

> Use this when a working vault already exists and the user wants **another** one. For
> first-time setup on a fresh machine, that's `setup/setup.sh` (the `onboard`/`setup-vault`
> path). This skill assumes prerequisites (git, uv, Obsidian) are already installed.

## Steps

1. **Confirm the ask.** Get the new vault's **name** (e.g. "Obsidian Puma"), and
   optionally its **primary tag** / tagline / purpose (same four fields as `setup-vault`).
   The folder slug and MCP label are derived from the name (`Obsidian Puma` →
   folder `obsidian-puma`, label `obsidian-puma`).

2. **Run the script** from inside the current vault:
   ```bash
   VAULT_NAME="Obsidian Puma" PRIMARY_TAG="puma" ./setup/add-vault.sh --yes
   ```
   It: (a) on first run, migrates the existing vault's legacy `mcp-obsidian` connection
   to its own vault name; (b) clones the base (from the vault's own `base` remote) into a
   sibling folder; (c) personalizes it via `init-vault.sh`; (d) provisions the Obsidian
   plugins on an **auto-allocated free port** with a fresh key; (e) **appends** a
   vault-named MCP server into every installed client. Env overrides mirror `setup.sh`
   (`VAULT_PARENT`, `MCP_CLIENTS`, `NO_OPEN`, `CLAUDE_DESKTOP_CONFIG`, `CODEX_HOME`).

3. **Hand off in plain language.** After it runs, tell the user, simply:
   - They now have a **new, separate knowledge base** at `<path>`, wired as
     **`obsidian-<slug>`**.
   - **Both vaults must be OPEN in Obsidian** to be reachable at the same time — a vault's
     connection only works while its window is open. If a vault is closed, the assistant
     will just say it can't reach that one.
   - They must **start a fresh assistant session** (quit/reopen Claude Desktop, or a new
     Claude Code / Codex session) for the new connection to load.
   - To confirm: ask the assistant to **"list the files in `obsidian-<slug>`."**
   - Optional cloud backup for the new vault anytime: `cd <path> && ./setup/connect-github.sh`.

## Notes

- **Multiple clients, one command.** The script wires Claude Desktop, Claude Code, and
  Codex (`~/.codex/config.toml`) if present, each under the same `obsidian-<slug>` label.
  Absent clients are skipped cleanly.
- **ChatGPT desktop app (macOS)** can't consume a *local* MCP server today (its connectors
  are remote-only, and only on web/Windows). To reach a vault from ChatGPT/Claude on the
  web you'd expose the vault's `/mcp/` endpoint at a public HTTPS URL (tunnel or cloud) —
  see the "reach a vault from the web" note in `SETUP.md`. That trades away the local-first
  posture, so it's opt-in and not set up here.
- **Just want to rename the existing connection** (not add a vault)? Run
  `./setup/migrate-mcp-names.sh` — it renames the legacy `mcp-obsidian` to your vault's name.
- Hand-authored, repo-local skill — not vendored, so `sync-skills.sh` won't overwrite it.
