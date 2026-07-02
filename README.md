# obsidian-base-vault

A forkable/templatable base for an **agentic, LLM-agnostic Obsidian knowledge base**.
Create your vault from it, start writing — with a curated set of Agent Skills already
wired in and working across Claude Code, OpenAI Codex, and any tool that reads the open
`SKILL.md` / `AGENTS.md` standards.

## 🚀 Brand new? Start here

**Non-technical, clean machine (no GitHub/Obsidian needed)** → follow **[SETUP.md](SETUP.md)**:
one command sets up everything, local-first.

```bash
# macOS
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Object-3/obsidian-base/main/setup/setup.sh)"
```
```powershell
# Windows
irm https://raw.githubusercontent.com/Object-3/obsidian-base/main/setup/setup.ps1 | iex
```

**Or just ask an AI assistant.** Point Claude Code or Claude Desktop at this repo and
say *"help me set one up"* — the **`onboard`** skill (`.agents/skills/onboard/`) drives
the whole setup with its tools and self-heals when something needs fixing.

> **For agents reading this repo:** to onboard a user, run the **onboard** skill (or
> `setup/setup.sh` / `setup/setup.ps1`) and verify each step with your tools. It creates
> a *separate* local vault — it does not turn this base clone into their vault.

## Two ways to use it

- **Use this template** (GitHub → "Use this template") → an **independent** repo.
  Recommended for everyone, including whole fleets. Pull base improvements on demand
  with `update-base` (below).
- **Fork it** only if you specifically want GitHub's fork graph. Note: GitHub won't
  let you fork into the **same org** that owns this base, and "Sync fork" conflicts
  as soon as a vault diverges (which it always does) — so `update-base` is the real
  sync mechanism either way.

Base updates flow via `update-base`, which is **git-native** and overlays only the
shared engine — your notes are never touched.

## Quickstart

```bash
.agents/scripts/init-vault.sh     # 1) customize (writes .agents/vault-profile.md), then syncs skills
.agents/scripts/sync-skills.sh    #    (init offers to run this for you)
```

With an agent you can instead just say **"/setup-vault"**. Then open the folder in
Obsidian and start writing (see `AGENTS.md` for the frontmatter contract).

## How customization stays separate from the base

The **only** per-vault file is `.agents/vault-profile.md` (name, tagline, purpose,
primary tag). `AGENTS.md` and the scripts are base-owned and never need per-vault
edits — so pulling base updates is conflict-free.

## Getting base improvements later

Run the base updater (or say **"/update-base"** to an agent):

```bash
.agents/scripts/update-base.sh    # pulls the latest engine from the upstream base
.agents/scripts/sync-skills.sh    # refresh skills if the scripts changed
```

It's **git-native**: it adds a `base` git remote, fetches the wanted ref, and overlays
only base-owned engine files (`AGENTS.md`, `CLAUDE.md`, scripts, hooks, `.gitignore`,
`.gitattributes`, `.agents/SKILLS.md`, and the curated `.agents/skill-sources.json`).
It prunes files the base removed and **never** touches your notes, `vault-profile.md`,
or your `skill-sources.local.json`. Configure with `BASE_REPO=owner/repo`,
`BASE_REPO_URL=<any git url>`, or pin a tag/SHA with `BASE_REF=` (or a `.agents/.base-ref`
file). Because it's an engine change, commit it on a branch and open a PR.

## Customizing the skill set

The curated list lives in base-owned `.agents/skill-sources.json` (refreshed by
`update-base`). Put **your own** sources in `.agents/skill-sources.local.json`
(never overwritten); `sync-skills.sh` **merges both** (local wins on name collisions).
Then run `.agents/scripts/sync-skills.sh`. See `.agents/SKILLS.md` for the full
mechanism, the Windows symlink fallback, and skill-name resolution.

**Use the skills in every project (optional).** Skills are vendored into the repo
(so they work in cloud/web sessions and shared clones), and you can *also* mirror the
portable ones into your machine's user-scope so they work outside the vault too — via
the **`/install-skills`** skill or the onboarding opt-in. It's additive and reversible;
see [`.agents/SKILLS.md`](.agents/SKILLS.md) → *User-scope mirror*.

## Sync model (humans + agents, no extra surface)

The vault ships a recommended **Obsidian Git** config (`.obsidian/plugins/obsidian-git/data.json`):
auto commit-and-sync to `main`, **pull-on-start**, merge strategy. Non-technical
users just write notes — sync is automatic, no git. Append-only/generated files
(`log.md`, `INDEX.md`) use `merge=union` in `.gitattributes` so Obsidian Git's local
merges resolve without conflict markers. **Content** (human- or MCP-authored notes)
flows to `main`; **engine** changes go on a branch + PR (see `AGENTS.md`).

## Self-improving (the dream)

The vault consolidates itself between sessions. The **`/vault-dream`** skill reads your
agent session transcripts since a watermark, folds durable learnings into
`docs/knowledge/`, dedupes/re-indexes the vault, and opens a **reviewable pull request** —
it never writes to `main` or auto-merges. A passive `SessionStart` nudge offers it once
enough sessions have piled up (≥24h and ≥5 new sessions); other agents run `/vault-dream`
manually. See *The dream* in `AGENTS.md`.

## Requirements

`bash`, `git`, `curl`, `jq`, `python3` for the scripts. The vault content itself is
plain Markdown and needs nothing.
