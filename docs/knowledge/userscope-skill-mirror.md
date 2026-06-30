---
title: "User-scope skill mirror (portable skills without un-vendoring)"
type: playbook
status: active
base_seed: true
tags: [skills, user-scope, portability, claude-code, codex, conductor, mirror, offboard]
confidence: high
created: 2026-06-29
updated: 2026-06-29
source: /ce-work implementing the user-scope skill mirror (decoupling brainstorm → plan → work)
related:
  - "[[vendor-skills-into-repo-for-cloud-sessions]]"
  - "[[llm-agnostic-agent-repo-layout]]"
---

# User-scope skill mirror (portable skills without un-vendoring)

The vault's portable skills can be **mirrored into your machine's user-scope** so they
work in *every* project — not just inside the vault — while the in-repo vendored copy
stays exactly as it is. The two are complementary, not either/or: vendoring is what
cloud / Claude-Code-on-the-web / shared-clone sessions need (see
[[vendor-skills-into-repo-for-cloud-sessions]]); the user-scope mirror is a local
convenience layered on top.

## TL;DR

- **Don't un-vendor to "declutter."** Removing committed skills breaks the cloud/web/
  phone and shared-clone cases — local install can't reach a different machine. Keep
  vendoring; *add* the mirror.
- Enable with the **`/install-skills`** skill, or opt in during onboarding
  (`MIRROR_SKILLS=yes`). Refresh/check the same way.

## How it works

- `.agents/scripts/sync-skills.sh --user-scope` (full, re-fetches) or `--mirror-only`
  (fast, mirrors the committed lock without network) copies the **lock-tracked portable
  set** — the `.skills[]` in `.agents/skill-sources.lock.json` — into:
  - `~/.claude/skills/` — Claude Code, the Claude Desktop **Code tab**, and Conductor (shared `$HOME`)
  - `~/.agents/skills/` — OpenAI Codex's native user-scope
- The **hand-authored vault-engine skills** — everything *not* in the lock (`onboard`,
  `setup-vault`, `update-base`, `offboard`, `normalize-vault`, `ingest-pdf`, plus
  `install-skills` itself) — are never mirrored; they only make sense inside a vault.
- A machine-global manifest (`${XDG_CONFIG_HOME:-~/.config}/obsidian-base/skill-mirror.json`,
  `{owned, lock_hash, vault_path, written}`) makes the install **non-destructive**
  (a same-named skill you installed yourself is never overwritten) and refreshes
  **ours-only**. `lock_hash` is the drift signal; `vault_path` flags a cross-vault writer.

## Caveats

- **Precedence: personal > project.** Your user-scope copy shadows the vault's in-repo
  copy locally. Within one vault both come from the same registry, so they match; across
  multiple vaults the mirror is **last-writer-wins** (the `/install-skills` status check —
  `sync-skills.sh --status`, exit 0/1/2 — flags it).
- **Refresh reverts edits to a *mirrored* skill.** The non-destructive guard protects
  skills *you* installed (a same-named skill we never wrote is never touched). But once a
  skill is **ours**, a refresh overwrites it with the vault's copy — so local edits to a
  mirrored skill are lost on the next refresh. Fork it under a new name to customize one.
- **Offboarding keeps them.** Disconnecting a vault (`offboard`) removes only the MCP
  wiring + the global rules block — never your skills. They're yours; delete manually if
  you ever want them gone.
- **Consumer chat can't be scripted.** Claude.ai chat takes skills only as a manual zip
  upload (Settings → Capabilities); ChatGPT has no SKILL.md runtime. The mirror targets
  the scriptable CLI surfaces only.
- **Codex path / Conductor inheritance** are docs-/inference-verified; confirm against a
  live install if a skill doesn't resolve. (A freshly installed personal skill in Claude
  Code may be invocable-by-name before it reliably *auto-triggers* — a known upstream quirk.)
