---
name: update-base
description: Pull the latest base-layer improvements (skills engine, scripts, AGENTS.md, hooks) from the upstream base vault into this vault, without touching the user's notes or vault profile. Use when the user says "update the base", "sync the base vault", "get the latest base", "pull base updates", or wants the benefit of upstream base improvements. Safe for any downstream (fork, template instance, or clone).
---

# Update from the base vault

Bring this vault's shared base layer up to date with the upstream base vault. Your
notes, `.agents/vault-profile.md`, and your skill list are left untouched, so this
never causes drift in your content.

## Steps

1. **Run the updater:**
   ```bash
   .agents/scripts/update-base.sh
   ```
   (Override the source if needed: `BASE_REPO=owner/repo BASE_REF=main .agents/scripts/update-base.sh`.)
   It refreshes only base-owned engine files (`AGENTS.md`, `CLAUDE.md`, `.gitignore`,
   `.agents/SKILLS.md`, `.agents/scripts/*.sh`, `.claude/hooks/*.sh`,
   `.claude/settings.json`) and reports what changed.

2. **Re-sync skills** (scripts may have changed):
   ```bash
   .agents/scripts/sync-skills.sh
   ```

3. **Review & commit.** `git diff` to see the base changes, then commit. If the base
   added new skill *sources* you want, compare `.agents/skill-sources.json` against
   the base copy and merge the entries you want (this file is yours, so it isn't
   auto-overwritten).

4. Append a one-line entry to `log.md` noting the base update.

## Notes

- This is a hand-authored, repo-local skill — not vendored — so `sync-skills.sh`
  won't overwrite it.
- For non-technical users: running this (or asking an agent to "update the base") is
  all they need to receive the maintainer's base improvements. Skipping it just
  means they stay on the version they have — no breakage.
