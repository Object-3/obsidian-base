---
type: correction
base_seed: true
tags: [skills, vendoring, gotcha, sync, customization, hardcoded-paths, matt-pocock]
confidence: high
created: 2026-06-27
source: /kw-compound — the obsidian-vault skill shipped with hardcoded personal paths; hand-edits get clobbered by sync
related:
  - "[[vendor-skills-into-repo-for-cloud-sessions]]"
  - "[[llm-agnostic-agent-repo-layout]]"
---

# Vet vendored skills for hardcoded paths; hand-author repo-aware skills outside the sync

Vendored third-party skills can carry **author-specific assumptions** — Matt
Pocock's `obsidian-vault` skill hardcoded his own vault path
(`/mnt/d/Obsidian Vault/AI Research/`) and naming conventions, so it pointed at
the wrong directory and conflicted with this vault's `AGENTS.md` contract. It
loaded fine but would not behave as expected; we dropped it.

## Context

While verifying skills resolved through the new `.agents/skills` pointers, a
test-load of `obsidian-vault` surfaced the hardcoded paths. A scan
(`grep -rE '/mnt/|/Users/|/home/'`) found it was the only skill with this problem;
the `kw-*` and Corey Haines marketing skills are generic.

## Implication

- **Vet `SKILL.md` for absolute/personal paths** before relying on a vendored
  skill. Prefer agnostic skills; for live-vault interaction use the Obsidian MCP /
  a KB endpoint, not a path-coded skill.
- **Don't hand-edit a vendored skill** — the next `sync-skills.sh` re-downloads and
  clobbers it. To customize, remove it from `.agents/skill-sources.json` and
  **hand-author a repo-aware skill directly in `.agents/skills/`**. Hand-made
  skills aren't in `skill-sources.lock.json`, so the sync's cleanup leaves them
  untouched.
