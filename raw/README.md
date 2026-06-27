---
title:   "Raw sources (immutable)"
type:    reference
status:  reference
tags:    [object3, raw]
created: 2026-06-27
updated: 2026-06-27
---

# raw/ — immutable source material

Drop original source material here: web clippings, article exports, meeting/call
transcripts, data exports, PDFs. This is the **ground truth**.

**Rule: never edit a file in `raw/`.** Agents read from it and synthesize into the
vault notes (and `docs/knowledge/`), but the raw sources stay untouched so claims
remain traceable to what was actually said. See the operating rules in `AGENTS.md`.

Suggested naming: `YYYY-MM-DD-source-slug.md` (or keep original filenames). When a
note draws on a raw source, link to it and record the ingest in `log.md`.
