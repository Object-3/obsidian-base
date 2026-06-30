---
title: "Two knowledge planes: kw-* (vault) vs ce-* (code repos)"
type: decision-record
status: active
base_seed: true
tags: [skills, knowledge-base, compound-engineering, compound-knowledge, plugins, conductor, collisions, plumbing]
confidence: high
created: 2026-06-29
updated: 2026-06-29
source: install-skills session — resolving kw colon/dash duplicate + ce vs vault doc-output collisions
related:
  - "[[userscope-skill-mirror]]"
  - "[[vendor-skills-into-repo-for-cloud-sessions]]"
---

# Two knowledge planes: kw-* (vault) vs ce-* (code repos)

When the `compound-engineering` (`ce-*`) and `compound-knowledge` (`kw-*`) skill
families are both available — common when you run **Conductor across many worktrees of
this KB** — two questions come up: *do their generated docs collide?* and *which
invocation of the `kw-*` skills is the real one?* Both are config/convention problems,
not code problems.

## TL;DR

- **No file collision.** The families write to **different directories**, so nothing
  overwrites: `kw-*` → `docs/knowledge/` + `plans/`; `ce-*` → `docs/solutions/<category>/`
  + `docs/plans/`.
- **They don't integrate, either.** Each researcher reads only its own plane
  (`knowledge-base-researcher` ↔ `docs/knowledge/`; `ce-learnings-researcher` ↔
  `docs/solutions/`). Treat them as two stores, not one.
- **In the vault, use `kw-*`.** It's the committed, Obsidian-indexed deliverable.
  **Don't run CE knowledge-writing skills here** — they'd scatter a schema-incompatible
  store that pollutes the Obsidian graph and fails `lint-vault.sh`.
- **CE is repo-scoped by construction.** `ce-*` skills write **relative to the working
  directory**, so even installed *globally* their output lands in whatever code repo you
  run them in — exactly where engineering work belongs. No symlinking needed.
- **One copy, EveryInc's name.** Vault **vendors** the `kw-*` skills verbatim from EveryInc
  and **disables the `compound-knowledge` plugin** so the same skill isn't loaded twice. Their
  folder is `kw-compound` but the registered `name:` is `kw:compound` (colon — EveryInc's
  literal naming, kept as-is, not forked to dash), so the invocation is **`/kw:compound`**. They
  delegate to flat-named agents (`past-work-researcher`, …) vendored in `.agents/agents/`, so
  they resolve without the plugin.

## Why disable the plugin instead of un-vendoring

The vendored `kw-*` are committed, so they work in cloud/web/shared-clone sessions where
a plugin isn't installed (see [[vendor-skills-into-repo-for-cloud-sessions]]). The plugin
adds nothing the vault doesn't already have — it only *duplicates* the menu under a
namespace and revives the colon/dash confusion. So the decoupling is one-directional:
keep vendoring, set `compound-knowledge@compound-knowledge-plugin: false` in this repo's
`.claude/settings.json` (a project `false` overrides a global `true`, so it's scoped to
the vault — your other repos keep the live plugin).

## Caveats

- **Plugin enablement applies at session start**, not live — the namespaced duplicates
  clear on the *next* Claude Code session.
- **CE-in-vault isn't machine-blocked.** If you *do* run a `ce-*` knowledge skill here,
  `docs/solutions/` is not a dot-folder and isn't in Obsidian's `userIgnoreFilters`, so it
  would be indexed. The guard is convention (this note + `AGENTS.md`), not enforcement.
- **Subdirectory cwd misfiles CE output.** CE's relative paths assume cwd = repo root;
  invoking from a subdir would create `docs/` under that subdir. The harness launches
  skills from the repo root, so this is an edge case, not the norm.
