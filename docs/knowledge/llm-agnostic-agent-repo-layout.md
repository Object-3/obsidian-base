---
type: playbook
base_seed: true
tags: [agents, agnostic, agents-md, claude-md, skills, codex, openai, symlink, windows, portability]
confidence: high
created: 2026-06-27
source: /kw-compound after making the vault usable by any agent (Claude primary) instead of Anthropic-coupled
related:
  - "[[vendor-skills-into-repo-for-cloud-sessions]]"
  - "[[vet-vendored-skills-and-avoid-sync-clobber]]"
  - "[[userscope-skill-mirror]]"
---

# LLM-agnostic agent-repo layout (Claude primary, any agent supported)

As of 2026 the two things that mattered became open, multi-vendor standards:
**`AGENTS.md`** (cross-tool instruction file, stewarded by the Linux Foundation;
Claude Code reads it too) and the **`SKILL.md`** "Agent Skills" format
(Anthropic-originated, now read by OpenAI Codex, Gemini CLI, Copilot, Cursor). So a
repo can be agnostic without losing first-class Claude support.

## Context

The vault was structured around `CLAUDE.md` + `.claude/skills`, which only Claude
reads. We wanted someone cloning with OpenAI/Codex to get the value immediately.

## Implication

- **Instructions:** put the canonical contract in `AGENTS.md`; make `CLAUDE.md` a
  thin `@AGENTS.md` import + Claude-only notes (Claude expands the import at load).
- **Skills:** canonical files in agnostic `.agents/skills/` (+ `.agents/agents/`);
  make `.claude/skills` and `.codex/skills` **pointers** to it — one source of truth.
- **Windows:** pointers are symlinks on mac/Linux/cloud; the sync script
  auto-falls-back to real copies where symlinks aren't supported, and the
  SessionStart hook re-syncs on broken pointers — self-healing, no manual steps.
- **Discovery:** auto-generate `.agents/skills/INDEX.md` (each skill + "use when")
  and an `llms.txt` entry point so even an agent without skill support can orient.
  Strong skill `description` fields matter more than any router.
