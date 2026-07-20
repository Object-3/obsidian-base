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
- **Fix — scan tracked *and* untracked files, or scan after staging:**
  - **Preferred — `git grep --untracked`:** scans tracked **and** untracked (non-ignored)
    files, so brand-new notes are covered, while honoring `.gitignore` — so it skips
    `_sensitive/` and scratch dirs (`.context/`, `.trash/`, gitignored `docs/plans/`) for free:
    `git grep -in --untracked -e "<name>" -e "<owner>" -- . ':(exclude)_sensitive' ':(exclude)_local'`
    (use the **long-form** `:(exclude)…` pathspec — the short `:!`/`:^` form errors on a path that
    starts with `_`: `fatal: Unimplemented pathspec magic '_'`, verified on git 2.43)
  - **or** run the scan *after* `git add`, so `git diff --cached` / `git grep --cached`
    sees the new files too.
  - **Fallback (no git):** a plain working-tree `grep -rin -e "<name>" -e "<owner>" .` — but
    *you* must exclude every gitignored scratch dir by hand
    (`--exclude-dir=.git --exclude-dir=_sensitive --exclude-dir=_local --exclude-dir=.context …`),
    or it false-positives on the confidential source text those dirs legitimately hold.
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
  ("Scan before you commit — include untracked files, not a bare `git diff`").
- `/ingest-pdf` step 8 ("Verify the boundary held") uses `git grep --untracked` instead of
  the old `git grep -- .` that shared this blind spot.
- `/vault-dream` step 6's "nothing confidential in a tracked note" re-scan says the same.

## Caveats

- **Why `git grep --untracked` beats a plain `grep -r`.** `--untracked` catches the new,
  still-unstaged notes (the whole point) *and* honors `.gitignore` — so it skips `_sensitive/`,
  `_local/`, and scratch like `.context/` automatically. A plain `grep -r .` sees none of that:
  it needs a hand-maintained `--exclude-dir` list that drifts out of sync with `.gitignore` and
  will **false-positive** on the extracted confidential source text `/ingest-pdf` step 3 parks in
  `.context/`. The old `git grep -- .` had two bugs at once: the *tracked-only* scope (the headline
  gap) **and** a fragile short-form `:!_sensitive` pathspec — `--untracked` fixes the scope and the
  long-form `:(exclude)…` fixes the pathspec.
- **Use the long-form `:(exclude)…` pathspec, not the short `:!`/`:^`.** On git 2.43 a short-form
  exclude whose path starts with `_` (`:!_sensitive`) dies with `fatal: Unimplemented pathspec magic
  '_'` — git reads the `_` as a magic signature char. The long form `:(exclude)_sensitive` parses
  cleanly and is supported further back, so it's the portable choice.
- **`--exclude-dir` (for the no-git fallback) is supported by both GNU grep and macOS/BSD
  grep**, so the fallback one-liner stays portable — just keep its exclude list current with
  `.gitignore`.
