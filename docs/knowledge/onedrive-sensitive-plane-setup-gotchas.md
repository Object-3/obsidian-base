---
type: pattern
base_seed: true
tags: [setup-sensitive-plane, onedrive, microsoft365, sensitive-plane, gotcha]
confidence: high
created: 2026-07-02
source: running /setup-sensitive-plane with Microsoft 365 / OneDrive for a new topic vault
related:
  - "[[fresh-vault-uncommitted-personalization-and-branch-drift]]"
  - "[[ephemeral-fetch-remote-pattern]]"
  - "[[de-id-scan-working-tree-not-git-diff]]"
---

# Setting up `_sensitive/` on OneDrive: four recurring gotchas

Backing a vault's `_sensitive/` plane with Microsoft 365 / OneDrive via
`/setup-sensitive-plane` surfaced four friction points. None are blockers, but each
cost real back-and-forth to diagnose the first time.

**1. `brew install --cask onedrive` fails headlessly.** The `.pkg` installer needs
`sudo`, which needs an interactive password prompt — a headless/agent shell can't supply
one and the install aborts with `sudo: a password is required`. Don't retry it
programmatically; hand off immediately to the user to either run the command themselves
in their own Terminal, or install from the Mac App Store instead.

**2. The right-click "Always keep on this device" pin-local method needs OneDrive's
Finder Sync Extension separately enabled.** It's off by default post-install — the
right-click context menu on a OneDrive-synced folder shows only generic macOS items (no
cloud-status badges, no On-Demand controls) until it's turned on under **System
Settings → General → Login Items & Extensions → Extensions** (or **Privacy & Security →
Extensions → Added Extensions**, depending on macOS version). A simpler,
extension-independent fallback that pins everything in the account at once: OneDrive's
own **Preferences → General → Files On-Demand → "Download all OneDrive files now."**
For an account that only holds one small dedicated backing folder (the common case for
a vault's Sensitive plane), the account-wide toggle is the easier path — no menu-hunting
required.

**3. An unexplained, self-referential symlink appeared twice inside the backing
folder.** A symlink named after the OneDrive account (e.g. `OneDrive - <Org>`) pointing
back at the account's own root turned up inside the dedicated backing subfolder — after
it had already been removed once, with the user confirming they hadn't recreated it
deliberately either time. Root cause never identified (candidate theories: some
OneDrive client behavior tied to a brand-new Business account's first sync, or a stray
Finder action — inconclusive). It went undetected by `setup-sensitive-plane.sh`'s
`check` command, which previously only checked for zero-byte stubs, `.obsidian/`
exclusion, and the vault-not-inside-a-synced-root — none of which catch a symlink
pointing at its own ancestor. **Fixed in the same change that added this note:** `check`
now scans the backing directory for any symlink resolving to an ancestor of itself and
flags it.

**4. `link`'s `.gitignore` addition for the bare `_sensitive` symlink got silently
wiped by `/update-base`.** `link` used to append a `/_sensitive` line to the tracked
`.gitignore` so the symlink itself stays out of git. But `.gitignore` is base-owned —
`/update-base` overlays it wholesale (`git checkout FETCH_HEAD -- .gitignore`, no
merge) — so that vault-specific line was silently gone on the next base pull, and
`_sensitive` reappeared as an untracked path. Reproduced twice in a row: re-added the
line by hand, ran `/update-base` again for an unrelated reason, and it was wiped again.
**Fixed in the same change that added this note:** `link` now writes that exclusion to
`.git/info/exclude` instead — git-local, never tracked, so no overlay of tracked files
can ever touch it again. The catch this introduces: because the rule now lives in a
hidden file, `unlink` must clear it symmetrically — a lingering `/_sensitive` line
excludes the *whole* directory once `_sensitive/` is a plain folder again, defeating the
base `.gitignore`'s `!_sensitive/.gitkeep` / `!_sensitive/README.md` re-includes (git
can't re-include a path under an excluded parent), so the folder would stop shipping its
placeholders. `unlink` now removes the line it `link` added, so the round-trip is clean.

## Context

Setting up the Sensitive plane for a new topic vault: fresh OneDrive install (no prior
client on the machine), fresh Microsoft 365 Business account, `_sensitive/` linked to a
dedicated backing subfolder via `setup-sensitive-plane.sh link`.

## Implication

For the next OneDrive-backed `/setup-sensitive-plane` run: expect all four. Hand off
the `brew` install rather than retrying it; default to the Files-On-Demand
account-wide toggle instead of hunting for the Finder-extension right-click option
unless the account holds other folders that shouldn't be pinned too; run
`setup-sensitive-plane.sh check` after linking and again after any GUI interaction with
the OneDrive app — it now catches gotcha 3 automatically; and gotcha 4 needs no action
at all going forward — `link` already writes to the right place. A vault linked
*before* this fix should manually move its `/_sensitive` line from `.gitignore` to
`.git/info/exclude` once (as this session did for the vault that surfaced the bug).
