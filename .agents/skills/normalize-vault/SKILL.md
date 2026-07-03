---
name: normalize-vault
description: Bring an existing Obsidian-vault note up to this knowledge base's frontmatter + structure standard (the AGENTS.md contract), on the user's go-ahead. Use this whenever you open or are handed a vault note that isn't conformant — missing or partial YAML frontmatter, no TL;DR-to-Caveats structure, no [[links]], missing the vault's primary tag, or a non-kebab-case filename (spaces/capitals/punctuation like "Puma Peak — Deal Strategy.md") — and it's worth keeping, or when the user says "normalize this note", "format this to our standard", "clean up this note", "make this fit the knowledge base", "add frontmatter", "standardize these notes", "rename this note to our convention", "fix these file names", or "kebab-case these files", or when AGENTS.md's normalize-on-contact rule fires and the user agrees. Also runs a deliberate whole-vault sweep (via lint-vault.sh) on request. Scope is structural/metadata conformance of existing vault notes — not authoring new notes, not prose/copy editing. It never forces the full note standard onto docs/knowledge, docs/solutions, or plans/ (those carry their own schema); the one exception is a metadata-only graph-linking pass over docs/knowledge/ that adds the vault's primary tag + a [[link]] so kw-compound learnings surface in Obsidian's graph and tag views (also triggers on "link my knowledge notes into the graph" or "back-fill primary tags on docs/knowledge"). Never touches raw/ or _sensitive/ (or legacy _local/).
---

# Normalize a note to the vault standard

Bring a note (or, when asked, a batch of notes) up to this vault's standard — the
`AGENTS.md` **Frontmatter** + **Note structure & voice** contract — preserving the
author's meaning. This is the "run everything" executor that the
*normalize-on-contact* operating rule points at.

**Consent first.** The operating rule makes the *offer*; this skill runs the work
**after a yes**. If you invoke it directly for a sweep, propose the list of
non-conforming notes and get a go-ahead before editing anything. Never silently
mass-rewrite, and don't bother normalizing throwaway scratch that isn't worth keeping.

## Steps

1. **Orient — read the standard you're normalizing *to*.** Skim `AGENTS.md`
   (Frontmatter + Note structure & voice) and `.agents/vault-profile.md` for this
   vault's **primary tag** and house conventions. That contract is the spec.

2. **Scope the target.**
   - *Single note* — the file you were pointed at, or the one you just encountered and
     got a yes on.
   - *Sweep* ("normalize the whole vault") — run `.agents/scripts/lint-vault.sh` for a
     deterministic list. It reports **note-standard misses** in the note area (your
     normalization target — the exclusions below already apply there) plus **invalid-YAML**
     frontmatter anywhere it matters, *including* the own-schema dirs under *What NOT to
     touch* (`docs/…`, `plans/`, the backbone) — broken YAML renders as raw text there
     too. Then **show the user that list and confirm before editing.** The linter only
     checks frontmatter — structure, voice, and linking are your call.

3. **Confirm it's in scope.** If the file is really source material (a clipping,
   transcript, export), don't reformat it — suggest moving it to `raw/` instead, and
   synthesize a note from it. Skip anything under *What NOT to touch*.

4. **Normalize the frontmatter** (YAML at line 1):
   - `title` — human-readable; from the existing H1 or the filename.
   - `type` — infer from content: `decision-record | research | playbook | scratch | index`.
   - `status` — `active | draft | reference | archived` (fresh dumps are usually `draft`).
   - `tags` — lowercase; **always include the vault's primary tag** plus topical tags.
   - `created` — keep if present; else infer from git
     (`git log --diff-filter=A --format=%ad --date=short -- "<file>" | tail -1`) or the
     file date; else ask. Don't invent a date.
   - `updated` — today.
   - Optional: `confidence`, `sources`, `related`.

5. **Normalize the body** (preserve meaning — **never invent facts, sources, or dates**):
   - Substantive notes → `TL;DR` → `Key Findings` → `Details` → `Recommendations` →
     `Caveats`.
   - Voice: research-backed and decisive; cite sources with dates; separate *verified
     facts* from *speculation*; flag assumptions and caveats.
   - A short scratch note doesn't need the full skeleton — clean frontmatter and a
     clear heading is enough.

6. **Link it in.** Add ≥2 `[[wikilinks]]` to genuinely related notes, and **add the
   backlink on the other side**.

