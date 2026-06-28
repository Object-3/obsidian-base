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

## Changed your mind? Disconnect it

To reverse the integration **without touching your notes**, run from your vault folder:

**macOS:** `./setup/uninstall.sh`  **Windows:** `.\setup\uninstall.ps1`

It removes the assistant connection (the Obsidian MCP from Claude Desktop and Claude
Code) and the vault rules added to your global assistant config. Your vault and notes
are left exactly where they are — it even prints the location. Add `--remove-plugins`
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
