# Knowledge base — agent contract

<!-- This file is BASE-OWNED. Don't put per-vault specifics here — they go in
     `.agents/vault-profile.md`, so pulling base updates stays conflict-free.
     New here? Run `.agents/scripts/init-vault.sh` (or "/setup-vault"). -->

This file is the **canonical, tool-agnostic contract** for working in this repo. It
follows the [AGENTS.md](https://agents.md) standard, so Claude Code, OpenAI Codex,
GitHub Copilot, Cursor, Gemini CLI, and any other agent read the same rules.
`CLAUDE.md` imports this file and adds only Claude-specific notes.

This repository is an **Obsidian vault used as a knowledge base**. The notes are the
artifact; they are plain Markdown and fully usable without any tool.

## This vault's identity

**Read [`.agents/vault-profile.md`](.agents/vault-profile.md) first** — it holds this
vault's name, what it's about, its **primary tag**, and any vault-specific
conventions. (That file is the only per-vault customization; everything else here is
shared base scaffolding.) Don't add secrets, credentials, or regulated/personal data.

## Frontmatter (the real "dependency")

Every note starts with YAML at line 1:
```yaml
---
title:   "Human-readable title"
type:    decision-record | research | playbook | scratch | index
status:  active | draft | reference | archived
tags:    [<primary-tag>, ...topical]   # lowercase; always include the vault's primary tag (see vault-profile.md)
created: YYYY-MM-DD
updated: YYYY-MM-DD
confidence: high | medium | low         # optional: your epistemic state on the claims
sources:  N                              # optional: how many distinct sources inform this note
related:                                 # optional, list of links
  - "[[Another Note]]"
---
```

## Note structure & voice

- Substantive notes follow: `TL;DR` → `Key Findings` → `Details` →
  `Recommendations` → `Caveats`.
- **Voice:** research-backed and decisive. Cite sources with dates. Separate
  *verified facts* from *speculation/prediction*. Flag assumptions and caveats.
- Update `updated:` when you materially change a note.

## Directory map (where things live)

| Path | What | Who reads/writes it |
|---|---|---|
| Vault root + topical folders | The notes (the KB itself) | humans + any agent |
| `index.md` | Catalog of every note (link + one-line summary), the navigation backbone | read first; update on every note add/change |
| `log.md` | Append-only record of ingests/changes | append an entry per working session |
| `raw/` | **Immutable** source material (clippings, transcripts, exports) | read-only — never edit a raw source |
| `assets/` | Small images embedded in notes (diagrams, screenshots); tracked in git | Obsidian (default attachment folder) |
| `_local/` | **Gitignored** large/sensitive originals (PDFs, big images, datasets) — stay on this machine | local agents + Obsidian; never committed |
| `docs/knowledge/` | Compounded learnings (the compounding loop) | `kw-compound` writes; `knowledge-base-researcher` + `stale-knowledge-checker` read |
| `docs/solutions/` | Solved-problem / pattern write-ups | `past-work-researcher` reads |
| `plans/` | In-progress plans & brainstorms | `kw-plan` / `kw-work` write; `past-work-researcher` reads |
| `.agents/` | **Agent home (agnostic):** `vault-profile.md`, `skills/`, `agents/`, `scripts/` | all agents |
| `.claude/`, `.codex/` | Tool-specific config; `skills`/`agents` here are pointers to `.agents/` | Claude Code / Codex |
| `.obsidian/` | Obsidian config | Obsidian |

**Folders beginning with a dot (`.agents`, `.claude`, `.codex`, `.obsidian`) are
ignored by Obsidian** — so skills, agents, and config never pollute the knowledge
graph, search, or tag index. Keep all skill/agent machinery under dot-folders.

## Large files & external sources

The repo holds **markdown** (the notes). Large or binary or sensitive originals —
PDFs, big images, datasets, exports — **do not belong in git** (GitHub caps files at
100MB, bloats permanently on binaries, and Obsidian Git auto-commits everything). A
pre-commit size guard blocks files over ~25MB.

Instead, keep the *bytes* outside git and a small **reference note** in the vault
(in git) that captures the distilled knowledge plus a pointer to the original — the
same idea as `raw/`, but for things too big or private to commit:

- **Local & private** → drop the file in `_local/` (gitignored; stays on this
  machine). Obsidian and local agents can still read/embed it.
- **Shared, large, or needed on other devices** → put it in **Google Drive** (or
  similar) and link to it; agents read it via the Google Drive MCP.
- **Small images that are genuinely part of a note** (a diagram) → fine in git;
  they go in `assets/` (the default attachment folder).

A reference note should record: what the file is, a short summary / key points, where
the original lives (the `_local/` path or the Drive link), and the usual frontmatter.

## Operating rules (LLM-Wiki pattern, after Karpathy)

This KB is maintained like Karpathy's [LLM Wiki](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f):

1. **Orient first.** Before any non-trivial operation in a new session, read this
   file + `.agents/vault-profile.md` + `index.md` + recent `log.md` entries.
2. **Maintain the backbone.** When you add or materially change a note, update
   `index.md` (catalog entry) and append to `log.md`.
3. **Link generously, bidirectionally.** `[[wikilinks]]` for internal references,
   standard Markdown links for external. Every note links to ≥2 others; add the
   backlink on the other side.
4. **Raw is immutable.** Synthesize from `raw/`; never edit a source.
5. **Lint periodically.** Watch for contradictions, stale claims, orphan notes, and
   concepts lacking a note. The `stale-knowledge-checker` agent helps.
6. **Compound.** End a cycle by extracting reusable learnings to `docs/knowledge/`.

## Skills (portable across agents)

Curated **Agent Skills** (the open `SKILL.md` standard — read by Claude Code, Codex,
Copilot, Cursor, Gemini) are vendored into this repo so they work in every session,
including ephemeral cloud containers that don't auto-install them.

- **Index:** [`.agents/skills/INDEX.md`](.agents/skills/INDEX.md) lists every skill
  and when to use it. **Consult it to choose a skill.**
- **Canonical location:** `.agents/skills/`; `.claude/skills` and `.codex/skills`
  point to it.
- **Add a skill — vault-specific:** put your own sources in
  `.agents/skill-sources.local.json` (never overwritten by base updates), then run
  `.agents/scripts/sync-skills.sh`. The base's curated list lives in
  `.agents/skill-sources.json` (base-owned); the sync **merges both**.
- **Get base improvements:** run `.agents/scripts/update-base.sh` (or the
  `/update-base` skill). It's **git-native** — it fetches a `base` git remote and
  overlays only the base-owned engine paths (including the curated
  `skill-sources.json`), leaving your notes, `vault-profile.md`, and
  `skill-sources.local.json` untouched. Then run `sync-skills.sh`.
- Full mechanism: [`.agents/SKILLS.md`](.agents/SKILLS.md).

## Working in this vault: content vs engine

Two kinds of change flow through this repo, and they use **different paths**:

- **Content** — notes, written by a person in Obsidian *or* by an agent via the
  Obsidian MCP. These land in the **live vault working tree on `main`** and are
  synced automatically by Obsidian Git (commit-and-sync + pull-on-start). Nobody
  runs git by hand. This is the path for all everyday knowledge work.
- **Engine / structural** — the base layer: `AGENTS.md`, scripts, hooks,
  `skill-sources.json`, schema-wide refactors, anything `update-base` owns. Make
  these on a **branch and open a PR**, ideally from a **separate checkout/worktree**,
  not the live auto-syncing vault — otherwise Obsidian Git can sweep a half-applied
  engine change straight onto `main`.

Rule of thumb: *if a non-technical note-taker would never touch it, it's an engine
change → branch + PR.*

## For agents

- Navigate by frontmatter (`type`/`status`/`tags`) and `related` links; start from
  `index.md`. Read `.agents/vault-profile.md` for this vault's specifics.
- New notes go in the vault root (or a topical subfolder), always with frontmatter
  and `tags` including the vault's primary tag.
- This is a knowledge base, not a codebase: the deliverable is well-sourced,
  decisive, cross-linked Markdown.
