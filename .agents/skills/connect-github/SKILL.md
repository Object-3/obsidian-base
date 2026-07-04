---
name: connect-github
description: Connect an existing LOCAL vault to GitHub for backup/sync -- creates a private repo (under the user's account or an org), pushes the vault, sets it as `origin`, and turns on Obsidian Git's auto-sync now that a real remote exists. Use when the user says "connect this vault to GitHub", "back this up to GitHub", "push this vault", "set up cloud backup for my vault", "I want this on GitHub", or after `/add-vault`/`/onboard` when they're ready to move a local-only vault off single-machine risk. Drives setup/connect-github.sh (macOS/Linux) or .ps1 (Windows) and owns the judgment the script can't: owner selection (personal vs. a dedicated org, especially for confidential/deal-specific vaults), repo naming (matches the vault's MCP label by default), and visibility.
---

# Connect a vault to GitHub

Your job: get an existing **local-only** vault durably backed up and synced via GitHub,
without exposing confidential material, and without leaving naming or state
inconsistent with how the vault is already wired locally.

This is **optional and opt-in** — a local vault works fully without GitHub (see
`AGENTS.md`: "Local-first"). Only run this when the user actually wants off-machine
backup/sync.

The mechanical core is `setup/connect-github.sh` (or `.ps1` on Windows) — idempotent,
safe to re-run. You own the judgment calls it can't make for you.

## 0. Orient

- Confirm this is a vault with its own git history, not mid-way through some other git
  operation — `git rev-parse --is-inside-work-tree`.
- Check `git remote -v`: if `origin` already exists, this is a re-run (the script just
  pushes to it) — skip straight to step 3.
- Read `.agents/vault-profile.md` — its primary tag/tagline tell you whether this vault
  holds confidential/deal-specific content, which matters for step 1.

## 1. Choose the owner (the judgment call)

Ask, or infer from context, whether the repo should live under:

1. **The user's personal GitHub account** — fine for personal knowledge bases.
2. **An existing org they belong to** — `gh api user/orgs` lists them. Only reach for
   an org that's actually the right home for this vault's content — **don't default to
   an unrelated org just because it exists.** A vault holding one specific
   confidential engagement's material (e.g. a PE deal, a client project) deserves its
   *own* dedicated org or the user's personal account, not a broader org used for
   unrelated ventures.
3. **A brand-new dedicated org** — if the vault is confidential/deal-specific and no
   existing org fits, ask whether they want to create one first
   (`github.com/account/organizations/new` is a manual step); once created,
   `gh api orgs/<name>` confirms it's reachable before you proceed.

**Visibility defaults to private** — keep it that way unless the user explicitly wants
a public repo (rare; the vault's Shareable-plane content is still theirs even if
public — `_sensitive/` never reaches git regardless).

## 2. Repo naming (parity with the MCP connection)

The script defaults the repo name to the vault's **MCP label** (`obsidian-<slug>`,
derived via `lib_mcp_label`) — the same name the assistant already uses to address this
vault. This gives naming parity between "the repo on GitHub" and "the connection the
assistant calls it by," with no manual rename needed afterward. Let the default stand
unless the user has a specific reason to override it.

(Windows: `connect-github.ps1` still defaults to the bare folder name — Windows doesn't
yet have per-vault MCP labels, since `add-vault.ps1`/multi-vault isn't ported there. No
action needed; just don't expect the same parity there yet.)

## 3. Run it

```
cd <vault> && ./setup/connect-github.sh       # macOS/Linux
cd <vault> && ./setup/connect-github.ps1      # Windows
```

Non-interactive (agent-driven), pass the answers from steps 1–2 as env vars:
```
OWNER="<owner>" REPO_NAME="<name>" VISIBILITY="private" ./setup/connect-github.sh
```

The script:
1. Confirms `gh` is installed and authenticated (installs/prompts login if not).
2. Creates the repo (or, if `origin` already exists, just pushes to it) and sets it as
   `origin`.
3. Turns on Obsidian Git's auto-sync (`autoSaveInterval`/`autoPullInterval`,
   `autoPullOnBoot`, `autoBackupAfterFileChange`, `disablePush`) now that a real remote
   exists — it ships OFF in a fresh vault specifically so nothing auto-pushes before
   `origin` is connected.
4. Retries the push once over HTTP/1.1 with a larger post buffer if the first attempt
   hits a transient failure (`RPC failed; HTTP 400 ... unexpected disconnect` is a known
   flakiness pattern, not usually a real problem — seen on a 3.7MB repo).

## 4. Verify

- `git remote -v` shows `origin` pointing at the right owner/repo.
- `gh repo view <owner>/<repo> --json visibility,defaultBranchRef` — confirms private
  (unless intentionally public) and `main` as the default branch.
- `git fetch origin` succeeds cleanly.
- `.obsidian/plugins/obsidian-git/data.json` has `autoPullOnBoot: true` and
  `disablePush: false` — confirms step 3 above actually completed. **If the script's
  push failed and its retry also failed** (rare, but possible on a genuinely broken
  connection), the script exits before reaching this step under `set -euo pipefail` —
  re-run the script once connectivity is fixed, or apply the same `jq` patch by hand.

## Notes

- Hand-authored, repo-local skill — not vendored, so `sync-skills.sh` won't overwrite
  it; `update-base` propagates it to downstream vaults (`setup/` is in its overlay
  paths).
- Pairs with `/add-vault` (creates the local vault this connects) and
  `/setup-sensitive-plane` (the confidential plane this repo's git history never
  touches, regardless of what GitHub owner it lives under).
- If the vault ever needs to move to a different owner/repo later: `git remote set-url
  origin <new-url>`, plus optionally `gh repo rename` on the GitHub side — both safe,
  reversible operations; GitHub keeps a redirect from the old name/location for a
  while.
