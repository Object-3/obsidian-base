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
title:   "Human-readable title"          # the FILENAME is a kebab-case slug of this — see "File naming"
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
- **Spell out acronyms — don't assume the reader knows them.** Expand every
  acronym, abbreviation, or initialism on **first use** in a note: write the full
  term with the short form in parentheses after it — e.g. "conversion rate
  optimization (CRO)", "jobs to be done (JTBD)" — then use the short form for the
  rest of the note. This applies to prose; lowercase `tags` may stay abbreviated.
  The same rule holds when an agent reports back in conversation: lead with plain
  language, gloss the shorthand once.
- Update `updated:` when you materially change a note.

## File naming

**Every note's filename is a kebab-case slug** — lowercase ASCII letters and digits,
words joined by single hyphens, ending in `.md` (e.g. `puma-peak-deal-strategy.md`,
`hipaa-compliant-google-ads.md`). **No** spaces, capitals, or punctuation
(`& — – ( ) , : / ' "` …). This holds **everywhere** — vault root and topical folders
alike — the same convention `docs/knowledge/` and `plans/` already follow, so the whole
vault reads one way.

Why the filename isn't the title: a note's filename is also a **git path, a URL, an
`llms.txt` entry, and a shell argument**. Spaces and `&`/`—`/`(` break links and
tooling, need escaping, and resolve differently on case-sensitive (Linux/CI) vs
case-insensitive (macOS) filesystems. A kebab slug is portable everywhere; a
Title-Case-with-spaces filename is a latent bug.

- **The human title lives in `title:` frontmatter** (and the H1) — *not* the filename.
  The filename is a **short slug of the title**: aim for ≤ ~5–6 words and trim filler.
  `title: "Outpatient Behavioral-Health Roll-Ups — Market Multiples & Risks"` →
  `outpatient-behavioral-health-roll-ups.md`.
- **Wikilinks target the slug** — `[[puma-peak-deal-strategy]]`. For a readable label,
  pipe it (`[[puma-peak-deal-strategy|Puma Peak — Deal Strategy]]`) or add
  `aliases: ["Puma Peak — Deal Strategy"]` to the note so `[[Puma Peak — Deal Strategy]]`
  resolves and displays nicely too. (The `aliases` bridge is also how a rename keeps
  old links working — see below.)
- **Enforced.** `.agents/scripts/lint-vault.sh` flags any non-kebab note filename, and
  **`/normalize-vault`** offers to rename an offender safely (kebab `git mv` + an
  `aliases:` bridge so existing `[[links]]` keep resolving + `index.md`/`log.md` fixups).
  Reserved backbone/engine files (`index.md`, `log.md`, `hot.md`, `AGENTS.md`,
  `README.md`, …) keep their fixed names — they're exempt.

## Directory map (where things live)

Like a fresh Obsidian vault, the base prescribes **no topical organization** — you get
the root and make whatever folders you like. The paths below aren't imposed filing;
each is either the **navigation backbone**, **workflow scaffolding** the agents create
as they need it, or a **mechanism** you never manage by hand. Anything not listed is
yours to organize freely — see the **Topical folders** convention below for how folders
grow in as the vault expands.

