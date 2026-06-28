---
title:   "Activity Log"
type:    index
status:  active
tags:    [{{PRIMARY_TAG}}, log]
created: 2026-06-27
updated: 2026-06-27
---

# Log

Append-only record of what happened and when — note ingests, major edits, syncs,
lint passes. Newest at the bottom. Prefix entries with `## [YYYY-MM-DD] <type> | <summary>`.

## [2026-06-27] init | Vault created from obsidian-base-vault template
- Agnostic agent layer in place: `AGENTS.md` contract, `.agents/skills` (vendored,
  with `.claude`/`.codex` pointers), Karpathy LLM-Wiki backbone (`index.md`, this
  `log.md`).
- Next: run `.agents/scripts/init-vault.sh` to customize, then start adding notes.
