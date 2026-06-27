@AGENTS.md

# Claude Code specifics

The full, tool-agnostic contract lives in **`AGENTS.md`** (imported above). This
file adds only what's specific to Claude Code.

- **Skills & subagents** auto-load from `.claude/skills/` and `.claude/agents/`,
  which are pointers to the canonical `.agents/skills/` and `.agents/agents/`.
  Invoke skills as `/cro`, `/kw-plan`, `/writing-shape`, etc. See the catalog at
  `.agents/skills/INDEX.md`.
- **Auto-refresh:** a `SessionStart` hook (`.claude/hooks/sync-skills-if-stale.sh`)
  re-runs the sync when the vendored skills are stale (>7 days) or the pointers
  are broken. It runs in the background and takes effect on the next session.
- **Compound Knowledge workflow:** `/kw-brainstorm` → `/kw-plan` → `/kw-confidence`
  → `/kw-review` → `/kw-work` → `/kw-compound`.
- Other agents (Codex, Copilot, Cursor, Gemini) read `AGENTS.md` and the same
  vendored skills directly — nothing here is required for them.
