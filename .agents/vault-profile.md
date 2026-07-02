---
vault_name:  "{{VAULT_NAME}}"
primary_tag: "{{PRIMARY_TAG}}"
dream_session_scope: "this-checkout"   # this-checkout | all-worktrees (see below)
---

# Vault profile

This is the **only** per-vault customization file. The base layer (`AGENTS.md`,
scripts, skills) never edits it, so pulling base updates stays conflict-free.
Run `.agents/scripts/init-vault.sh` (or the `/setup-vault` skill) to fill it in.

## What this KB is about

> {{VAULT_TAGLINE}}

{{VAULT_PURPOSE}}

## Conventions specific to this vault

- **Primary tag:** every note's frontmatter `tags` includes `{{PRIMARY_TAG}}`.
- (Add any vault-specific conventions, topic areas, or house style here.)

## Self-improvement (the dream)

The **`/vault-dream`** skill folds learnings from your agent sessions into the knowledge
base and consolidates the vault, on its own branch + pull request (PR). One toggle here
controls how widely it looks for sessions:

- **`dream_session_scope`** (frontmatter, above) — `this-checkout` (default) reads only
  the current checkout's agent sessions; `all-worktrees` reads every git worktree of this
  vault (useful when you run agents across several parallel worktrees). Omit or leave as
  `this-checkout` and nothing changes. The watermark (`.agents/dream-state`) advances only
  when the dream's PR is merged/applied, so an abandoned run safely reconsiders those
  sessions next time.

## Topical folders (this vault)

Declared topic folders (promote a topic here once it exceeds ~5–8 root notes — see
the topical-folder convention in `AGENTS.md`):

- _(none yet — root-only is fine until the vault grows)_

<!-- BEGIN sensitive-plane (managed by setup-sensitive-plane) -->
## Sensitive plane backing store

Where the gitignored `_sensitive/` (Sensitive) plane physically lives and how agents reach it.
Maintained by `/setup-sensitive-plane`. No secrets/paths here (vault-profile is in git).

- **Status:** not configured — `_sensitive/` lives on this machine only (unbacked). Run
  `/setup-sensitive-plane` to back it up + make it multi-device, confidentially.
<!-- END sensitive-plane -->

