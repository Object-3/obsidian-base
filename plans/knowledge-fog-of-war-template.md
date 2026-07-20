---
title:   "Template changes to facilitate fog-of-war awareness & agentic expansion"
type:    research
status:  draft
tags:    [knowledge-base, meta, planning, fog-of-war]
created: 2026-07-20
updated: 2026-07-20
confidence: medium
sources: 11
---

# Plan — make the template facilitate "fog-of-war" awareness + agentic expansion

## Context

A deep-research pass (11 verified findings, 2025–2026 literature) established the meta:
a knowledge base should treat **"what it doesn't know" as a first-class, representable
object**, detect **staleness structurally** (embedding similarity provably can't — a
contradicting fact is *more* similar to the original than a rephrase; AUROC ~0.59), and
run a **background consolidation pass** that supersedes, forgets, and goes to fill gaps.

This template already has the *skeleton* — `/vault-dream`, `stale-knowledge-checker`,
`> [!contradiction]` callouts, the compounding loop — but lacks the *substrate*: no way to
record a known-unknown, no validity/time signal distinct from file `updated:`, and
stale-checking that is reactive + single-model + relational-only. This change adds that
substrate and upgrades the dream to use it, so **every derived vault inherits a
"fog-of-war map"** it can maintain and act on.

Key sources: Know Your Limits / abstention (TACL 2025); GAPMAP/TABI gap schema (NeurIPS
2025); Zep/Graphiti bi-temporal invalidate-not-delete (arXiv 2501.13956); multi-LLM
abstention +19.3% (ACL 2024); sleep-time compute / SleepGate consolidation (2026
preprints); temporal-RAG freshness limits (arXiv 2509.19376).

## Design decisions (defaults — flip any)

1. **Scope → Foundation + awareness.** Ship the representational substrate + adversarial
   stale-checking now; **defer the autonomous web-retrieval expansion loop to phase 2.**
   The schema is what every derived vault inherits via `update-base`, so it lands first
   and stable; the retrieval loop is behavior that bolts onto a proven representation.
2. **Gap format → backbone `gaps.md`.** One maintained catalog, sibling to
   `index.md`/`log.md`/`hot.md`. Greppable, single global view, low ceremony, maintained
   by the dream. No new `type:` enum needed (keeps the lint/enum surface minimal).
3. **Automation → LLM-driven in `/vault-dream`.** Enrich the skill + dispatch repo-local
   subagents (markdown only); no net-new scripts/hooks in phase 1. A deterministic
   orphan/coverage scanner is phase-2 optional (no wikilink-graph walker exists today, so
   that's real net-new code we're deliberately deferring).

---

## Phase 1 — what changes

### A. Frontmatter schema — 4 new *optional* fields (the substrate)

Add to the canonical schema block at **`AGENTS.md:33–38`**, all optional/additive (no
existing note breaks). `confidence:` already exists and covers the epistemic-state axis.

| Field | Meaning | Research basis |
|---|---|---|
| `valid_as_of: YYYY-MM-DD` | When the claim was last confirmed true *in the world* — distinct from `updated:` (when the *file* changed). Valid-time vs transaction-time split. | Graphiti bi-temporal |
| `review_by: YYYY-MM-DD` | When the dream/auditor should re-examine this note. Per-note recency trigger. | Freshness limits (2509.19376); existing 90-day heuristic |
| `superseded_by: "[[slug]]"` | Supersession pointer — **invalidate, don't delete**. Pairs with existing `status: archived`. | Graphiti invalidate-not-delete; MemStrata |
| `open_questions:` (list) | Known-unknowns this note is aware of but hasn't answered — the note flagging its own edges. Harvested into `gaps.md` by the dream. | Abstention (TACL 2025); GAPMAP |

### B. New backbone file: `gaps.md`

- Root-level backbone catalog (sits alongside `hot.md`/`index.md`) — the vault's
  **fog-of-war map**. Entry format is TABI-lite: **the gap (Claim) · what we do know /
  what raised it (Grounds) · why it matters (Warrant) · confidence + status**
  (`open` / `researching` / `answered → [[note]]`), with provenance to the note(s) that
  raised it.
- **Each entry also carries a resolution route** — `resolve_via: web | ask-owner |
  unknowable` (the abstention *query axis* from *Know Your Limits*, TACL 2025). This lets
  the expansion loop route a gap to web retrieval, to a human, or to abstention from day
  one — *before* either loop exists.
