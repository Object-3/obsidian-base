---
name: add-engineering-skills
description: Add the software-ENGINEERING (coding) skill set — EveryInc's Compound Engineering plugin (ce-*) — to this vault, as an opt-in. These are for WRITING AND SHIPPING CODE (planning, code review, debugging, pull-request/commit workflows, browser/Xcode testing), NOT for note-taking or knowledge work. Use when the user says "add the engineering skills", "add coding/developer skills", "add compound engineering", "install the ce-* skills", "I also write code in this setup", or asks for code-review/debugging/PR skills. If they only take notes, they don't want this. Drives a LOCAL vendored source + sync-skills.sh; never forced, always reversible.
---

# Add the engineering (Compound Engineering) skills — opt-in

This vault is a **knowledge base** — its skills are for notes, research, writing, and
marketing. **Compound Engineering** is a *separate* toolkit for people who also **write
software**: planning a feature, reviewing code, debugging, committing, opening pull
requests, running tests. This skill adds that toolkit **only if the user asks for it.**

> **Say this plainly to a non-technical user first, and only proceed on a clear yes:**
> "These are **coding** skills — they help write and ship *software*, not notes. If you're
> using this vault to capture knowledge, you don't need them. Do you also build software
> with this setup? If yes, I'll add them; they sit alongside your notes and change nothing
> about how the vault works."

## What gets added

The full **[Compound Engineering plugin](https://github.com/EveryInc/compound-engineering-plugin)**
(`EveryInc/compound-engineering-plugin`) — its `ce-*` skills (e.g. `/ce-plan`,
`/ce-code-review`, `/ce-debug`, `/ce-commit`, `/ce-babysit-pr`, `/ce-simplify-code`,
`/ce-worktree`, `/ce-test-browser`) plus `/lfg`. They vendor into `.agents/skills/`
exactly like every other skill, so they load in every session and every cloud container.

**The whole plugin, on purpose — no cherry-picking.** We add the *entire* `skills/`
folder rather than an allow-list so that **every refresh adopts the complete current
upstream set automatically** — new skills, renames, and restructuring flow in on their
own, and nothing they ship ever gets silently missed. (An allow-list would freeze the set
to today's names and quietly skip anything added later.)

## Steps

1. **Confirm it's wanted** (the plain-language check above). If the user only does
   knowledge work, stop here — this is not for them.

2. **Add the source and vendor it.** Register Compound Engineering as a **local** source
   (this vault only — never pushed to the base/fleet, never touched by `/update-base`),
   then sync. Idempotent — safe to re-run:
   ```bash
   cd "$(git rev-parse --show-toplevel)"
   LOCAL=.agents/skill-sources.local.json
   [ -f "$LOCAL" ] || echo '{"sources":[]}' > "$LOCAL"
   jq '.sources |= (map(select(.name != "compound-engineering")) + [{
         name: "compound-engineering",
         repo: "EveryInc/compound-engineering-plugin",
         skillsPath: "skills",
         note: "Full Compound Engineering plugin (ce-* code skills + lfg). ENGINEERING plane — for code repos, not knowledge notes. No include list, so every sync adopts the complete current upstream set. If a sync ever warns this source yielded no skills, upstream likely moved the folder — update skillsPath (e.g. to plugins/compound-engineering/skills)."
       }])' "$LOCAL" > "$LOCAL.tmp" && mv "$LOCAL.tmp" "$LOCAL"
   .agents/scripts/sync-skills.sh
   ```
   `sync-skills.sh` merges local sources with the base's, fetches the plugin, vendors the
   `ce-*` skills into `.agents/skills/`, refreshes the pointers, and regenerates
   `INDEX.md` + the lock. Commit the result (the new `skill-sources.local.json`, the
   vendored `ce-*` dirs, `INDEX.md`, and `skill-sources.lock.json`).

3. **Tell the user where these skills actually belong.** They're for **code repositories**,
   not the knowledge vault:
   - To use them in your **software projects**, mirror the portable set into your machine's
     user-scope with the **`install-skills`** skill (or `.agents/scripts/sync-skills.sh
     --user-scope`) — then `/ce-plan`, `/ce-code-review`, etc. work in *every* project.
   - **Inside this vault, keep using the `kw-*` knowledge skills** (`/kw-plan`,
     `/kw-compound`, …). Don't run `ce-compound`/`ce-plan`/`ce-brainstorm` here: they write
     `docs/solutions/`, `docs/plans/`, `docs/brainstorms/` with a code-oriented schema that
     doesn't belong in the Obsidian graph. (The `.gitignore` already keeps `docs/plans/`
     and `docs/brainstorms/` out of git as a backstop, but the cleaner rule is simply:
     `ce-*` in code repos, `kw-*` in the vault.)

## Staying up to date (automatic)

Once added, the set keeps itself current with **zero curation**:

- **No allow-list** → every sync re-fetches the entire upstream `skills/` folder, so new
  or renamed Compound Engineering skills appear on their own, and skills they remove are
  pruned locally on the next clean sync.
- **Auto-refresh** → the `SessionStart` hook re-runs `sync-skills.sh` when the vendored
  copies go stale (>7 days) or a pointer breaks; a fresh copy takes effect next session.
- **On demand** → re-run this skill, or `.agents/scripts/sync-skills.sh`, to pull the
  latest immediately.
- **The one thing to watch:** if a sync prints `compound-engineering yielded no skills`,
  upstream moved the folder — update `skillsPath` in `skill-sources.local.json` (the sync
  keeps the last-good copy until you do, so nothing breaks in the meantime).

## Removing them later

Fully reversible — nothing here is load-bearing for the vault:
```bash
cd "$(git rev-parse --show-toplevel)"
LOCAL=.agents/skill-sources.local.json
jq '.sources |= map(select(.name != "compound-engineering"))' "$LOCAL" > "$LOCAL.tmp" && mv "$LOCAL.tmp" "$LOCAL"
.agents/scripts/sync-skills.sh   # a clean run prunes the now-unlisted ce-* skills
```
To silence a single one without removing the set, add
`{ "skillOverrides": { "ce-debug": "off" } }` to `.claude/settings.local.json`.

## Notes

- **Opt-in by design.** The base template ships this *capability*, not the skills
  themselves — a plain knowledge vault stays free of coding skills unless someone runs
  this. That's why the source is **local** (`skill-sources.local.json`), not base-owned.
- **No name or file collisions with the vault.** CE skills are `/ce-*`; the vault's
  workflow skills are `/kw-*` — different commands, different output directories. They
  coexist cleanly; the only guidance is *which plane to use where* (above).
- Hand-authored, repo-local skill — not vendored, so `sync-skills.sh` won't overwrite it,
  and `/update-base` propagates it to the fleet (so every vault can offer this opt-in).
