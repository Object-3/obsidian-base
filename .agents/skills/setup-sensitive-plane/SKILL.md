---
name: setup-sensitive-plane
description: Set up (or repair) durable, multi-device storage for the vault's confidential `_sensitive/` plane by backing it with an org-tenant cloud-synced folder, WITHOUT putting it in git or breaking Obsidian. Use when the user handles confidential / NDA / third-party material and wants it backed up and on their other devices, when onboarding asks "where should my sensitive notes live", or when they say "set up sensitive storage", "back up _sensitive", "cloud-back my private notes", "multi-device confidential notes", "protect my confidential vault", "migrate _local to _sensitive", or "make my confidential notes durable". Drives setup-sensitive-plane.sh and ALWAYS ends by telling the user, in plain language, that they have a private folder and how to use it.
---

# Set up the Sensitive plane's backing store

Your job: give the user a **confidential `_sensitive/` plane that is durable and
multi-device** — without ever putting confidential material in git or breaking
Obsidian — and then **tell them, simply, that they have it and how to use it.**

This is **opt-in and value-gated**: only run it for someone who actually handles
confidential material and wants durability/sharing. For purely personal,
single-machine notes, the plain `_sensitive/` folder already works — don't push this.

The mechanical core is `.agents/scripts/setup-sensitive-plane.sh` (idempotent — safe to
re-run). You own the judgment the script can't: provider choice, the org-vs-personal
warning, wiring agent read access, and the plain-English handoff.

## 0. Orient

- Read `AGENTS.md` → *Confidential & third-party material* and *Where the Sensitive
  plane lives*. Read `.agents/vault-profile.md`.
- Run `setup-sensitive-plane detect`. It reports OS, detected cloud clients (and whether
  each looks like an **org** or **personal** account), the current `_sensitive/` state,
  any **legacy `_local/`**, and any already-recorded choice.
- If a legacy `_local/` is present, offer `setup-sensitive-plane migrate` first (renames
  it → `_sensitive/` on disk; both stay gitignored, so nothing is ever exposed).

## 1. Choose the provider (the judgment call)

Detect/ask the user's stack — **Google Workspace**, **Microsoft 365**, or neither — and
**whether it's an organization tenant**. ⚠️ **Warn hard if it's a personal account**: a
personal `@gmail.com` / consumer Microsoft account is **not** covered by a DPA/BAA and is
**inappropriate for NDA-bound or regulated material** (fine for personal knowledge work).

Offer options in priority order:

1. **Org cloud-sync folder at `_sensitive/`** *(recommended for any business)* —
   Google Workspace / Drive or Microsoft 365 / OneDrive on an **org tenant**.
2. **Obsidian Sync, selective to `_sensitive/`** *(personal only)* — elegant and cheap,
   E2E-encrypted, but **no SOC 2 / no BAA** → never for firm-confidential material.
3. **Scripted local→cloud backup** *(lowest-effort fallback)* — a one-way copy job; no
   live multi-device, but better than single-machine-unbacked.

Decision matrix (verified guidance):

| | M365 / OneDrive | Google Workspace / Drive | iCloud | Obsidian Sync |
|---|---|---|---|---|
| DPA/BAA | default (Business/Ent.) | available, separate signature | **none ever** | **none** |
| SOC 2 Type 2 | yes | yes | no | none found |
| Headless agent read | Graph app-only (`Files.Read.All`) | service account | **no file API** | n/a |
| Verdict for NDA data | ✅ strong (mature DLP) | ✅ good | ❌ never | ❌ personal only |

## 2. Provision (drive the script)

Pick a backing folder **inside the cloud root** (e.g. `~/Library/CloudStorage/GoogleDrive-<org>/My Drive/<vault>-sensitive`), then:

- **Symlink mechanism (universal):** `setup-sensitive-plane link --backing-dir "<abs path>"`.
  It migrates existing contents, symlinks `_sensitive/` → the backing folder, and keeps
  git clean. (For **Google Drive for Desktop**, you may instead "mirror" the existing
  `_sensitive/` folder via Drive's GUI — no symlink — then skip `link`.)
- **Apply the proven-safe config** (these are provider-GUI settings the script can't set):
  1. **Pin local** — "Always keep on this device" / disable Files-On-Demand /
     Optimize-Storage, so files never dehydrate to **0-byte stubs**.
  2. **One sync engine** on this path (the cloud client only — not Obsidian Sync/Git too).
  3. **Never sync `.obsidian/`**; sync only the `_sensitive/` subtree.
- **Verify:** `setup-sensitive-plane verify` (probe note round-trips) and
  `setup-sensitive-plane check` (the non-negotiables checkable locally).

## 3. Wire headless agent read (optional — for remote/automation)

Only if an agent must read the plane **without** this machine's synced copy. This is a
**separate credential from the human login**, and least-privilege on the folder is the
whole control:

- **Google:** create a **service account**, share *only* the backing folder with it (or
  domain-wide delegation scoped to it); agents read via the Drive API.
- **Microsoft:** register a **Graph app** (app-only), grant `Files.Read.All` (or scope to
  the site/drive); agents read via Graph.

Confirm a headless read works, then move on.

## 4. Record the choice

```
setup-sensitive-plane record --provider "Google Workspace / Drive" \
  --account-type org --mechanism symlink --agent-read "Google service account"
```

Writes the **Sensitive plane backing store** block in `.agents/vault-profile.md`
(idempotent — replaced in place). It stores **no secrets or paths** (vault-profile is in
git): the exact local path is resolved at runtime via `readlink _sensitive`.

## 5. ALWAYS tell the user — plainly (REQUIRED)

**Never finish setup silently.** Whenever a sensitive location is created or repaired,
the user must be told it exists and how to use it — **simply, non-technically.** Run:

```
setup-sensitive-plane explain
```

and deliver that card in your own warm, plain words. The four things they must walk away
knowing:

1. **They have a private folder, `_sensitive/`** — the "locked drawer" of their notes.
2. **What goes in it** — anything confidential (client/NDA, financials, candid notes).
3. **What happens to it** — backed up + on their devices, but **never in GitHub / the
   shared repo**, and visible **only** to people they've shared the cloud folder with.
4. **The one rule** — sensitive things go **only** in `_sensitive/`; everything in normal
   notes is shared with everyone on the knowledge base.

Keep it concrete and reassuring: *"In Obsidian it's just a folder — drop private notes in
`_sensitive/` and you're done."* No talk of symlinks, ACLs, or sync engines unless asked.

## How access control actually works (so you can explain it)

Access is **delegated to the cloud provider's native sharing** — the vault enforces
nothing itself. The boundary is dead simple: **is the file physically on this disk or
not**, which the provider's IAM decides upstream.

- A collaborator who shares the same knowledge base but is **not** on the cloud folder's
  ACL gets the repo's **shareable notes only**. Their `_sensitive/` is empty (it's
  gitignored, never cloned; their sync client, signed in as them, can't pull the folder).
  **Obsidian on their machine never even indexes it.** They see the de-identified
  breadcrumbs (`> [!lock] Local-only companion …`) but never the content.
- The model holds **iff sensitive material only ever lands in `_sensitive/`** (or a
  `*.private.md` file). The backstops enforce this: `**/*.private.md` is gitignored, and
  the pre-commit guard blocks a `classification: confidential…` note staged outside
  `_sensitive/`. Need tiers? Use another backing folder with its own ACL.

## Idempotency & re-running

Everything is safe to re-run: `detect` / `verify` / `check` / `explain` are read-only or
self-cleaning; `migrate` no-ops once done; `link` no-ops if already linked to the same
target (re-point with `--force`); `record` replaces its block in place (never duplicates).

## Notes

- Hand-authored, repo-local skill — not vendored, so `sync-skills.sh` won't overwrite it;
  `update-base` propagates it to downstream vaults (listed in update-base's overlay paths).
- Pairs with `/ingest-pdf` (the consumer of the Sensitive plane) and the *Confidential &
  third-party material* + *Where the Sensitive plane lives* sections of `AGENTS.md`.