7. **Rename to a kebab-case filename (if it isn't one).** Filenames must be kebab-case —
   lowercase, hyphens, no spaces/capitals/punctuation (`AGENTS.md` → **File naming**).
   This applies to the **note area** (root + topical folders — the same set the linter's
   filename check covers); `docs/…` and `plans/` are named by their owning skills, and
   `raw/`/`_sensitive/` are never renamed. When a name has spaces, capitals, or punctuation
   (`Puma Peak — Deal Strategy.md`), rename it **without breaking inbound links**:
   - **Pick a short slug** from `title:` — lowercase, hyphens, ≤ ~5–6 words
     (`puma-peak-deal-strategy.md`). `lint-vault.sh` prints a suggestion you can shorten.
   - **Bridge old links first.** Add the note's *current* human name to its frontmatter
     `aliases:` (e.g. `aliases: ["Puma Peak — Deal Strategy"]`) **before** moving it — so
     every existing `[[Puma Peak — Deal Strategy]]` still resolves in Obsidian after the
     rename, with no inbound rewrite needed.
   - **Move it.** `git mv "Puma Peak — Deal Strategy.md" puma-peak-deal-strategy.md` on
     your branch (or a live-vault move via the Obsidian MCP when the connector supports it
     and you're working live by explicit request). Never leave a half-rename.
   - **Repoint the machine-readable references** that don't ride the alias: this note's
     `index.md` / `hot.md` entries → `[[puma-peak-deal-strategy]]` (pipe for display if you
     like — `[[puma-peak-deal-strategy|Puma Peak — Deal Strategy]]`), and any `related:`
     frontmatter in *other* notes that named the old file.
   - **One at a time.** On a batch, rename note-by-note and re-run `lint-vault.sh` to watch
     the offender list shrink and confirm nothing new broke.

8. **Maintain the backbone.** Add or refresh the note's entry in `index.md` (link +
   one-line summary) and append to `log.md`
   (`## [YYYY-MM-DD] normalize | <what changed + why>`).

9. **Report.** Summarize what changed. For a sweep, list each note touched (and any
   you skipped, with why).

## What NOT to touch

- `raw/` — immutable source material; synthesize from it, never reformat it.
- `_sensitive/` (and legacy `_local/`), `assets/`, and dot-folders (`.agents`, `.claude`, `.codex`, `.obsidian`).
- Engine / meta markdown: `AGENTS.md`, `CLAUDE.md`, `README.md`, `SETUP.md`, `llms.txt`.
- Backbone files: `index.md`, `log.md`, `hot.md` — these are the navigation/history/recent-context
  spine (maintained by the operating rules and `/vault-dream`), not content notes; don't force the note schema onto them.
- `docs/knowledge/`, `docs/solutions/`, `plans/` — these carry their **own**
  frontmatter schema maintained by the `kw-*`/`ce-*` skills; **don't force the note schema
  onto them.** Two narrow, schema-preserving exceptions: (1) if `lint-vault.sh` flags one as
  *invalid YAML*, quoting the offending value is a safe fix — it restores parseability without
  touching their schema; and (2) the **Graph-linking pass** below may add the primary tag +
  a `[[link]]` to `docs/knowledge/` notes **only**. `docs/solutions/` and `plans/` stay fully
  hands-off.
- Non-note files such as Obsidian Bases (`*.base`).

## Graph-linking pass for `docs/knowledge/` (metadata-only — never the full standard)

`docs/knowledge/` notes are written by `/kw:compound`, which uses its **own** schema
(`type: insight|playbook|correction|pattern`, `confidence`, `source`) and does **not**
stamp the vault's primary tag or any `[[links]]`. That leaves those learnings fully findable
by *search* (grep / semantic) but light in Obsidian's **graph and tag views** — a real
discoverability seam. This one narrow pass closes it, and it is the **only** thing normalize
does inside `docs/knowledge/`.

**Finding candidates:** `lint-vault.sh` won't surface these (under `docs/` it checks only
YAML parseability, not tags/links), so identify them directly — `docs/knowledge/` notes whose
`tags:` lacks the primary tag, or that contain no `[[wikilink]]`.

Run it **only** on `docs/knowledge/` (never `docs/solutions/` or `plans/`), on the same
consent-first basis, and touch **only** these two things:

- **Primary tag** — if the note's `tags:` is missing the vault's primary tag, add it to the
  existing list (inline `[...]` or block form). **Keep the existing keyword tags as-is** —
  don't reorder, dedupe, or drop them.
- **Wikilinks** — add ≥1 `[[wikilink]]` to a **genuinely** related note that **actually
  exists** (another `docs/knowledge/` learning or a vault note). Obsidian surfaces the
  backlink automatically, so **don't edit the target** — this keeps the pass from rewriting
  any other (possibly human-authored) note. Never invent a link to make the count.

**Never, in this pass:** change `type`/`confidence`/`source`, add `title`/`status`/`updated`,
or restructure the body into the `TL;DR…Caveats` skeleton — any of those would fight the kw
schema and is out of scope here. (Invalid *YAML* is the separate, always-safe quoting fix from
*What NOT to touch*.)

The note is already catalogued in `index.md` by `/kw:compound`, so no new catalog entry is
needed; on a sweep, append one `log.md` line summarizing the batch
(`## [YYYY-MM-DD] normalize | graph-linked N docs/knowledge notes (primary tag + links)`).

## Notes

- Hand-authored, repo-local skill — not vendored, so `sync-skills.sh` won't overwrite
  it; `update-base` propagates it to forks.
- If a required field is genuinely unknown, leave it out or ask — a wrong-but-present
  value is worse than an honest gap.