- **`ask-owner` entries double as elicitation-queue items** (see B2): stable `id`,
  `status: unasked | asked | answered | skipped`, and slots `asked_via` / `asked_at` /
  `answered_at`. Idempotent (never re-ask an answered question) and auditable.
- **Register it as a backbone file** everywhere the other three are special-cased:
  - `lint-vault.sh` `scan_mode()` (~93–96) → yaml-tier + reserved-name exemption.
  - `AGENTS.md` directory-map table (~94–113) → new row; reserved-backbone list (~82).
  - `normalize-vault/SKILL.md` refuse-list (~90–104) and `/vault-dream` "don't touch as a
    regular note."
  - `init-vault.sh` → seed a placeholder `gaps.md` (as it seeds `index/log/hot`); add a
    seed `gaps.md` at this repo root. `gaps.md` is **per-vault content** (like `index.md`)
    — NOT added to `update-base` PATHS.

### B2. Human elicitation channel — forward-compatible (queue now, comms later)

Some gaps can never be answered by `WebSearch` — internal/proprietary/tacit knowledge that
only lives in a person's head (the "needs-unavailable-context" bucket of the abstention
query axis; the classic *active-learning* "query the oracle" + *tacit-knowledge
elicitation* paradigms). The right resolution for these is **ask the owner**, not search.

**The overnight/headless case forces the architecture.** vault-dream may run while the
owner sleeps and they answer hours later out-of-session, so a synchronous prompt (e.g. a
live `AskUserQuestion`) is impossible. The elicitation must therefore be **queue-as-durable
-data + a thin, swappable delivery adapter**:

- **Phase 1 (do now — the only expensive-to-retrofit part is the data shape):** the
  `ask-owner` items in `gaps.md` (stable `id`, `status`, `asked_via`/`asked_at`/
  `answered_at` — see B) *are* the queue. Delivery stays **passive**: questions live in
  `gaps.md` and ride the existing SessionStart nudge. No comms wiring yet. Ask the *few*
  highest-value questions (MAGELLAN learning-progress frame), never a wall of them.
- **Deferred (phase 2/3 — pure adapters, designed as a seam):**
  - A **pluggable notifier** step: read `status: unasked` `ask-owner` items → deliver via a
    configured channel (email / Slack / Teams **MCP** adapter). vault-dream's core never
    changes when a channel is added — adding one = "write one adapter + set one config
    value." The transport primitives already exist at the harness level (Microsoft 365 /
    Teams / Outlook MCP tools; the remote harness's `send_later` / routines / push).
  - **Channel config in `vault-profile.md`** — a `comms:` stanza (preferred channel +
    handle; **no secrets**, creds via the provider/MCP), managed by a future `/setup-comms`
    skill exactly the way `/setup-sensitive-plane` manages its block. Lets a headless
    overnight run know where to send.
  - **Answer-ingestion-by-id:** a reply comes back → matched to the question `id` → ingested
    as a note with provenance `source: owner-reply`, routed to `_sensitive/` when
    confidential (natural tie-in to the existing confidentiality plane).

### C. Adversarial + time-aware stale-checking  ⚠️ CORRECTED

**Do NOT edit the vendored `stale-knowledge-checker.md`.** It is vendored from EveryInc's
compound-knowledge plugin (listed in `skill-sources.lock.json` `agents[]`), so
`sync-skills.sh` re-fetches it on every sync and **any in-place edit gets clobbered.**

Instead:

- **Add a new repo-local subagent** `.agents/agents/frontier-auditor.md` (hand-authored,
  therefore *not* in the lock → never clobbered). Its job: **time/validity-aware staleness
  detection** (`valid_as_of` age, `review_by` elapsed, "external fact likely changed"
  heuristics — the signals the vendored checker lacks, which is purely relational) **plus
  coverage-gap surfacing** (orphans, thin/uncovered topics, harvesting `open_questions:`).
- **The adversarial cross-check falls out for free:** in `/vault-dream` phase 4, dispatch
  **both** the vendored `stale-knowledge-checker` **and** the new `frontier-auditor`, and
  require the two *independent* agents to agree before any `DELETE`/supersede on an
  agent-authored note. That is the multi-LLM "cooperate/compete" pattern (+19.3% over
  single-model self-review, ACL 2024) achieved without touching the vendored file.
- Human-authored prose stays untouchable → `> [!contradiction]` callout, as today.

