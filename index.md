---
title:   "Index — {{VAULT_NAME}}"
type:    index
status:  active
tags:    [{{PRIMARY_TAG}}, index]
created: 2026-06-27
updated: 2026-07-21
---

# Index

Catalog of every note in this vault. **Read this first** to orient. Update it
whenever you add or materially change a note (see operating rules in `AGENTS.md`).

> Tip: organize by topic sections below, or keep notes flat and navigate by
> `type`/`status`/`tags` frontmatter — Obsidian doesn't need folders.

## Notes

- [[cloud-mcp-deployment-architecture]] — `decision-record` · opt-in AWS cloud deployment of a vault as an authenticated read/write MCP endpoint: narrow markdown-only server composed with native M365/Drive MCPs, Fargate-first with a clean AgentCore migration path, three-tier data-control ladder (shareable → confidential → PHI) enforced by OAuth scopes, `_sensitive/` retained as the routing boundary.

## Plans

- `plans/` — in-progress plans & brainstorms.

## Compounded learnings (`docs/knowledge/`)

How this vault's agent scaffolding works (kept from the base template — useful
background for anyone building on it):

- [[vendor-skills-into-repo-for-cloud-sessions]] — `playbook` · why skills are vendored into the repo.
- [[llm-agnostic-agent-repo-layout]] — `playbook` · AGENTS.md + SKILL.md are open standards; `.agents/` canonical + tool pointers.
- [[vet-vendored-skills-and-avoid-sync-clobber]] — `correction` · vet skills for hardcoded paths; hand-author repo-aware skills outside the sync.
- [[userscope-skill-mirror]] — `playbook` · mirror portable skills into user-scope so they work in every project (additive to vendoring; survives offboard).
- [[kw-and-ce-knowledge-planes]] — `decision-record` · `kw-*` → `docs/knowledge`+`plans` (the KB); `ce-*` → `docs/solutions`, repo-scoped; vault disables the `compound-knowledge` plugin — invoke `/kw:compound` (EveryInc's literal name).
- [[fresh-vault-uncommitted-personalization-and-branch-drift]] — `correction` · `setup.sh`/`add-vault.sh` used to commit before `init-vault.sh` personalized, and `git init` inherited the machine's default branch — fixed to `git init -b main` + personalize-then-commit.
- [[onedrive-sensitive-plane-setup-gotchas]] — `pattern` · four OneDrive `/setup-sensitive-plane` gotchas: `brew install --cask` fails headlessly, the pin-local right-click needs the Finder Sync Extension enabled (Files-On-Demand toggle is a simpler fallback), a self-referential symlink `check` now catches, and `link`'s `.gitignore` line used to get wiped by `/update-base` (now written to `.git/info/exclude` instead).
- [[ephemeral-fetch-remote-pattern]] — `playbook` · make the base-update fetch remote ephemeral via a dedicated reclaimable name (`base-ephemeral`); crash-orphan self-heals, never mutates the user's own remote; EXIT trap fires on SIGINT/SIGTERM but not SIGKILL.
- [[connect-github-naming-parity-and-push-resilience]] — `correction` · `connect-github.sh` now defaults the repo name to the vault's MCP label (`obsidian-<slug>`, not the bare folder name) and retries a transient push failure over HTTP/1.1 before giving up — a failed push used to silently skip the auto-sync re-enable step too.
