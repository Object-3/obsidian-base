# Get started in one step

This turns a brand-new computer into a working, agent-powered knowledge vault —
**no GitHub account, no setup knowledge needed.** You write notes in
[Obsidian](https://obsidian.md); your AI assistant can read and write them too.

## 0. Install your AI assistant first

The vault is read and written by an AI assistant, so you need one on this computer.
The command below **pre-wires the connection**, but it doesn't install the assistant
itself — grab whichever you'll use first:

- **[Claude Desktop](https://claude.ai/download)** — the easy choice for non-technical use.
- **[Claude Code](https://claude.com/claude-code)** — if you live in the terminal.

(If you skip this, setup still finishes and tells you what's missing — you can install
the assistant afterward and it'll connect.)

## 1. Run one command

**macOS** — open the **Terminal** app, paste this, press Return:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Object-3/obsidian-base/main/setup/setup.sh)"
```

**Windows** — open **PowerShell**, paste this, press Enter:

```powershell
irm https://raw.githubusercontent.com/Object-3/obsidian-base/main/setup/setup.ps1 | iex
```

It installs everything it needs (Obsidian included), creates your vault on your
computer, wires the connection to your AI assistant, and opens it. It only asks you to
**name your vault**.

## 2. One click in Obsidian

When Obsidian opens, if it asks, click **“Trust author and enable plugins.”**
That’s a one-time safety prompt — and it’s what switches on the little bridge
(the Local REST API) your assistant uses to reach the vault. **Until you click it, the
assistant can’t read or write your notes.** Then start writing — you’re done with Obsidian.

## 3. Start a *new* assistant session to connect it

The connection was set up for you, but your assistant only picks it up when a session
**starts** — so you have to begin a fresh one:

- **Claude Desktop:** fully quit the app and reopen it.
- **Claude Code:** start a new session (the one already running won’t see it).

To confirm it worked, ask your assistant: **“list the files in my vault.”** If it lists
them, you’re connected.

Your vault lives **on your computer** and is yours. Nothing is uploaded anywhere
unless you choose to in step 4.

## 4. (Optional) Back up to the cloud — anytime later

Want your notes backed up and synced across devices? From your vault folder, run:

**macOS:** `./setup/connect-github.sh`  **Windows:** `.\setup\connect-github.ps1`

It signs you into GitHub and creates a **private** repo under **your account** (or a
company/team **org** you choose). After that it backs up automatically.

## Use these skills everywhere (optional)

During setup you're asked whether to make the vault's skills available in **all** your
projects, not just this vault. Say yes and they're installed for your assistant
machine-wide. You can change your mind anytime — just ask your assistant to
**"install my skills everywhere"** (or *"are my global skills up to date?"*). These
skills stay even if you later disconnect the vault — they're yours.

## Add another vault (a second topic knowledge base)

Already have one vault working and want a **separate** one for a different topic —
e.g. "Obsidian Puma" beside "Obsidian Strategy"? From inside your existing vault, run:

**macOS/Linux:** `./setup/add-vault.sh`   *(or ask your assistant to "add another vault")*

It creates a brand-new empty vault with the identical setup, and wires it into your
local AI clients — **Claude Desktop, Claude Code, and OpenAI Codex** (whichever are
installed) — under its **own name** (`obsidian-<slug>`), on its **own port**, without
disturbing the vault you already have. The first time you run it, it also gives your
existing vault a proper name (renaming the old generic `mcp-obsidian` connection).

Two things to know so both vaults work at once:
- **Open both vaults in Obsidian.** A vault is only reachable while its window is open
  (the Local REST API bridge runs per open vault). Closed vault → the assistant just
  can't reach that one.
- **Start a fresh assistant session** so the new connection loads, then ask your
  assistant to "list the files in `obsidian-<name>`" to confirm.

(Just want to rename the existing connection without adding a vault?
Run `./setup/migrate-mcp-names.sh`.)

(Vaults showing up in one app but not another, or a connection erroring / "off air"?
Run `./setup/sync-mcp.sh` — or ask your assistant to **"run the doctor"** — to reconcile
every vault into every AI client and repair broken wiring.)

## Reach a vault from ChatGPT or Claude on the web (optional, advanced)

The setup above is **local-first** — your vault stays on your computer and your
assistant reaches it over `localhost`. The **ChatGPT desktop app on macOS can't use a
local vault** today (its connectors are remote-only, on web/Windows). If you want to
reach a vault from **ChatGPT or Claude on the web** from anywhere, you'd expose the
vault's built-in MCP endpoint (`https://127.0.0.1:<port>/mcp/`, secured by its API key)
at a **public HTTPS URL** — via a tunnel (Cloudflare Tunnel / ngrok / Tailscale Funnel)
or a cloud-hosted setup. Those web clients dial the URL from the provider's cloud, so a
`localhost` address won't work — it needs to be publicly reachable.

**Trade-off:** this puts your knowledge base behind a network endpoint, which cuts
against the local-first, "nothing leaves your machine" default. Keep it auth-gated and
behind a private tunnel, and treat confidential material the same careful way as the
`_sensitive/` plane. It's deliberately **not** set up for you — it's here so you know
the path exists.

## Changed your mind? Disconnect it

To reverse the integration **without touching your notes**, run from your vault folder:

**macOS:** `./setup/uninstall.sh`  **Windows:** `.\setup\uninstall.ps1`

It removes the assistant connections (every Obsidian MCP server — for all your vaults —
from Claude Desktop, Claude Code, and OpenAI Codex) and the vault rules added to your
global assistant config. Your vault and notes are left exactly where they are — it even
prints the location. Add `--remove-plugins`
(macOS/Linux) or `-RemovePlugins` (Windows) to also remove the Obsidian plugins. To
re-enable later, just run `setup` again. (Or ask your assistant to "disconnect my vault.")

## Keeping up to date

To pull the latest shared improvements (new skills, fixes) into your vault:

```bash
.agents/scripts/update-base.sh
```

(Or just ask your assistant to “update the base.”)

---

*Curious what the command does first? Read [`setup/setup.sh`](setup/setup.sh) — it's
plain, commented, and safe to re-run.*
