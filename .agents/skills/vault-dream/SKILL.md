---
name: vault-dream
description: Consolidate this Obsidian knowledge base and fold durable learnings from recent agent sessions into it — one "dream" pass that reads session transcripts since a watermark, captures reusable learnings into docs/knowledge/, dedupes and re-indexes the vault, and hands the changeset off as a reviewable branch + pull request (never a write to main, never an auto-merge). Use when the user says "run the dream", "run /vault-dream", "consolidate the vault", "dream", "fold my sessions into the KB", "clean up and re-index the vault", or "compound my recent sessions", or when the SessionStart nudge offers it. Runs only inside the vault repo itself — never when merely consuming the vault over the Obsidian MCP from another project. A thin conductor over the existing engine (dream-scan.sh, kw-compound, the researcher and stale-knowledge-checker agents, lint-vault.sh, normalize-vault); it de-identifies before writing and never deletes human-authored prose.
---

# Dream: self-improving consolidation + session-learning for the vault

One triggered pass that does what a human maintainer would do between work sessions:
**capture** durable learnings from the agent sessions you just ran, **consolidate** the
vault (dedupe, resolve contradictions, re-index), and hand the result off as a
**reviewable branch + pull request (PR)** — never a silent write to `main`.

This skill is a **thin conductor**. It does not reimplement extraction, learning-capture,
contradiction-checking, linting, or normalization — it *composes* the pieces this repo
already ships. Where a step says "delegate to X," do exactly that.

**Consent first.** The SessionStart nudge only *offers* the dream; running this skill is
the acceptance. For an interactive/manual run, **preview the proposed changeset and get a
go-ahead before writing anything** (the `/normalize-vault` "propose, then act on yes"
posture). The PR itself is the async review gate — you never merge it.

**Scope guard — vault repo only.** Run only when the working directory *is* this vault
repo (its `AGENTS.md` + `.agents/vault-profile.md` are present). If you reached the vault
over the Obsidian Model Context Protocol (MCP) from another project, **do not run the
dream** — that is read/consume access, not maintenance access.

---

## The change vocabulary (used throughout)

Every proposed change is exactly one of:

- **ADD** — a new note (usually a captured learning in `docs/knowledge/`).
- **UPDATE** — edit an existing note (merge a duplicate, fix a stale claim, add a link).
- **DELETE** — remove a note. **Restricted to agent-authored notes only.** A
  human-authored note is *never* deleted; a contradiction in human prose becomes a
  `> [!contradiction]` callout for a human to resolve (see below).
- **NOOP** — considered and deliberately not acted on (e.g. project-only trivia rejected
  by the generalizability gate). Record it so the reviewer sees what you chose *not* to do.

**Every ADD/UPDATE/DELETE/NOOP carries a one-line rationale + provenance** — which session
or note drove it (e.g. `from session 2026-07-01/…jsonl` or `merges [[note-a]] into
[[note-b]]`). The PR (or the `DREAMS.md` fallback) must be reviewable without archaeology.

---

## Phases

### 1. Orient

Read, in order: `.agents/vault-profile.md` (primary tag, `dream_session_scope`, vault
conventions), `index.md` (the catalog), recent `log.md` entries, `hot.md` (recent-context
cache), and `.agents/dream-state` (the watermark — the ISO-8601 timestamp of the last
consolidated run). This is the spec for everything below.

If `.agents/dream-state` is absent (a fork that predates this feature — `update-base` never
overlays the per-vault watermark), create it seeded to *now* and proceed: the first dream
then consolidates sessions going forward rather than scanning the entire history. **Write
the timestamp in exactly the form the reader parses** — `date -u +%Y-%m-%dT%H:%M:%SZ` (a
trailing `Z`, no offset, no fractional seconds) — so the scanner/nudge never silently
desync from a different ISO-8601 variant.

### 2. Gather signal

Find the agent sessions recorded since the watermark, then read them cheaply:

- **Discover (fast, repo-scoped):** run `.agents/scripts/dream-scan.sh` to list the Claude
  Code session transcripts newer than the watermark for the configured scope
  (`this-checkout` or `all-worktrees`). `--count` gives just the number.
- **Read (portable default):** for each transcript, `.agents/scripts/dream-scan.sh --extract
  <file>` prints a compact digest (user + assistant text only; tool calls, tool results, and
  reasoning stripped) so you harvest learnings **without loading multi-megabyte files into
  context**. This works everywhere — forks, cloud containers, any agent.
