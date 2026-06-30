---
title:   "Activity Log"
type:    index
status:  active
tags:    [{{PRIMARY_TAG}}, log]
created: 2026-06-27
updated: 2026-06-29
---

# Log

Append-only record of what happened and when — note ingests, major edits, syncs,
lint passes. Newest at the bottom. Prefix entries with `## [YYYY-MM-DD] <type> | <summary>`.

## [2026-06-27] init | Vault created from obsidian-base-vault template
- Agnostic agent layer in place: `AGENTS.md` contract, `.agents/skills` (vendored,
  with `.claude`/`.codex` pointers), Karpathy LLM-Wiki backbone (`index.md`, this
  `log.md`).
- Next: run `.agents/scripts/init-vault.sh` to customize, then start adding notes.

## [2026-06-29] feat | User-scope skill mirror (engine)
- Added an opt-in mirror of the vendored portable skills into user-scope
  (`~/.claude/skills`, `~/.agents/skills`) so they work in every project, not just the
  vault. Surfaces: `sync-skills.sh --user-scope`/`--mirror-only`, the `/install-skills`
  skill, onboarding opt-in (`MIRROR_SKILLS`), offboard retain-and-inform, `update-base`
  propagation + refresh nudge. Vendoring + cloud path unchanged. See [[userscope-skill-mirror]].

## [2026-06-29] fix | Harden user-scope mirror + decouple from compound-knowledge plugin
- `sync-skills.sh`: stage the user-scope mirror in the target's **parent** dir, not the
  skills root, so a host's skill scanner never catches a half-written `.tmp` dir
  mid-rename; smoke test grows a guard (now 13/13).
- Disabled the `compound-knowledge` plugin in this repo (`.claude/settings.json`) so the
  vendored dash-form `kw-*` are the single invocation — kills the `kw:` / `compound-knowledge:`
  menu duplicate. Documented the two knowledge planes (`kw-*` vs `ce-*`) in `AGENTS.md`.
  See [[kw-and-ce-knowledge-planes]].
