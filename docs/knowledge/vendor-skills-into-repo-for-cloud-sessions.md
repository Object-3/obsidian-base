---
type: playbook
base_seed: true
tags: [skills, cloud, claude-code, codex, agents, vendoring, portability, web-sessions]
confidence: high
created: 2026-06-27
source: /kw-compound after setting up the vault so /kw-* and marketing skills work in Claude Code on the web
related:
  - "[[llm-agnostic-agent-repo-layout]]"
  - "[[vet-vendored-skills-and-avoid-sync-clobber]]"
---

# Vendor GitHub-hosted skills into the repo for cloud sessions

Cloud / "Claude Code on the web" containers are ephemeral and do **not**
auto-install marketplace or GitHub plugins, so skills declared in `settings.json`
(`enabledPlugins` + `extraKnownMarketplaces`) silently fail to load there even
when the marketplace is reachable. The fix is to **vendor the skills' files into
the repo and commit them**, so a fresh clone has them with zero install step.

## Context

`compound-knowledge` was enabled in `.claude/settings.json` but its `/kw-*` skills
never appeared in a web session. Network was fine (the GitHub marketplace returned
HTTP 200); the cloud harness just doesn't run the plugin-install step.

## Implication

- Don't rely on `enabledPlugins`/marketplaces for skills you need in cloud. Vendor
  them: registry in `.agents/skill-sources.json`, synced by
  `.agents/scripts/sync-skills.sh` (tarball download — `git clone` is blocked by
  the agent proxy; codeload `.tar.gz` over HTTPS works).
- Commit the vendored output; that's what guarantees first-session availability.
- A `SessionStart` hook can refresh stale copies, but skills are enumerated at
  launch, so a refresh only takes effect **next** session — committed copies cover
  the current one.
