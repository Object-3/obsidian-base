# `_sensitive/` — the Sensitive plane (never committed to git)

Everything in this folder (except this README and `.gitkeep`) is **gitignored** — it
never reaches GitHub. It's the **Sensitive plane** of the three-bucket model in
`AGENTS.md` (*Shareable → Sensitive → Original*): confidential synthesis notes —
candid, named, number-heavy — that must stay out of git but **are first-class Obsidian
notes** (graph, `[[links]]`, backlinks, search, tags). It's also the on-disk escape
hatch for large/sensitive originals (PDFs, datasets) too big for git; the pre-commit
size guard points you here.

> Formerly named `_local/`. That name was a misnomer once the folder is cloud-backed,
> so it's now `_sensitive/`. A vault created before the rename keeps `_local/` ignored
> too (back-compat); `/setup-sensitive-plane migrate` renames it on disk.

## Durability without putting it in git

By default this folder lives on **one machine** — unbacked, not multi-device. To fix
that without breaking Obsidian or leaking into git, back it with an **org-tenant
cloud-synced folder** (Google Workspace / Drive or Microsoft 365 / OneDrive), pinned
local, one sync engine, `.obsidian/` excluded. The **`/setup-sensitive-plane`** skill
walks through it and applies the proven-safe config. Never iCloud / Obsidian Sync / a
personal account for NDA-bound material — see `AGENTS.md`.

## Who can see what's in here (by access context)

- **On this machine** (local file tools, or Obsidian + the MCP on localhost): full
  access — these are ordinary files on disk; Obsidian indexes them like any note.
- **A fresh git clone / cloud container / CI**: nothing — it's gitignored, so it isn't
  there at all. Only the de-identified breadcrumbs in the Shareable plane remain.
- **A remote/headless agent**: only if it has credentialed access to the cloud backing
  folder (provider API / service account). Git is never an ingress.

So the cloud folder's sharing/permissions (ACL) is the security boundary — scope it tight.

**Two catalogs — don't confuse where each lives:**
- The **de-identified reference note** goes in your **normal notes** — the *tracked*
  vault (root or a topical folder), **not** in here. It's a **Shareable** note: full
  frontmatter, listed in `index.md`, with **no** confidential detail (no names, owners,
  or verbatim figures). It's the breadcrumb that lets the KB — and a teammate who can't
  see this folder — know the material exists, without storing the bytes.
- **`_sensitive/_index.md`** (inside *this* folder, gitignored) catalogs what actually
  lives **here** — the local-plane counterpart to `index.md`, visible only where this
  folder is materialized.