| Path | What | Kind |
|---|---|---|
| Vault root + folders you create | The notes (the KB itself) — organize however you like | yours |
| `index.md` | Catalog of every note (link + one-line summary), the navigation backbone | backbone |
| `log.md` | Append-only record of ingests/changes | backbone |
| `hot.md` | ~500-word recent-context cache agents read first (what changed / active context); refreshed by `/vault-dream`. Sits above `index.md`. | backbone |
| `assets/` | Where Obsidian drops pasted/embedded images, keeping them out of your note area. Auto-managed — you never touch it. | mechanism |
| `_sensitive/` | **Gitignored** Sensitive plane: confidential notes + large/sensitive originals (PDFs, datasets) kept off git but first-class in Obsidian. Optionally cloud-backed for durability via `/setup-sensitive-plane`. The pre-commit size + confidential guards point here. (Pre-rename name: `_local/`, still gitignored for back-compat.) | mechanism |
| `raw/` | *Convention, created on demand:* immutable source material (clippings, transcripts, exports) you synthesize from and never edit | convention |
| `docs/knowledge/` | Compounded learnings (the compounding loop) | `kw-compound` writes; `knowledge-base-researcher` + `stale-knowledge-checker` read |
| `docs/solutions/` | Solved-problem / pattern write-ups | `past-work-researcher` reads |
| `plans/` | In-progress plans & brainstorms | `kw-plan` / `kw-work` write; `past-work-researcher` reads |
| `.agents/` | **Agent home (agnostic):** `vault-profile.md`, `skills/`, `agents/`, `scripts/` | engine |
| `.agents/dream-state` | Committed watermark (ISO-8601 timestamp) of the last `/vault-dream` run; advances only when the dream's PR is merged. Per-vault state — seeded by `init-vault.sh`, not overlaid by `update-base`. | mechanism |
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
**`_sensitive/`** folder: drop the file there and it stays on your machine, never
reaching GitHub, while Obsidian and local agents can still read/embed it. For files you
need on other devices or want to share, put them in **Google Drive** (or similar) and
link to them; agents read them via the Google Drive MCP.

When a `_sensitive/` (or Drive) file matters to the knowledge, it's worth leaving a small
**reference note** in the vault — what the file is, a few key points, and where the
original lives — so the KB "knows about" it without storing the bytes. (Same idea as
keeping immutable sources in `raw/`, just for things too big or private to commit.)

Small images that are genuinely part of a note are fine in git — Obsidian drops them
in `assets/` automatically.

## Confidential & third-party material (what goes where)

Some material can't go in git **at all** — NDA-bound documents, third-party financials
or personal/client records, a counterparty's confidential decks. The governing line is
the usual NDA one: **no disclosure to a third party** — and a synced git host *is* a third
party (a private repo can be made public, shared, or reached by integrations). Sort it into
three buckets — **Shareable → Sensitive → Original**, in rising order of sensitivity:

- **Shareable** → the tracked vault. Strategy-level synthesis with **no**
  third-party-confidential detail. For third-party material, **de-identify** (no name,
  owner, or verbatim figures/records); often there's no per-document Shareable note at all.
