---
name: ingest-pdf
description: Ingest one or more PDFs (or other large/binary source documents) into the knowledge base through a confidentiality-aware workflow — extract the text, keep the original off-git, and synthesize linked notes that degrade gracefully when the original isn't present. Use when the user hands over PDFs / decks / contracts / reports / datasets and wants to "ingest", "file", "capture", "add to the vault", or "put this in my knowledge base" — especially anything confidential, NDA-bound, or holding third-party or regulated detail (financials, client or personal records, embargoed material).
---

# Ingest a PDF (confidentiality-aware) into the vault

Turn a source document — usually a PDF, but any large / binary / sensitive original —
into well-linked vault notes **without** putting bytes or confidential third-party detail
into git. Built for the case this base is designed around: a git-synced vault where some
material (NDA-bound documents, third-party or regulated records, private originals) must
stay off the remote but still be a first-class, linked Obsidian note **locally**.

## The core idea — sort into three buckets

Sort every artifact into one of three buckets — **Shareable → Sensitive → Original**, in
rising order of sensitivity — and route it accordingly:

| Bucket | What | Home | In git? |
|---|---|---|---|
| **Shareable** | Strategy / synthesis with **no** third-party-confidential detail | vault (tracked) | yes |
| **Sensitive** | Synthesis that must stay private (third-party-confidential detail, candid reads) but needs to be a linked Obsidian note locally | `_local/` (gitignored) | no |
| **Original** | The raw bytes (PDF, deck, xlsx) | Google Drive (shareable / automatable) or `_local/` | no |

The governing line for confidential material is usually **"no disclosure to a third
party"** — and a synced git host *is* a third party. If there's an NDA, **read it first**;
its terms set the sorting.

## Steps

1. **Orient.** Read `AGENTS.md` (esp. *Large files*, *Confidential & third-party material*,
   *Vault access*), `.agents/vault-profile.md` (primary tag, voice, no-PHI rules), `index.md`,
   recent `log.md`. Search the vault for related notes so you **link, not duplicate**.

2. **Classify sensitivity first**, per document: shareable, sensitive, or
   third-party-confidential. If a document is governed by an NDA, read the NDA and let it
   set policy. **When in doubt, keep it out of git — Sensitive or Original.**

3. **Extract the text.** PDFs need a real extractor — the Obsidian MCP can't read them and
   the Read tool needs poppler. Prefer `pdftotext -layout "<in>" "<out>"` (install once:
   `brew install poppler`). Extract to **gitignored scratch** (`.context/` or `_local/`),
   never the tracked tree. For chart/image pages, render with poppler + read as an image.

4. **Park the original.** Move the raw file to Google Drive (shareable with
   collaborators, reachable by agents) or `_local/`. **Never commit the original** — the
   size guard and `_local/*` gitignore are backstops, not the plan.

5. **Write the notes, by bucket:**
   - **Shareable → tracked vault note** — full frontmatter (incl. the primary tag),
     `TL;DR … Caveats`. For third-party material, **de-identify**: no party name, owner, or
     verbatim figures/records — only generalizable, non-identifying synthesis. Often there is *no*
     per-document shareable note for a confidential third party; a small reference note that just
     says what/where the original is can be enough.
   - **Sensitive → `_local/<name>.md`.** When you're working on a branch, write these
     **through the Obsidian MCP into the live vault** (`obsidian_append_content`) — git can't
     carry `_local/`, but the MCP lands the note in the *running* vault where it's indexed and
     gitignored. Add `classification: confidential-local-only` + `availability: local-only`.

6. **Keep links working across both planes — one rule:**
   > **Links point *up* the sensitivity gradient (shareable → sensitive → original) freely;
   > references *down* are optional, labeled, and never load-bearing.**
   - A Shareable note's `related:` frontmatter lists **only other Shareable notes** → resolves everywhere.
   - Sensitive notes and Originals link **up** to Shareable notes (which exist everywhere) → backlinks connect locally.
   - The only downward reference is a single labeled callout, e.g.
     `> [!lock] Local-only companion: [[…]] — present on this machine by design`. When the
     local note is absent (cloud run, fresh clone, the remote), it reads as intentional, not broken.

7. **Maintain both backbones.**
   - **Git:** add a catalog entry to `index.md` *only if there's a shareable note*, and a
     **de-identified** `log.md` entry — never the confidential identity or figures/records.
   - **Local:** catalog Sensitive notes in a gitignored **`_local/_index.md`** — the local-plane
     counterpart to `index.md`.

8. **Verify the boundary held.** Before finishing, prove nothing leaked:
   `git grep -i -e "<party name>" -e "<owner>" -- . ':!_local'` must return nothing in tracked
   files. Confirm Sensitive notes are in the live vault's `_local/` and **absent** from the tracked tree.

9. **Compound.** Extract reusable learnings to `docs/knowledge/` (`/kw-compound`).

## Make sensitivity machine-enforced (don't rely on memory)

Two backstops this base ships, so a stray sensitive note can't leak:
- **`**/*.private.md`** is gitignored everywhere — name a stray sensitive note `*.private.md`
  and it stays out of git wherever it sits (Obsidian still indexes it).
- The **pre-commit guard** (`.githooks/pre-commit`) blocks committing a note whose frontmatter is
  `classification: confidential…` outside `_local/`. Obsidian Git's bundled git may skip native
  hooks, so the durable rule is still "sensitive → `_local/` or `*.private.md`."

## What NOT to do

- Don't put third-party-confidential identities, figures/records, or originals in git — not even in
  `index.md` / `log.md`, and not even in a "private" repo.
- Don't `![[embed]]` a Sensitive note or Original from a Shareable note (it dangles when the file is absent).
- Don't route Shareable writes through the MCP onto `main` when the task wants a reviewable branch/PR —
  write those natively on the branch; use the MCP for the `_local/` plane.
- Don't reformat `raw/` or `_local/` originals.

## Notes

- Hand-authored, repo-local skill — not vendored, so `sync-skills.sh` won't overwrite it;
  `update-base` propagates it to downstream vaults (it's listed in update-base's overlay paths).
- Pairs with the *Confidential & third-party material (what goes where)* section of `AGENTS.md`
  and the *Vault access (Obsidian MCP)* rules.
