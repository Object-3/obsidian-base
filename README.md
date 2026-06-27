# obsidian-base-vault

A forkable/templatable base for an **agentic, LLM-agnostic Obsidian knowledge base**.
Create your vault from it, run a 30-second onboarding, and start writing — with a
curated set of Agent Skills already wired in and working across Claude Code, OpenAI
Codex, and any tool that reads the open `SKILL.md` / `AGENTS.md` standards.

## Two ways to use it

- **Use this template** (GitHub → "Use this template") → an **independent** repo.
  No upstream link, no drift, nothing to maintain. Best for non-technical users.
- **Fork it** → keeps an upstream link so you can pull base improvements later
  ("Sync fork" / merge). Best if you maintain a fleet of vaults off this base.

Either way you can also pull base updates on demand with `update-base` (below) — no
git knowledge required.

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

It refreshes only base-owned engine files (`AGENTS.md`, `CLAUDE.md`, scripts, hooks,
`.gitignore`, `.agents/SKILLS.md`) and **never** touches your notes,
`vault-profile.md`, or your `skill-sources.json`. Point it at your base with
`BASE_REPO=owner/repo`.

## Customizing the skill set

Edit `.agents/skill-sources.json` (add/remove GitHub skill sources; `include`
allow-list to cherry-pick), then run `.agents/scripts/sync-skills.sh`. See
`.agents/SKILLS.md` for the full mechanism, the Windows symlink fallback, and how
same-named skills resolve across Claude/Codex/user scopes.

## Requirements

`bash`, `git`, `curl`, `jq`, `python3` for the scripts. The vault content itself is
plain Markdown and needs nothing.