### D. `/vault-dream` upgrades (the "sleep-time" behaviors)

`/vault-dream/SKILL.md` is hand-authored and repo-local (never clobbered) — the right home
for our fog-of-war logic.

- **Phase 4 — gap-surfacing sub-step:** harvest note `open_questions:` + detect
  thin/orphan/uncovered topics (LLM judgment over `index.md` + tag coverage) → maintain
  `gaps.md`, **classifying each gap's `resolve_via`** (web / ask-owner / unknowable) and
  populating the `ask-owner` elicitation queue (B2). "Identify which questions the docs can't yet
  answer."
- **Phase 4 — supersession:** when a note is superseded, set `superseded_by:` +
  `status: archived` and close it out rather than delete (invalidate-not-delete).
- **Phase 4 — adversarial confirm:** the dual-agent consensus gate from section C.
- **Phase 5 — intentional forgetting:** archive/roll-up genuinely dead agent-authored
  notes (the DELETE-is-agent-authored-only rail already exists) and record it —
  "forgetting as a first-class op."

### E. New template convention — never edit vendored skills/agents in place

Generalize the section-C lesson into an explicit rule in the template, because it will
recur every time we want to change vendored behavior:

> **Vendored skills/agents are read-only.** Anything listed in
> `.agents/skill-sources.lock.json` (`skills[]` / `agents[]`) is re-fetched by
> `sync-skills.sh` and your edits get clobbered. To change vendored behavior, **hand-author
> a repo-local sibling** (a new skill dir or `.agents/agents/*.md` — never in the lock) and
> have your orchestrator dispatch it, or fork it out of the lock. This is also why
> base-authored agents must be propagated by `update-base` (section F).

- Document in **`AGENTS.md`** (the "Skills (portable across agents)" section) as the
  authoritative engine contract.
- Optionally capture as a `docs/knowledge/` playbook via `/kw:compound` (don't hand-write
  that plane).

### F. Required engine fix — agent propagation via `update-base`

`.agents/agents/` is **NOT** in the `update-base` `PATHS` array and has **no
auto-discovery** — so our new repo-local `frontier-auditor` would never reach derived
vaults. Fix `update-base.sh`: either add `.agents/agents` to `PATHS` (61–83) or mirror the
base-authored-*skill* derivation (105–128) for agents, excluding vendored ones listed in
`skill-sources.lock.json` `agents[]`. **Without this, sections C/D are invisible
downstream.**

### G. Keep the hand-synced enum/schema copies consistent

The `type`/`status` enum lists live in **three independent copies** (`AGENTS.md:28`,
`lint-vault.sh:38`, `normalize-vault/SKILL.md:41`). Phase 1 adds only *optional fields* (no
new `type`), so edits are just `AGENTS.md:33–38` + `normalize-vault/SKILL.md:48`
(optional-fields line); no `lint-vault.sh:38` change. Note the triplication as a known
fragility in the PR.

---

## Files to touch (phase 1)

- `AGENTS.md` — schema block (33–38); directory table (~94–113); reserved-backbone list
  (~82); vendored-are-read-only convention (Skills section).
- `.agents/scripts/lint-vault.sh` — `scan_mode()` backbone registration for `gaps.md`
  (~93–96).
- `.agents/scripts/init-vault.sh` — seed `gaps.md`; new root `gaps.md` seed file.
- `.agents/skills/vault-dream/SKILL.md` — phase 4 (gap-surfacing, supersession, dual-agent
  confirm) + phase 5 (forgetting).
