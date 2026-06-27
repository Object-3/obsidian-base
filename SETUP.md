# Get started in one step

This turns a brand-new computer into a working, agent-powered knowledge vault —
**no GitHub account, no setup knowledge needed.** You write notes in
[Obsidian](https://obsidian.md); your AI assistant can read and write them too.

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
computer, connects your AI assistant, and opens it. It only asks you to **name your
vault**.

## 2. One click in Obsidian

When Obsidian opens, if it asks, click **“Trust author and enable plugins.”**
That’s a one-time safety prompt. Then start writing — that’s it.

Your vault lives **on your computer** and is yours. Nothing is uploaded anywhere
unless you choose to in step 3.

## 3. (Optional) Back up to the cloud — anytime later

Want your notes backed up and synced across devices? From your vault folder, run:

**macOS:** `./setup/connect-github.sh`  **Windows:** `.\setup\connect-github.ps1`

It signs you into GitHub and creates a **private** repo under **your account** (or a
company/team **org** you choose). After that it backs up automatically.

## Keeping up to date

To pull the latest shared improvements (new skills, fixes) into your vault:

```bash
.agents/scripts/update-base.sh
```

(Or just ask your assistant to “update the base.”)

---

*Curious what the command does first? Read [`setup/setup.sh`](setup/setup.sh) — it's
plain, commented, and safe to re-run.*
