---
name: update-base
description: Pull the latest base-layer improvements (skills engine, scripts, AGENTS.md, hooks, curated skill sources) from the upstream base repo into this vault, without touching the user's notes, vault profile, or custom skill sources. Use when the user says "update the base", "sync the base vault", "get the latest base", "pull base updates", or wants the benefit of upstream base improvements. Git-native; safe for any downstream (fork, template instance, or clone).
---

# Update from the base repo

Bring this vault's shared base layer up to date with the upstream base. It's
**git-native** (fetches via an ephemeral `base-ephemeral` git remote — added for the fetch,
then removed, so no standing remote can be mis-picked in Obsidian Git; no tarballs), overlays
only base-owned engine paths, and prunes files the base removed. Your notes,
`.agents/vault-profile.md`, and `.agents/skill-sources.local.json` are left untouched.

This is an **engine change** — do it on a branch and open a PR (ideally from a
separate checkout, not the live auto-syncing vault). See "content vs engine" in `AGENTS.md`.

## Steps

1. **Run the updater:**
   ```bash
   .agents/scripts/update-base.sh
   ```
   Override the source if needed: `BASE_REPO=owner/repo .agents/scripts/update-base.sh`,
   or `BASE_REPO_URL=<any git url>` (per-invocation only), or pin with `BASE_REF=v1.2.0`
   (or a `.agents/.base-ref` file). It refreshes only base-owned engine files (`AGENTS.md`,
   `CLAUDE.md`, `.gitignore`, `.gitattributes`, `.agents/SKILLS.md`,
   `.agents/skill-sources.json`, `.agents/scripts/*`, `.claude/hooks/*`,
   `.claude/settings.json`), prunes removed files, and reports what changed. Changes are
   left **staged**. It never touches the vault-local extension points
   `.githooks/pre-commit.d/` and `.claude/hooks-local/` (+ `.claude/settings.local.json`)
   — those survive every update, in both directions (your guards are kept; the base
   can't plant files there either).

   **Read the `!!` warnings — they are loss reports, not noise.** The overlay is
   whole-file replacement, so the script calls out what it can detect it is dropping:
   - `!! pruned NON-BASE file '<f>'` — a file tracked in this vault but absent from
     the base tree was deleted. If the base removed it, fine; if it was a
     **vault-local addition** (a custom hook/guard), restore it from git history and
     move it to the matching extension point above, then relay that to the user.
   - `!! '<f>': N '# vault-local:'-marked line(s) are NOT in the incoming base copy`
     — marked vault-local lines inside a base-owned file are being dropped;
     re-apply them via the extension points (or re-add after the run).
   Unmarked in-file edits (e.g. a bare extra `.gitignore` line) still revert
   silently — the marker convention is what makes them detectable.

   Every run (including a no-op "Already up to date" one) also writes and stages
   `.agents/.base-sync` — `<sha> <ref> <iso-timestamp>` (+ `partial-skills` if the
   base-authored skill overlay was skipped for lack of `jq`). That's the freshness
   stamp `/doctor` reads to measure base staleness; expect it in the staged diff.

   **Point an existing vault at a fork permanently:** write the bare git URL (no
   `user:token@` credentials — the file is tracked) to `.agents/.base-url`, then run
   update-base. Env `BASE_REPO_URL=` overrides for one run only; the file is the
   persistent primitive. To return to the public default, delete `.agents/.base-url`.

2. **Re-sync skills** (the curated `skill-sources.json` may have changed):
   ```bash
   .agents/scripts/sync-skills.sh
   ```
   This merges the base's curated sources with your `skill-sources.local.json`, so
   base curation updates flow in while your custom sources persist.

   If `update-base.sh` printed a note that your **user-scope mirror** may be out of date
   (it detects the manifest), the global copies don't auto-refresh. **Offer** to run
   `/install-skills` (or `sync-skills.sh --mirror-only`) — consent-gated; don't auto-run.

3. **Review, commit on a branch, open a PR.** `git diff --staged` to review — the
   staged `.agents/.base-sync` stamp is expected (per-vault state, not an engine
   edit; on a no-op run it may be the *only* staged change, and a plain commit of
   just the stamp needs no `BASE_UPDATE=1`). For a real overlay, commit with
   `BASE_UPDATE=1 git commit …` — the pre-commit engine guard blocks other engine
   edits in a derived vault, and this marks the one sanctioned kind.

4. Append a one-line entry to `log.md` noting the base update.

## Notes

- **If the updater (or anything else in the engine) misbehaves in this vault, do NOT
  fix the script here and do NOT open a PR against the base repo** — a local patch is
  overwritten by the next base update and helps no other clone. **File a GitHub issue
  against the upstream base repo** (the URL in `.agents/.base-url`, else
  `Object-3/obsidian-base`) with the error output and your proposed fix in the issue
  body. See *Engine bugs & improvements found in a derived vault* in `AGENTS.md`.
- This is a hand-authored, repo-local skill — not vendored — so `sync-skills.sh`
  won't overwrite it.
- For non-technical users: an agent running this on their behalf is all they need to
  receive base improvements. Skipping it just means they stay on the version they
  have — no breakage.
