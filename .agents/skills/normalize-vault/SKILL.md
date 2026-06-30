---
name: normalize-vault
description: Bring an existing Obsidian-vault note up to this knowledge base's frontmatter + structure standard (the AGENTS.md contract), on the user's go-ahead. Use this whenever you open or are handed a vault note that isn't conformant — missing or partial YAML frontmatter, no TL;DR-to-Caveats structure, no [[links]], or missing the vault's primary tag — and it's worth keeping, or when the user says "normalize this note", "format this to our standard", "clean up this note", "make this fit the knowledge base", "add frontmatter", or "standardize these notes", or when AGENTS.md's normalize-on-contact rule fires and the user agrees. Also runs a deliberate whole-vault sweep (via lint-vault.sh) on request. Scope is structural/metadata conformance of existing vault notes — not authoring new notes, not prose/copy editing, and not docs/knowledge, docs/solutions, or plans/ (those carry their own schema). Never touches raw/ or _sensitive/ (or legacy _local/).
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
     deterministic list of notes that miss the frontmatter standard (it already applies
     the exclusions below). Then **show the user that list and confirm before editing.**
     The linter only checks frontmatter — structure, voice, and linking are your call.

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

7. **Maintain the backbone.** Add or refresh the note's entry in `index.md` (link +
   one-line summary) and append to `log.md`
   (`## [YYYY-MM-DD] normalize | <what changed + why>`).

8. **Report.** Summarize what changed. For a sweep, list each note touched (and any
   you skipped, with why).

## What NOT to touch

- `raw/` — immutable source material; synthesize from it, never reformat it.
- `_sensitive/` (and legacy `_local/`), `assets/`, and dot-folders (`.agents`, `.claude`, `.codex`, `.obsidian`).
- Engine / meta markdown: `AGENTS.md`, `CLAUDE.md`, `README.md`, `SETUP.md`, `llms.txt`.
- `docs/knowledge/`, `docs/solutions/`, `plans/` — these carry their **own**
  frontmatter schema maintained by the `kw-*` skills; don't force the note schema onto
  them.
- Non-note files such as Obsidian Bases (`*.base`).

## Notes

- Hand-authored, repo-local skill — not vendored, so `sync-skills.sh` won't overwrite
  it; `update-base` propagates it to forks.
- If a required field is genuinely unknown, leave it out or ask — a wrong-but-present
  value is worse than an honest gap.
