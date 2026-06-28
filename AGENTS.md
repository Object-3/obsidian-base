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

Like a fresh Obsidian vault, the base prescribes **no topical organization** — you get
the root and make whatever folders you like. The paths below aren't imposed filing;
each is either the **navigation backbone**, **workflow scaffolding** the agents create
as they need it, or a **mechanism** you never manage by hand. Anything not listed is
yours to organize freely.

| Path | What | Kind |
|---|---|---|
| Vault root + folders you create | The notes (the KB itself) — organize however you like | yours |
| `index.md` | Catalog of every note (link + one-line summary), the navigation backbone | backbone |
| `log.md` | Append-only record of ingests/changes | backbone |
| `assets/` | Where Obsidian drops pasted/embedded images, keeping them out of your note area. Auto-managed — you never touch it. | mechanism |
| `_local/` | **Gitignored** escape hatch for files too big or sensitive for git (PDFs, datasets, private originals). The pre-commit size guard points here. | mechanism |
| `raw/` | *Convention, created on demand:* immutable source material (clippings, transcripts, exports) you synthesize from and never edit | convention |
| `docs/knowledge/` | Compounded learnings (the compounding loop) | `kw-compound` writes; `knowledge-base-researcher` + `stale-knowledge-checker` read |
| `docs/solutions/` | Solved-problem / pattern write-ups | `past-work-researcher` reads |
| `plans/` | In-progress plans & brainstorms | `kw-plan` / `kw-work` write; `past-work-researcher` reads |
| `.agents/` | **Agent home (agnostic):** `vault-profile.md`, `skills/`, `agents/`, `scripts/` | engine |
| `.claude/`, `.codex/` | Tool-specific config; `skills`/`agents` here are pointers to `.agents/` | engine |
| `.obsidian/` | Obsidian config | engine |

**Folders beginning with a dot (`.agents`, `.claude`, `.codex`, `.obsidian`) are
ignored by Obsidian** — so skills, agents, and config never pollute the knowledge
graph, search, or tag index. Keep all skill/agent machinery under dot-folders.

**Topical folders (optional, grow-into).** Notes live in the vault root until a
single topic accumulates more than ~5–8 notes; then promote that topic to a
**single-level, lowercase, topic-named** folder (e.g. `private-equity/`,
`marketing/`). Folders are **coarse buckets only** — `tags`, `[[links]]`, and
`index.md` stay the primary organizing axes (a note lives in exactly one folder but
can carry many tags). Don't pre-create empty folders; promote at the threshold. Keep
folders one level deep.

## Large files & external sources

The repo holds **markdown** (the notes). Large, binary, or sensitive originals —
PDFs, big images, datasets, exports — **don't belong in git** (GitHub caps files at
100MB and bloats permanently on binaries, and Obsidian Git auto-commits everything).

You don't have to police this by hand. A **pre-commit size guard** blocks anything
over ~25MB and tells you what to do, and the fix it points to is the gitignored
**`_local/`** folder: drop the file there and it stays on your machine, never reaching
GitHub, while Obsidian and local agents can still read/embed it. For files you need on
other devices or want to share, put them in **Google Drive** (or similar) and link to
them; agents read them via the Google Drive MCP.

When a `_local/` (or Drive) file matters to the knowledge, it's worth leaving a small
**reference note** in the vault — what the file is, a few key points, and where the
original lives — so the KB "knows about" it without storing the bytes. (Same idea as
keeping immutable sources in `raw/`, just for things too big or private to commit.)

Small images that are genuinely part of a note are fine in git — Obsidian drops them
in `assets/` automatically.

## Operating rules (LLM-Wiki pattern, after Karpathy)

This KB is maintained like Karpathy's [LLM Wiki](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f):

1. **Orient first.** Before any non-trivial operation in a new session, read this
   file + `.agents/vault-profile.md` + `index.md` + recent `log.md` entries.
2. **Maintain the backbone.** When you add or materially change a note, update
   `index.md` (catalog entry) and append to `log.md`.
3. **Link generously, bidirectionally.** `[[wikilinks]]` for internal references,
   standard Markdown links for external. Every note links to ≥2 others; add the
   backlink on the other side.
4. **Sources are immutable.** When you keep source material (clippings, transcripts,
   exports), put it in `raw/` (create the folder on demand) and never edit it —
   synthesize into notes so claims stay traceable.
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
- New notes go in the vault root (or a topical subfolder — see **Topical folders**
  under the Directory map), always with frontmatter and `tags` including the vault's
  primary tag.
- This is a knowledge base, not a codebase: the deliverable is well-sourced,
  decisive, cross-linked Markdown.
