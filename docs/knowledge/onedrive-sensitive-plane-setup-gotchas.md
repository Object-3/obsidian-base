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
---

# Setting up `_sensitive/` on OneDrive: three recurring gotchas

Backing a vault's `_sensitive/` plane with Microsoft 365 / OneDrive via
`/setup-sensitive-plane` surfaced three friction points. None are blockers, but each
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

## Context

Setting up the Sensitive plane for a new topic vault: fresh OneDrive install (no prior
client on the machine), fresh Microsoft 365 Business account, `_sensitive/` linked to a
dedicated backing subfolder via `setup-sensitive-plane.sh link`.

## Implication

For the next OneDrive-backed `/setup-sensitive-plane` run: expect all three. Hand off
the `brew` install rather than retrying it; default to the Files-On-Demand
account-wide toggle instead of hunting for the Finder-extension right-click option
unless the account holds other folders that shouldn't be pinned too; and run
`setup-sensitive-plane.sh check` after linking and again after any GUI interaction with
the OneDrive app — it now catches gotcha 3 automatically.
