---
type: correction
base_seed: true
tags: [setup, add-vault, init-vault, git, branch, gotcha]
confidence: high
created: 2026-07-02
source: setting up a second topic vault via /add-vault — found personalization sitting uncommitted since creation, and the vault on `master` instead of `main`; fixed in the same change that added this note
related:
  - "[[onedrive-sensitive-plane-setup-gotchas]]"
  - "[[ephemeral-fetch-remote-pattern]]"
---

# A freshly created vault has rough, uncommitted edges — don't assume "created" means "clean"

Before this fix, `setup.sh` and `add-vault.sh` both committed **"Initial vault from
obsidian-base"** *before* running `init-vault.sh`'s personalization step. So the first
commit in a new vault's history actually captured the **unfilled** `{{VAULT_NAME}}` /
`{{VAULT_TAGLINE}}` / `{{VAULT_PURPOSE}}` / `{{PRIMARY_TAG}}` placeholders in
`vault-profile.md`, `index.md`, `log.md`, and `llms.txt` — the real personalization
landed on disk right after, but nothing re-committed it. It sat **uncommitted
indefinitely** unless something else (Obsidian Git's auto-commit timer, or a person/agent
running `git commit` for an unrelated reason) happened to sweep it up.

Separately: `git init -q` inherited whatever branch name the machine's global
`init.defaultBranch` git config resolved to — not necessarily `main`. On the machine
this was observed on, that produced `master` for a new vault, silently inconsistent with
the fleet's `main` convention.

## Context

Running `/add-vault` to create a second topic vault beside an existing one. Days into
the session, `git status` on the new vault still showed `vault-profile.md`/`index.md`/
`log.md`/`llms.txt` as modified relative to `HEAD` — the diff was the
placeholder-to-real-value personalization from the very first `init-vault.sh` run at
vault creation, never committed. The vault was also found on branch `master`, requiring
a manual rename to `main` before it made sense to connect GitHub.

## Implication

Fixed at the source: `create_vault`/the vault-creation block in `setup.sh` and
`add-vault.sh` now `git init -b main` explicitly, and the personalization step
(`init-vault.sh`) runs **before** the one initial commit, not after — so a fresh vault's
first commit already reflects its real name/tagline/tag, and its default branch is
always `main` regardless of the machine's git config. Anyone still on an older vault
created before this fix should check `git status` and `git branch --show-current`
before treating it as clean, especially before connecting GitHub (`connect-github.sh`
pushes whatever the *current* branch is).
