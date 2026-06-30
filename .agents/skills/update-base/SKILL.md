---
name: update-base
description: Pull the latest base-layer improvements (skills engine, scripts, AGENTS.md, hooks, curated skill sources) from the upstream base repo into this vault, without touching the user's notes, vault profile, or custom skill sources. Use when the user says "update the base", "sync the base vault", "get the latest base", "pull base updates", or wants the benefit of upstream base improvements. Git-native; safe for any downstream (fork, template instance, or clone).
---

# Update from the base repo

Bring this vault's shared base layer up to date with the upstream base. It's
**git-native** (fetches a `base` git remote — no tarballs), overlays only base-owned
engine paths, and prunes files the base removed. Your notes,
`.agents/vault-profile.md`, and `.agents/skill-sources.local.json` are left untouched.

This is an **engine change** — do it on a branch and open a PR (ideally from a
separate checkout, not the live auto-syncing vault). See "content vs engine" in `AGENTS.md`.

## Steps

1. **Run the updater:**
   ```bash
   .agents/scripts/update-base.sh
   ```
   Override the source if needed: `BASE_REPO=owner/repo .agents/scripts/update-base.sh`,
   or `BASE_REPO_URL=<any git url>`, or pin with `BASE_REF=v1.2.0` (or a `.agents/.base-ref`
   file). It refreshes only base-owned engine files (`AGENTS.md`, `CLAUDE.md`,
   `.gitignore`, `.gitattributes`, `.agents/SKILLS.md`, `.agents/skill-sources.json`,
   `.agents/scripts/*`, `.claude/hooks/*`, `.claude/settings.json`), prunes removed
   files, and reports what changed. Changes are left **staged**.

2. **Re-sync skills** (the curated `skill-sources.json` may have changed):
   ```bash
   .agents/scripts/sync-skills.sh
   ```
   This merges the base's curated sources with your `skill-sources.local.json`, so
   base curation updates flow in while your custom sources persist.

   If `update-base.sh` printed a note that your **user-scope mirror** may be out of date
   (it detects the manifest), the global copies don't auto-refresh. **Offer** to run
   `/install-skills` (or `sync-skills.sh --mirror-only`) — consent-gated; don't auto-run.

3. **Review, commit on a branch, open a PR.** `git diff --staged` to review.

4. Append a one-line entry to `log.md` noting the base update.

## Notes

- This is a hand-authored, repo-local skill — not vendored — so `sync-skills.sh`
  won't overwrite it.
- For non-technical users: an agent running this on their behalf is all they need to
  receive base improvements. Skipping it just means they stay on the version they
  have — no breakage.
