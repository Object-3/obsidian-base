---
vault_name:  "{{VAULT_NAME}}"
primary_tag: "{{PRIMARY_TAG}}"
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

## Topical folders (this vault)

Declared topic folders (promote a topic here once it exceeds ~5–8 root notes — see
the topical-folder convention in `AGENTS.md`):

- _(none yet — root-only is fine until the vault grows)_
