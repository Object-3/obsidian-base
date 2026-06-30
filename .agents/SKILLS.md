# Vendored skills — how this works

This repo vendors curated **GitHub-hosted Agent Skills** (the open `SKILL.md`
standard) into the repo and commits them, so they load in **every session of
every agent** — Claude Code, OpenAI Codex, Copilot, Cursor, Gemini — including
ephemeral cloud containers that do **not** auto-install marketplace/GitHub skills.

We only vendor skills that are **not** already available in your agent's cloud.
Built-in / official cloud-native skills are left alone.

## Agnostic-first layout

```
.agents/                      <- agnostic agent home (read by multiple tools)
├── skills/                   CANONICAL skills (real files, committed)
│   └── INDEX.md              auto-generated catalog of all skills + "use when"
├── agents/                   CANONICAL subagents
├── scripts/sync-skills.sh    the sync script
├── skill-sources.json        BASE-OWNED curated sources (refreshed by update-base)
├── skill-sources.local.json  THIS VAULT'S extra sources (never synced; optional)
└── skill-sources.lock.json   bookkeeping for clean re-sync
.claude/skills  -> ../.agents/skills    (pointer for Claude Code)
.codex/skills   -> ../.agents/skills    (pointer for OpenAI Codex)
.claude/agents  -> ../.agents/agents
```

The canonical files live in `.agents/` (the most agent-agnostic location). Each
tool's own skills directory is a **pointer** to it, so there's a single source of
truth and no duplication.

All of this sits under dot-folders, so **Obsidian ignores it** — skills never
appear in the vault's graph, search, or tag index.

## Adding / removing a skill

Add **your own** sources to `.agents/skill-sources.local.json` (create it if absent;
same `{"sources":[…]}` shape). Leave `.agents/skill-sources.json` to the base — it's
the curated list that `update-base` refreshes. `sync-skills.sh` **merges both**, with
local entries winning on a name collision (so you can override a base source).

1. Edit `.agents/skill-sources.local.json` (yours) — or `skill-sources.json` if you're
   the base maintainer:
   ```json
   { "sources": [
     { "name": "my-source", "repo": "owner/repo", "skillsPath": "skills",
       "agentsPath": "agents", "include": ["only-these","skill-dirs"] }
   ] }
   ```
   - `skillsPath` — directory in the repo under which each `*/SKILL.md` lives (default `skills`).
   - `include` — optional allow-list of skill directory names (cherry-pick across nested folders).
   - `agentsPath` / `ref` — optional (`*.md` agents; branch defaults to `main`→`master`).
2. Run `.agents/scripts/sync-skills.sh`.
3. Commit the changes under `.agents/` (and the pointer dirs).

Skill **command names come from the directory** (`.agents/skills/cro/` → `/cro`).
A colon in a skill's frontmatter `name` (e.g. `kw:plan`) is ignored — it loads as
`/kw-plan`.

### Self-contained agent references

Some vendored skills launch a subagent by a **plugin-namespaced** ID (e.g.
`compound-knowledge:research:stale-knowledge-checker`) that only resolves when the
upstream marketplace plugin is installed — which defeats the point of vendoring.
After vendoring, `sync-skills.sh` rewrites any such reference down to the **flat**
agent name (`stale-knowledge-checker`) **whenever that agent was also vendored flat
into `.agents/agents/`** — the form that resolves in every agent and every cloud
container. It only collapses names it can satisfy locally (an external
`compound-engineering:ce-foo` with no vendored `ce-foo.md` is left untouched), only
touches lock-tracked vendored files, and is idempotent — so repeated syncs and
upstream skill updates flow through cleanly.

## Updating

- Manual: `.agents/scripts/sync-skills.sh`, then commit.
- Automatic (Claude): a `SessionStart` hook re-syncs when copies are >7 days old
  **or** the pointers are broken. Skills are enumerated at launch, so a refresh
  takes effect next session; the committed files cover the current one.

## Cross-platform / Windows note

Pointers are **symlinks** on macOS/Linux/cloud (lean, no duplication). On a
checkout where symlinks aren't supported — notably **Windows without Developer
Mode / `git config core.symlinks=true`** — the committed symlinks may arrive as
plain text files. The sync script **detects this and automatically falls back to
real copies** of the canonical skills into `.claude/skills` / `.codex/skills`, and
the Claude `SessionStart` hook re-runs the sync when it sees broken pointers. So
the Windows path self-heals on first sync — no manual steps. The only consequence
is that those copied directories are real files rather than links on that machine.

## Behavior across devices (graceful by design)

Skills resolve by scope precedence:
**enterprise > personal (`~/.claude`) > project (`.claude`) > plugin > bundled.**
Collisions never error — the highest-precedence one silently wins.

- **Plugin installed locally** (e.g. Compound Knowledge via a marketplace): plugin
  skills are namespaced (`/compound-knowledge:…`), so they don't collide with the
  vendored `/kw-*`. Both exist side by side.
- **Same skill at user level** (`~/.claude/skills/cro`): your personal copy wins
  while you work here; the vendored copy is the fallback that makes cloud work.
- **Cloud / fresh machine:** the committed vendored copy is used.

To suppress a vendored skill locally, add `skillOverrides` in
`.claude/settings.local.json`: `{ "skillOverrides": { "kw-plan": "off" } }`.

## User-scope mirror (skills in every project)

Vendoring scopes skills to **this vault**. To also use the portable skills in
**other projects** on your machine, **mirror** them into each tool's user-scope —
this is **additive**, the in-repo vendored copy (what cloud/web sessions need) is
untouched.

- **Enable / refresh:** the **`/install-skills`** skill, or at onboarding
  (`MIRROR_SKILLS=yes`). Under the hood: `sync-skills.sh --user-scope` (re-fetch +
  mirror) or `--mirror-only` (mirror the committed lock, offline).
- **Targets:** `~/.claude/skills` (Claude Code, the Claude Desktop **Code tab**, and
  Conductor via shared `$HOME`) and `~/.agents/skills` (Codex's native user-scope).
  Only the **lock-tracked portable set** is mirrored — the hand-authored vault-engine
  skills (everything *not* in the lock) are never installed globally.
- **Safe + reversible-but-retained:** a manifest
  (`${XDG_CONFIG_HOME:-~/.config}/obsidian-base/skill-mirror.json`) makes it
  non-destructive (your own same-named skills are never overwritten) and refreshes
  ours-only. Offboarding **keeps** these skills — they're yours.
- **Caveat:** personal scope shadows project scope locally (precedence
  `personal > project`); across multiple vaults the mirror is last-writer-wins, which
  the `/install-skills` status check (`sync-skills.sh --status`) flags via the manifest's
  recorded source hash + vault path.
- **Not for chat surfaces:** claude.ai chat takes skills only as a manual zip upload;
  ChatGPT has none. The mirror targets the scriptable CLI tools only.

See [`docs/knowledge/userscope-skill-mirror.md`](../docs/knowledge/userscope-skill-mirror.md).

## Discovery

`.agents/skills/INDEX.md` is auto-generated on every sync from each skill's
frontmatter (`name` + `description`). It gives any agent — including a bare
OpenAI chat with no skill support — an at-a-glance list of what's available and
when to use it. It's also linked from `llms.txt` and `AGENTS.md`.