- **Read (richer, when available):** if the `compound-engineering` plugin's session
  primitives are installed, prefer **`ce-session-inventory`** (enumerate across Claude Code,
  Codex, and Cursor — it CWD-filters Codex and parses Cursor, breadth the portable path
  skips) + **`ce-session-extract`** (`skeleton`/`errors` mode). Treat them as an optional
  enhancement, not a hard dependency — they are *not* vendored into this repo (they ship
  only in the built plugin), so never assume their presence.

From the digests, harvest **durable candidates**: explicit user corrections ("no, do it
this way"), explicit saves ("remember this"), decisions reached, recurring themes across
sessions, and solved problems worth reusing. Ignore one-off chatter and anything specific
to a single unrelated repo.

### 3. Capture (write learnings — delegated)

For each durable candidate:

1. **Generalizability gate.** Would this help *future, different* work in this vault? If it
   is project-only trivia (a one-repo fix, a transient path, a local config), mark it
   **NOOP** and move on. Only reusable domain/strategy/workflow learnings pass.
2. **Search before save.** Dispatch the **`knowledge-base-researcher`** agent (over
   `docs/knowledge/`) and, when the candidate is work/decision-shaped, the
   **`past-work-researcher`** agent (over `plans/` + `docs/solutions/`) to check whether the
   learning already exists. If it does → **UPDATE** that note (sharpen, add a source, add a
   link); if not → **ADD**.
3. **De-identify, then write.** Strip secrets, credentials, personal/third-party detail
   before anything touches the tracked vault (see *Privacy* below). Then **delegate the
   write to `/kw:compound`** — it owns `docs/knowledge/` frontmatter, search-before-save
   dedupe, and the `index.md` + `log.md` backbone updates. Do not hand-roll the note schema.
   Note that `/kw:compound`'s schema does **not** stamp the vault's primary tag or `[[links]]`;
   the **graph-linking pass** in step 4 back-fills those so the new learning joins the graph.

> **Privacy (self-enforced — do not rely on the pre-commit hook alone; the Obsidian Git
> plugin may use a bundled git that skips native hooks):** learnings with a secret, API
> key, credential, or third-party-confidential detail are either **de-identified** (no name,
> owner, verbatim figures) before landing in a tracked note, or **routed to `_sensitive/`**
> with `classification: confidential` in the frontmatter (gitignored, still first-class in
> Obsidian). The `**/*.private.md` gitignore and the pre-commit confidential guard are
> backstops, not the primary control.

### 4. Consolidate (multi-category audit)

Beyond `lint-vault.sh`'s frontmatter + filename checks, run the **judgment-based audit
only an LLM/agent can do**, and express each finding as ADD/UPDATE/DELETE/NOOP:

- **Contradictions / superseded claims** — dispatch the **`stale-knowledge-checker`** agent.
  In an *agent-authored* note, UPDATE (or DELETE if fully superseded). In a *human-authored*
  note, **never edit or delete** — insert a `> [!contradiction]` callout naming both claims
  and their sources, and leave it for the human.
- **Duplicates / overlaps** — merge into the canonical note (UPDATE the survivor, DELETE the
  agent-authored duplicate, repoint links).
- **Orphans** (no inbound links), **dead/broken `[[wikilinks]]`**, **stale claims**, and
  **missing concept pages / cross-references** — fix by adding links/backlinks or flagging a
  gap. Use **`/normalize-vault`** for any structural/frontmatter fixes to existing notes;
  don't hand-roll them. This includes **`docs/knowledge/` learnings that `/kw:compound` left
  without the vault's primary tag or any `[[link]]`** — they read as graph-orphans even though
  search finds them; run `/normalize-vault`'s **graph-linking pass** to back-fill the primary
  tag + ≥1 link, without otherwise touching their kw schema.

`lint-vault.sh` covers the deterministic layer — frontmatter conformance **and** non-kebab
filenames (`/normalize-vault` renames the offenders safely, links intact — see its rename
step); this phase is the semantic layer on top.

### 5. Prune & re-index (backbone)

- Update `index.md` (catalog entries for every ADD/UPDATE).
- **Refresh `hot.md`** (create it if absent) — the ~500-word recent-context cache agents
  read first: distill this run's additions, decisions, and open threads. Keep it short; it
  is a cache, not an archive.
- **Roll up / archive stale `log.md` entries** so the append-only log doesn't grow
  unbounded (summarize old runs into a rolled-up block), then append this run's line:
  `## [YYYY-MM-DD] dream | <one-line summary of the changeset>`.
- **Bump `.agents/dream-state`** to now — `date -u +%Y-%m-%dT%H:%M:%SZ` (the exact form the
  reader parses; see the seeding note in Phase 1) — *as part of this changeset*, so the
  watermark advances only when the PR is merged/applied. An abandoned PR leaves it untouched
  and those sessions are reconsidered next run.

### 6. Self-verify (before anyone sees it)

Audit the proposed changeset and fix or annotate any failure before opening the PR:

- **Every new `[[wikilink]]` resolves** to a real note (guard against hallucinated links).
- **No human-authored prose deleted or rewritten** — such changes must be `[!contradiction]`
  callouts instead.
- **Nothing confidential in a tracked note** — re-scan for secrets/credentials/third-party
  detail with `git grep --untracked` (or scan *after* `git add`) so **brand-new, untracked**
  notes are included — a bare `git diff`/`git grep` sees only *tracked* files and silently skips
  a just-written note, so it would pass as "clean". `--untracked` honors `.gitignore`, so it
  won't false-positive on scratch like `.context/`.
- **`.agents/scripts/lint-vault.sh` is clean** on every newly written/edited note.

If a check fails, fix it (repair the link, convert the deletion to a callout, de-identify)
and re-verify. Do not open the PR on a failing check.

### 7. Isolate, PR & hand off

Never write to `main`; never auto-merge.

- **git + PR tooling available:** work on a dedicated branch (e.g. `dream/YYYY-MM-DD`),
  commit the changeset, push, and open a PR with a **plain-language description** in which
  **every change carries its one-line rationale + provenance**. Surface the **PR URL** and
  recommend the user review it before merging.
- **git but no PR tooling (`gh`):** commit on the branch and push (or leave it local); tell
  the user the branch name and that they should open/merge the PR themselves. Still never
  touch `main`.
- **No git at all (Obsidian-only / non-technical):** write a **`DREAMS.md`** review note at
  the vault root listing the annotated ADD/UPDATE/DELETE/NOOP changes with rationale +
  provenance, and **apply nothing**. It is a proposal for a human to act on.
- **Non-technical handoff:** additionally narrate the changes in plain language in chat, and
  **offer to merge only on explicit confirmation** — do not merge on your own.

---

## What this composes (don't reinvent)

| Step | Delegate to |
|---|---|
| Discover sessions since watermark | `.agents/scripts/dream-scan.sh` |
| Read one transcript (portable) | `.agents/scripts/dream-scan.sh --extract <file>` |
| Read transcripts cross-agent (optional) | `ce-session-inventory` + `ce-session-extract` — only if the compound-engineering plugin is installed (not vendored) |
| Write a learning note | `/kw:compound` (owns `docs/knowledge/` schema + dedupe + backbone) |
| Dedupe before save | `knowledge-base-researcher`, `past-work-researcher` agents |
| Find contradictions / superseded | `stale-knowledge-checker` agent |
| Frontmatter lint | `.agents/scripts/lint-vault.sh` |
| Structural / frontmatter fixes | `/normalize-vault` |

## What NOT to touch

- **`main`** — the dream only ever produces a branch/PR (or `DREAMS.md`). The PR is the only
  path to `main`.
- **Human-authored prose** — never deleted or rewritten; contradictions become
  `> [!contradiction]` callouts. DELETE is for agent-authored notes only.
- **`raw/`** — immutable source material; synthesize from it, never rewrite it.
- **`_sensitive/`** (and legacy `_local/`) — write confidential learnings there, but never
  reformat or delete existing sensitive notes.
- **`assets/`, dot-folders** (`.agents`, `.claude`, `.codex`, `.obsidian`), and engine/meta
  markdown (`AGENTS.md`, `CLAUDE.md`, `README.md`, `SETUP.md`, `llms.txt`) — not content.

## Notes

- **Portable + tool-agnostic.** This is plain Markdown any agent can run (Claude Code,
  Codex, Cursor, Copilot, Gemini). The SessionStart nudge is the only Claude-Code-specific
  piece; other agents invoke `/vault-dream` manually (a manual/cron fallback is documented
  in `AGENTS.md`).
- **Hand-authored, repo-local skill** — not vendored, so `sync-skills.sh` won't overwrite
  it; `update-base` propagates it to forks.
- **Single writer.** One dream at a time — don't run parallel consolidation passes over the
  same vault (they would race on `index.md` / `hot.md` / the watermark).
