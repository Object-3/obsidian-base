---
name: setup-vault
description: One-time onboarding for a vault created from the base vault. Use when the user just cloned/forked/templated the base vault, says "set up this vault", "onboard", "customize the template", or `.agents/vault-profile.md` still contains {{PLACEHOLDER}} tokens. Fills in the vault's name, tagline, purpose, and primary tag (into the profile), then runs the skill sync.
---

# Set up this vault (onboarding)

This vault was created from the base vault and still has template placeholders in
`.agents/vault-profile.md`. Personalize it quickly, then sync skills.

## Steps

1. **Check it's needed.** Grep for `{{` in `.agents/vault-profile.md` (and `index.md`,
   `llms.txt`, `README.md`). No placeholders → already set up; say so and stop.

2. **Gather four things** (one short round):
   - **Vault name** — e.g. "Acme Strategy KB"
   - **Tagline** — one line describing the vault
   - **Purpose** — a sentence or two on what it's about
   - **Primary tag** — lowercase, goes on every note (e.g. `acme`)

3. **Apply** via the onboarding script:
   ```bash
   VAULT_NAME="..." VAULT_TAGLINE="..." VAULT_PURPOSE="..." PRIMARY_TAG="..." \
     .agents/scripts/init-vault.sh --yes
   ```
   It writes `.agents/vault-profile.md` and fills the content files (`index.md`,
   `llms.txt`, `log.md`, `README.md`), then runs `sync-skills.sh`. `AGENTS.md` is
   base-owned and intentionally left untouched. If you can't run scripts, make the
   same edits directly (only in `.agents/vault-profile.md` + those content files).

4. **Confirm.** Report what was set, that skills synced (see `.agents/skills/INDEX.md`),
   and suggest the first note per the `AGENTS.md` frontmatter contract. Append an
   entry to `log.md`.

## Notes

- Hand-authored, repo-local skill — not vendored, so `sync-skills.sh` won't overwrite it.
- To receive future base improvements later, use `/update-base`.
- This skill can be deleted after onboarding if you don't want it lingering.
