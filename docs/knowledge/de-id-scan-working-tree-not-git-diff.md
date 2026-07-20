---
title: "De-identification scans must read the working tree, not a bare git diff/grep"
type: correction
status: active
base_seed: true
tags: [plumbing, git, security, confidential-plane, de-identification, ingest-pdf]
confidence: high
created: 2026-07-20
updated: 2026-07-20
source: real session — a bare `git diff | grep <names>` reported CLEAN while two just-authored notes still carried a deal codename; grepping the working files directly caught it
related:
  - "[[onedrive-sensitive-plane-setup-gotchas]]"
  - "[[ephemeral-fetch-remote-pattern]]"
---

# De-identification scans must read the working tree, not a bare git diff/grep

The confidential-plane workflow tells an agent (or person) to **de-identify before
committing** — strip third-party names, owners, and verbatim figures out of any note
that will reach a synced git host. The natural way to *check* that is a scan like
`git diff -- . | grep -i <names>`. **That check is broken by construction:** it silently
skips exactly the files most likely to still carry a codename — the ones you just wrote.

## TL;DR

- **`git diff` and `git grep` only see tracked content.** A brand-new note is *untracked*
  until `git add`, so a bare `git diff … | grep <names>` (or a bare `git grep <names>`)
  reports **CLEAN** even while that new note still contains a confidential name — and then
  it gets committed.
- **Observed for real:** `git diff -- . | grep -i <names>` said CLEAN while two
  just-authored notes still held a deal codename; a direct `grep` of the working files
  caught them.
- **Fix — scan the working tree, or scan after staging:**
  - Working tree directly (catches untracked):
    `grep -rin -e "<name>" -e "<owner>" . --exclude-dir=.git --exclude-dir=_sensitive --exclude-dir=_local`
  - **or** run the scan *after* `git add`, so `git diff --cached` / `git grep --cached`
    (and `git grep --untracked`) can see the new files too.
  - **Never** a bare `git diff`/`git grep` as the pre-commit de-id gate.

## Why the pre-commit guard doesn't cover this

The `classification: confidential` pre-commit guard (`.githooks/pre-commit`) is **fine** —
it scans **staged** content (`git diff --cached`), which *does* include new files once
they're `git add`-ed. Two things keep it from being the whole answer:

1. **It runs after staging, on frontmatter only.** It blocks a note *tagged*
   `classification: confidential…` / `availability: local-only` from landing outside
   `_sensitive/`. It does **not** catch a stray codename inside an otherwise-shareable
   note that carries no such tag — which is precisely what de-identification is about.
2. **The interactive pre-stage scan is a separate control.** The gap is the *manual*
   "de-identify before commit" check an agent runs by hand, and any guidance modeled on
   `git diff`. That scan is the one that must read the working tree.

So the two controls are complementary: the hook is a staged-content backstop for
*tagged* notes; the working-tree grep is the pre-stage gate for *de-identifying* content
that isn't tagged at all.

## Where this is enforced in the base

- `AGENTS.md` → *Confidential & third-party material* now carries the rule
  ("Scan before you commit — the working tree, not a bare `git diff`").
- `/ingest-pdf` step 8 ("Verify the boundary held") uses the working-tree `grep -rin …`
  form instead of the old `git grep -- .` that shared this blind spot.
- `/vault-dream` step 6's "nothing confidential in a tracked note" re-scan says the same.

## Caveats

- **Exclude the sensitive planes and `.git`.** A plain recursive grep over the whole vault
  would flag the confidential names where they *legitimately* live (`_sensitive/`,
  `_local/`) and churn through `.git/` internals — hence the `--exclude-dir` list. The old
  `git grep -- . ':!_sensitive' ':!_local'` got the exclusions right but the tracked-only
  scope wrong.
- **`git grep --untracked` is a valid third option** — it adds untracked (non-ignored)
  files to git grep's scan and keeps the pathspec-exclusion syntax. Plain `grep -rin` is
  preferred in the docs because it doesn't depend on git's staging state at all.
- **`--exclude-dir` is supported by both GNU grep and macOS/BSD grep**, so the one-liner is
  portable across the environments this vault runs in.