- **Sensitive** → `_sensitive/` (gitignored, but still a first-class Obsidian note
  locally). The candid / number-heavy synthesis. When you're on a branch, write these
  **through the Obsidian MCP into the live vault** — git can't carry `_sensitive/`, but the
  MCP lands them where they're indexed and gitignored. Tag `classification:
  confidential-local-only`.
- **Original** → Google Drive (shareable / automatable) or `_sensitive/`. Never committed.

**Keep links intact across planes** with one rule: *links point up the sensitivity
gradient (shareable → sensitive → original) freely; references down are optional, labeled,
and never load-bearing.* A Shareable note's `related:` lists only other Shareable notes
(always resolves); Sensitive notes and Originals link up to Shareable; the one downward
pointer is a labeled callout that reads as intentional when the local note is absent.
Catalog Sensitive notes in a gitignored **`_sensitive/_index.md`** (the local-plane counterpart
to `index.md`); keep `index.md` / `log.md` de-identified.

Two machine backstops so this doesn't depend on memory: **`**/*.private.md`** is
gitignored everywhere, and the **pre-commit guard** blocks committing a `classification:
confidential…` note outside `_sensitive/`. The **`/ingest-pdf`** skill runs this whole workflow.

**Scan before you commit — include untracked files, not a bare `git diff`.** The interactive
de-identification check you run *before* staging must cover **brand-new, still-untracked notes**,
which a **bare `git diff` or bare `git grep` silently skips** (both look only at *tracked* content) —
so a just-written note still carrying a confidential name reports as "clean" and slips into the
commit. Use `git grep --untracked`: it scans tracked **and** untracked files while honoring
`.gitignore` (so it skips `_sensitive/` and scratch like `.context/` for free) —
`git grep -in --untracked -e "<name>" -e "<owner>" -- . ':(exclude)_sensitive' ':(exclude)_local'`
(use the long-form `:(exclude)…`; the short `:!`/`:^` form chokes on the leading `_`). (Outside a git
repo, fall back to a plain working-tree `grep -rin -e "<name>" -e "<owner>" .`, excluding any
gitignored scratch yourself; or just run the scan *after* `git add`, so `git diff --cached` sees new
files.) The pre-commit guard above is unaffected (it scans *staged* content once you've `git add`-ed) —
but it only flags `classification:`-tagged notes, not a stray codename in an otherwise-shareable note,
which is exactly what this pre-stage scan is for.

### Where the Sensitive plane lives (durability & multi-device)

By default `_sensitive/` lives on **one machine**, unbacked — lose the disk, lose the
notes, and they're not on your other devices. Fix that **without** putting them in git
or breaking Obsidian: back `_sensitive/` with an **org-tenant cloud-synced folder**.
Obsidian computes the graph / search / backlinks from on-disk files, so a cloud-synced
folder works **fully** as long as files are **materialized locally** (not online-only
placeholders). Set it up with the **`/setup-sensitive-plane`** skill.

**Proven-safe config (non-negotiable):**
1. **Pin files local** — disable OneDrive "Files On-Demand" / iCloud "Optimize Storage" /
   Drive offline-only for this subtree ("Always keep on this device"). Dehydrated
   placeholders are what produce **0-byte stub files** that Obsidian mis-reads or overwrites.
2. **One sync engine per path** — only the cloud client touches `_sensitive/`. Never also
   run Obsidian Sync or Obsidian-Git over it (the classic two-writer race).
3. **Never let the cloud client touch `.obsidian/`** — the most collision-prone path; it
   stays in git, outside the synced subtree.
4. **Sync only the `_sensitive/` subtree**, not the whole vault.
5. **Agents read via the provider API** (service account / app-only), not by reading/writing
   through the sync client.

**Provider — org tenant only.** Use **Microsoft 365 / OneDrive** or **Google Workspace /
Drive** on an **organization tenant** with a DPA/BAA in place; headless agents read via
Graph app-only (`Files.Read.All`) or a Google service account respectively. **Never
iCloud** (no BAA, no third-party file API), **never Obsidian Sync** (no SOC 2 / BAA —
fine for personal knowledge, not firm-confidential), and **never a personal account** for
NDA-bound material.

**One-line rule:** *Sensitive plane → org-tenant cloud-sync folder, pinned local, one
sync engine, agents read via the provider API. Never iCloud, never Obsidian Sync, never a
personal account for NDA'd material.*

**How agents discover the Sensitive plane (by access context).** Git is never an
ingress — `_sensitive/` is gitignored — so what an agent can see depends on *where it runs*:

| Where the agent runs | Sees `_sensitive/`? | Discovery path |
|---|---|---|
| Same machine (file tools, or Obsidian + MCP on localhost) | **Yes** — ordinary on-disk files | list / grep / read; Obsidian search + backlinks |
| Fresh clone / cloud container / CI | **No** — absent by design | only the de-identified `index.md` + the `> [!lock]` companion callouts |
| Remote / headless with cloud creds | **Yes**, if wired | the provider API on the backing folder (its ACL is the security boundary) |

So an agent shouldn't trust git alone to know the plane exists. The signposts are: the
**`> [!lock] Local-only companion`** callout in a Shareable note (announces a Sensitive
companion exists), **`_sensitive/_index.md`** (the local catalog), and the **Sensitive
plane backing store** block in `.agents/vault-profile.md` (records provider / mechanism /
how a headless agent reads it — no secrets, since vault-profile is tracked in git).

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
   concepts lacking a note — the `stale-knowledge-checker` agent helps, and
   `.agents/scripts/lint-vault.sh` flags notes that miss the frontmatter standard.
6. **Normalize useful notes on contact (ask first).** When you happen to open a note
   that doesn't meet the frontmatter/structure standard above and you judge it
   genuinely worth keeping, **offer** to bring it up to standard — don't silently
   rewrite it, and don't bother for throwaway scratch. On a yes, run the full
   normalization (frontmatter → `TL;DR … Caveats` structure → ≥2 `[[links]]` +
   backlinks → `index.md` + `log.md`); the `/normalize-vault` skill does all of it.
   Never reformat `raw/` (immutable) or `_sensitive/`; if you can't ask (non-interactive
   run), just flag it rather than changing it.
7. **Compound.** End a cycle by extracting reusable learnings to `docs/knowledge/`.
8. **Dream (consolidate periodically).** Rules 5–7 are the maintenance loop; the
   **`/vault-dream`** skill *runs that loop on a cadence* and adds session-learning capture.
   One triggered pass reads your agent session transcripts since a watermark, folds durable
   learnings into `docs/knowledge/` (delegating to `kw-compound`), consolidates the vault
   (dedupe, contradictions, orphans, dead links, re-index — via `stale-knowledge-checker` +
   `lint-vault.sh` + `/normalize-vault`), refreshes `hot.md`, and hands the whole changeset
   off as a **reviewable branch + pull request (PR)** — never a write to `main`. See *The
   dream* below.

### The dream (self-improving consolidation) — how it surfaces & its rails

- **Trigger (self-surfacing, not a daemon).** A second `SessionStart` hook
  (`.claude/hooks/dream-if-stale.sh`) prints a one-line nudge into the session **only** when
  it has been **≥24 hours since the last dream AND ≥5 new sessions** have accumulated.
  Otherwise it is silent. It is repo-scoped, so it fires only when an agent starts **inside
  the vault repo** — never when another project merely reads the vault over the Obsidian
  Model Context Protocol (MCP). The nudge only *offers*; accepting it runs the skill.
- **Isolation.** Every run happens on its **own branch** and opens a PR (or, with no
  `git`/`gh`, writes a `DREAMS.md` review artifact and applies nothing). It **never
  auto-merges** and never writes to `main`; the human reviews the PR. Every proposed change
  carries a one-line rationale + provenance (which session/note drove it).
- **Privacy.** Learnings are **de-identified** before landing in a tracked note; anything
  confidential is routed to `_sensitive/` with `classification: confidential`. The skill
  self-enforces this (the Obsidian Git plugin may use a bundled git that skips the native
  pre-commit guard), with `**/*.private.md` + the pre-commit confidential guard as backstops.
- **Safety.** Human-authored prose is **never** deleted or rewritten — contradictions in it
  become `> [!contradiction]` callouts for a human. `DELETE` is restricted to agent-authored
  notes. `raw/` and `_sensitive/` are never destructively rewritten.
- **Portable + fallback for non-Claude agents.** The skill core is plain Markdown any agent
  (Claude Code, Codex, Cursor, Copilot, Gemini) can run — the auto-nudge hook is the only
  Claude-Code-specific piece. **Codex/Cursor/Gemini users invoke `/vault-dream` manually**
  (no hook); a scheduled/cron run (`claude -p "/vault-dream"` or the equivalent) is a
  supported manual fallback and, as a power-user follow-up, an opt-in unattended mode — both
  still open a branch + reviewable artifact, never a silent commit to `main`.

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
  `/update-base` skill). It's **git-native** — it fetches from the base repo via an
  **ephemeral** `base` git remote (added for the fetch, then removed, so nothing standing
  can be mis-picked in Obsidian Git and push private notes to the public template) and
  overlays only the base-owned engine paths (including the curated `skill-sources.json`),
  leaving your notes, `vault-profile.md`, and `skill-sources.local.json` untouched. A
  fork/custom base URL is remembered in `.agents/.base-url`. Then run `sync-skills.sh`.
- Full mechanism: [`.agents/SKILLS.md`](.agents/SKILLS.md).

### Where skills read & write (knowledge planes)

Skills that **generate knowledge** split into two planes that never share a directory —
keep them apart so nothing collides and every agent knows where to look:

- **Vault plane (`kw-*`) — this is the KB.** `kw-compound` writes `docs/knowledge/`,
  `kw-plan`/`kw-work` write `plans/`. These are the **committed, Obsidian-indexed
  deliverable**: vault frontmatter, catalogued in `index.md`, synced to the canonical
  vault on `main`. Knowledge work *in this repo* goes through `kw-*`.
- **Engineering plane (`ce-*`) — for code repos, repo-scoped.** Compound-engineering's
  `ce-compound` writes `docs/solutions/<category>/` and `ce-plan` writes `docs/plans/`,
  with a different (enum-based) schema. CE skills write **relative to the working
  directory**, so even when installed globally their output stays in *whatever repo you
  run them in* — engineering learnings correctly land in that code repo, not here.
  **Don't run CE knowledge-writing skills inside the vault:** they'd scatter a second,
  schema-incompatible store that pollutes the Obsidian graph. (`lint-vault.sh` will
  confirm those files parse as valid YAML, but it deliberately doesn't hold `docs/` to
  the vault note schema, so it won't flag them as intruders — the graph is the tell.)
- **One copy, EveryInc's name.** The `kw-*` skills are vendored verbatim from EveryInc's
  `compound-knowledge` plugin. Their registered `name:` is `kw:compound` (the colon is
  EveryInc's; the folder is `kw-compound`) — invoke the **upstream name, `/kw:compound`**, and
  don't fork it to dash. They're committed under `.agents/skills/` for cloud sessions, and the
  vault **disables the `compound-knowledge` plugin** (`.claude/settings.json`) so the same skill
  isn't loaded twice; the skills delegate to flat-named agents vendored in `.agents/agents/`, so
  they resolve without it.

## Working in this vault: content vs engine

Two kinds of change flow through this repo, and they use **different paths**:

- **Content** — notes. When **a person** writes them in Obsidian (or explicitly asks
  an agent to write through the Obsidian MCP), they land in the **live vault working
  tree on `main`** and sync automatically via Obsidian Git (commit-and-sync +
  pull-on-start) — nobody runs git by hand. This is the path for all everyday
  knowledge work. **Agent-initiated** content edits instead go on a **branch** (see
  *Vault access* below).
- **Engine / structural** — the base layer: `AGENTS.md`, scripts, hooks,
  `skill-sources.json`, schema-wide refactors, anything `update-base` owns.
  **STOP — check `git remote get-url origin` before touching any engine file.**
  If origin is **not** the base repo, this is a **derived vault**: engine files are
  not yours to fix — no local patch, no branch, no PR. **File a GitHub issue against
  the upstream base repo instead** (see the next section — it wins over everything
  else here). Only in the base repo itself do engine changes go on a **branch + PR**,
  ideally from a **separate checkout/worktree**, not the live auto-syncing vault —
  otherwise Obsidian Git can sweep a half-applied engine change straight onto `main`.

Rule of thumb: *if a non-technical note-taker would never touch it, it's an engine
change → branch + PR.*

**But first check whose engine it is.** The branch-+-PR path above is for the **base
repo itself**. Nearly every vault built on this scaffolding is a **derived vault** — a
private clone/instance that inherits the engine via `update-base` — and there the rule
is different: engine problems go **upstream as GitHub issues**, never local fixes. See
the next section; it overrides everything else in this file when it applies.

### Engine bugs & improvements found in a derived vault → file an upstream issue. Never fix locally, never open a PR.

**Who this applies to:** any agent working in a vault whose engine came from the
obsidian-base template. Check `git remote get-url origin` — if it is **not** the base
repo itself (default `Object-3/obsidian-base`; a fork/custom base is recorded in
`.agents/.base-url`), you are in a **derived vault** and this section governs.

**What counts as "engine":** anything base-owned — the paths `update-base` overlays:
`AGENTS.md`, `CLAUDE.md`, `.agents/scripts/*` (`sync-skills.sh`, `update-base.sh`,
`lint-vault.sh`, `init-vault.sh`, …), `.claude/hooks/*`, `.claude/settings.json`,
`.agents/SKILLS.md`, `.agents/skill-sources.json`, vendored skills under
`.agents/skills/`, `.gitignore`/`.gitattributes`. Also any **optimization,
improvement, or enhancement that would benefit all clones of the base**, even if you
noticed it while doing ordinary knowledge work.

**The rule, in order:**

1. **Do NOT patch the engine file in the derived vault.** A local fix is silently
   **overwritten by the next `update-base` run**, forks the engine from upstream, and
   fixes exactly one vault while every other clone keeps the bug.
2. **Do NOT open a pull request against the base repo** — even if this session has
   push or PR access to it. The base maintainers triage via issues; an unsolicited PR
   from a derived-vault session is not the contribution path.
3. **File a GitHub issue against the base repo, immediately** — via whatever GitHub
   access the session has (GitHub MCP tools, `gh` CLI, or the API). Target the repo
   from `.agents/.base-url` if present, otherwise `Object-3/obsidian-base`. Include:
   - what you were doing when it surfaced (skill/script invoked, command run);
   - the failing behavior — exact error output or wrong result;
   - root cause if you diagnosed it (file + line);
   - your proposed fix **as text or a diff inside the issue body** — the diagnosis
     and patch are welcome, the delivery vehicle is the issue, not a PR;
   - **de-identified**: no vault names, note titles, client/deal names, or private
     paths — engine bugs are describable without any vault content.
4. **No GitHub access at all in the session?** Write the same report to a local note
   (e.g. `base-issue-<slug>.md`, `type: scratch`) and tell the user to file it against
   the base repo — don't let the finding evaporate, and still don't fix the file.
5. **Blocked right now?** If the bug prevents the user's *current* task, a minimal
   local workaround is permitted **only after** the issue is filed (or the report note
   from step 4 exists), and it must be clearly flagged to the user as **temporary —
   will be overwritten by the next `update-base`** — ideally applied as an
   un-committed working-tree change rather than committed to the vault.

**In the base repo itself** (origin *is* the base repo, or a checkout explicitly made
to contribute to it), none of this applies — develop fixes normally on a branch + PR
as described above.

### Vault access (Obsidian MCP)

The vault is a **user-owned, portable knowledge base** — reachable even from other
projects and workflows. How you touch it depends on whether you're *consuming* it or
*working on* it:

- **Consuming knowledge** — gathering, searching, or pulling vault context into
  another workflow → use the **Obsidian MCP** when available to read/search the
  **live vault**. This is the access path when you're *not* working in the vault repo
  (e.g. a different project in Claude Code that just needs the KB as a source).
- **Working on the vault** — creating, editing, or restructuring notes, anytime
  you're in this repo → use **native approaches** (file tools + a branch in a
  checkout). Don't route edits through the MCP.
- **Exception:** write to the live vault through the MCP when the **user explicitly
  asks** you to.

Why: agents that work on the vault stay on a branch, so changes are reviewable and
Obsidian Git never sweeps a half-applied edit onto `main`; the MCP stays a clean read
bridge, keeping the knowledge base accessible from anywhere without becoming a back
door for silent writes.

## For agents

- Navigate by frontmatter (`type`/`status`/`tags`) and `related` links; start from
  `index.md`. Read `.agents/vault-profile.md` for this vault's specifics.
- New notes go in the vault root (or a topical subfolder — see **Topical folders**
  under the Directory map), always with frontmatter and `tags` including the vault's
  primary tag, and a **kebab-case filename** (see **File naming**) — the human title
  goes in `title:`, not the filename.
- This is a knowledge base, not a codebase: the deliverable is well-sourced,
  decisive, cross-linked Markdown.
- Found a bug or a broadly-useful improvement in the **engine** (scripts, hooks,
  skills, `AGENTS.md`) while working in a **derived vault**? **File a GitHub issue
  against the base repo — don't fix it locally and don't open a PR.** See *Engine
  bugs & improvements found in a derived vault* above.