- `.agents/agents/frontier-auditor.md` — **new** repo-local subagent (time/staleness +
  gaps + independent skeptic + classify each gap's `resolve_via` route).
- `.agents/skills/normalize-vault/SKILL.md` — optional-fields line (48); `gaps.md`
  refuse-list (90–104).
- `.agents/scripts/update-base.sh` — agent propagation fix (61–83 / 105–128).
- `.agents/scripts/test-lint-vault.sh` — fixture: `gaps.md` is yaml-tier; new optional
  fields pass.
- **Untouched:** `.agents/agents/stale-knowledge-checker.md` (vendored — deliberately not
  edited).

## Verification

1. **Linter:** run `lint-vault.sh` on a scratch note with all 4 new fields → pass; on
   `gaps.md` → yaml-tier, not schema-flagged. Run `test-lint-vault.sh`.
2. **Backbone:** confirm `gaps.md` skipped by kebab/schema checks and `normalize-vault`
   refuse-list.
3. **Dream dry-run:** run `/vault-dream` against a seeded scratch session; confirm it
   (a) rolls `open_questions:` into `gaps.md`, (b) proposes supersede as `superseded_by` +
   `status: archived` (not delete), (c) dispatches both stale-checker + frontier-auditor
   and requires consensus before any agent-authored delete, (d) opens a branch/PR, never
   touches `main`.
4. **Propagation:** dry-run `update-base.sh` logic → confirm `frontier-auditor.md` is in
   the overlay set and vendored `stale-knowledge-checker.md` is not double-managed.
5. **Sync safety:** run `sync-skills.sh` → confirm `frontier-auditor.md` survives
   untouched (not in the lock) and the vendored checker is unmodified.
6. **Pre-commit:** confidential-note guard still fires (unchanged).

## Deferred — phase 2/3 (autonomous expansion loop + comms adapters)

**Routing by `resolve_via` (the loop reads the phase-1 classification):**

- **`web` → autonomous retrieval (MetaKGEnrich/AgREE pattern):** detect a sparse region
  (orphan/thin note, `open` web-gap) → generate targeted questions → **retrieve web
  evidence** → ingest as a new note with provenance → mark the gap `answered` → re-check.
  Optionally backed by a net-new deterministic `gap-scan.sh` (orphan/coverage over the
  wikilink graph) with its own cadence hook, mirroring the `dream-scan.sh` +
  `dream-if-stale.sh` watermark pattern.
- **`ask-owner` → human elicitation via a pluggable comms adapter (B2):** a notifier reads
  `status: unasked` items → delivers the few highest-value questions via a configured
  channel (email / Slack / Teams **MCP** adapter); replies are matched back by `id` and
  ingested (`source: owner-reply`, sensitive-routed). Channel config in `vault-profile.md`
  `comms:` (managed by a future `/setup-comms`, à la `/setup-sensitive-plane`). The seam is
  designed in phase 1 so this is "add an adapter + set a config value," not a redesign.
- **`unknowable` → abstain:** mark and stop; don't burn retrieval or the owner's attention.

Deferred because it rests on the phase-1 representation and is the largest net-new surface;
the comms adapters additionally wait on the vault's communication channels coming online.

## Architecture note — the notifier is a decoupled *service* (code, not markdown)

Delivery/notification is deterministic plumbing (auth, retries, scheduling, idempotency,
matching replies to a question `id`), so it belongs in **real code**, not LLM judgment. The
division of labor: **vault-dream (LLM) decides *what* to ask and prioritizes; a notifier
(code) delivers it and ingests the answer.** Decisions settled in this session:

- **Source of truth = the vault markdown.** Open questions / gaps live in `gaps.md` (per
  §B/B2), never a database — that keeps them git-versioned, Obsidian-native, and
  human-editable, and they're low-volume human-scale data. The notifier MAY keep its own
  **derived, disposable** state (e.g. a small SQLite/JSON cache of "already delivered" and
  channel-message-id ↔ question-id); if lost, it rebuilds from the markdown. No coupling.
- **The code lives in its own repo/package, NOT inside the vault.** The vault is content;
  the notifier is an application (auto-committed vault ≠ home for a running service). **The
  contract between them is the documented `gaps.md`/open-questions *file schema*, not a code
  import** — Unix "programs + text streams" decoupling. Either side evolves independently as
  long as the schema holds.
- **One daemon, many vaults.** Because it's pointed at vault path(s) + creds + a schedule,
  the same binary serves any obsidian-base-derived vault. This template **owns the schema**
  (+ optionally a `/setup-comms` that installs/configures the daemon); the daemon repo owns
  the code.
- **Local vs cloud, same contract.** Local: a small background service the user installs
  once and forgets (launchd/systemd/menubar). Cloud: the same binary as a service/cron — or
  lean on the remote harness's existing scheduled routines + push, where a scheduled agent
  turn reads `gaps.md` and calls the messaging tool.
- **Zero per-channel adapters via a gateway.** Deliver *through* a unified messaging gateway
  that already speaks email/Slack/Teams → the daemon writes ONE integration (to the gateway)
  + the vault-reading logic. **TBD:** confirm the role of Hermes / OpenClaw (from prior
  sessions) — working assumption is one of them IS that gateway; wire the daemon to it once
  confirmed.

