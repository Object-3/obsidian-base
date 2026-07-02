---
title:   "Activity Log"
type:    index
status:  active
tags:    [{{PRIMARY_TAG}}, log]
created: 2026-06-27
updated: 2026-06-29
---

# Log

Append-only record of what happened and when — note ingests, major edits, syncs,
lint passes. Newest at the bottom. Prefix entries with `## [YYYY-MM-DD] <type> | <summary>`.

## [2026-06-27] init | Vault created from obsidian-base-vault template
- Agnostic agent layer in place: `AGENTS.md` contract, `.agents/skills` (vendored,
  with `.claude`/`.codex` pointers), Karpathy LLM-Wiki backbone (`index.md`, this
  `log.md`).
- Next: run `.agents/scripts/init-vault.sh` to customize, then start adding notes.

## [2026-06-29] feat | User-scope skill mirror (engine)
- Added an opt-in mirror of the vendored portable skills into user-scope
  (`~/.claude/skills`, `~/.agents/skills`) so they work in every project, not just the
  vault. Surfaces: `sync-skills.sh --user-scope`/`--mirror-only`, the `/install-skills`
  skill, onboarding opt-in (`MIRROR_SKILLS`), offboard retain-and-inform, `update-base`
  propagation + refresh nudge. Vendoring + cloud path unchanged. See [[userscope-skill-mirror]].

## [2026-06-29] fix | Harden user-scope mirror + decouple from compound-knowledge plugin
- `sync-skills.sh`: stage the user-scope mirror in the target's **parent** dir, not the
  skills root, so a host's skill scanner never catches a half-written `.tmp` dir
  mid-rename; smoke test grows a guard (now 13/13).
- Disabled the `compound-knowledge` plugin in this repo (`.claude/settings.json`) so the
  vendored dash-form `kw-*` are the single invocation — kills the `kw:` / `compound-knowledge:`
  menu duplicate. Documented the two knowledge planes (`kw-*` vs `ce-*`) in `AGENTS.md`.
  See [[kw-and-ce-knowledge-planes]].

## [2026-07-02] fix | Vault-creation hygiene + Sensitive-plane symlink check
- `setup.sh`/`add-vault.sh`: personalize (`init-vault.sh`) *before* the initial commit,
  not after — a new vault's history now starts with real values instead of
  `{{PLACEHOLDER}}` tokens. `git init -b main` explicitly, instead of inheriting the
  machine's `init.defaultBranch`. See [[fresh-vault-uncommitted-personalization-and-branch-drift]].
- `update-base.sh`: "Next steps" messaging is now origin-aware — only recommends
  branch+PR when `origin` exists; says "commit directly" for a vault with no `origin`
  remote yet.
- `setup-sensitive-plane.sh check`: now scans the backing directory for symlinks that
  resolve to an ancestor of themselves (e.g. a stray shortcut back to a cloud
  provider's account root) and flags them — previously undetected. Doc updated with the
  Files-On-Demand account-wide-toggle fallback and a note that `brew install --cask`
  needs a human hand-off headlessly. See [[onedrive-sensitive-plane-setup-gotchas]].
- All three found while setting up a second topic vault end to end (`/add-vault` →
  `/update-base` → `/setup-sensitive-plane`) in a downstream vault.
## [2026-07-02] fix | Harden the ephemeral base remote (code-review follow-ups) + compound learning
- `update-base.sh`: dedicated `base-ephemeral` fetch remote — reclaimed at start-of-run,
  removed on exit; the user's/legacy `base` is now read-only, so a SIGKILL orphan self-heals
  and the old `set-url` repoint side effect is gone. Whitespace-only `.agents/.base-url` now
  falls through; `setup.sh`/`add-vault.sh`/`setup.ps1` clear a stowaway `.base-url` before writing.
- `test-add-vault-integration.sh`: 14 → 20 checks (crash-orphan reclaim, legacy-preserve,
  happy-path rc assertion, fetch-failure trap cleanup).
- New learning [[ephemeral-fetch-remote-pattern]]. Surfaced follow-ups filed as
  Object-3/obsidian-base#30 (credential scrub), #31 (URL/precedence dedupe), #32 (docs).

## [2026-07-02] fix | Vault-creation hygiene: code-review follow-ups (post-merge hardening)
- `setup.sh`/`add-vault.sh`/`setup.ps1`: `git init -b main` now falls back to
  `git init` + `symbolic-ref` for git < 2.28 (was a hard abort right after `rm -rf .git`);
  and a placeholder guard warns loudly if `{{PLACEHOLDER}}` tokens survive personalization
  instead of silently committing them as a false success. `setup.ps1` brought to parity
  (deferred commit + `-b main` + guard, gated on a fresh-vault flag).
- `test-add-vault-integration.sh`: 20 → 22 checks — asserts the first commit is on `main`
  and holds real values (no `{{ }}`), which the prior test could not distinguish from the bug.
- Cross-linked [[fresh-vault-uncommitted-personalization-and-branch-drift]] and
  [[onedrive-sensitive-plane-setup-gotchas]] (each ↔ the other + [[ephemeral-fetch-remote-pattern]]).

## [2026-07-02] fix | Sensitive-plane `.gitignore` line survives `/update-base`
- `setup-sensitive-plane.sh link` used to append the bare `/_sensitive` ignore rule (for
  the symlink form of `_sensitive/`) to the tracked `.gitignore` — but `.gitignore` is
  base-owned and `/update-base` overlays it wholesale (checkout, no merge), so that line
  was silently wiped on the next base pull and the symlink reappeared as untracked.
  Reproduced twice in one downstream-vault session: fixed by hand, then wiped again by an
  unrelated `/update-base` run minutes later.
- Fix: `link` now writes the exclusion to `.git/info/exclude` instead — git-local, never
  tracked, so no overlay of tracked files can ever touch it again. Considered baking
  `/_sensitive` permanently into this repo's own tracked `.gitignore` instead, but
  rejected it: a bare `/_sensitive` pattern would exclude the whole directory whenever
  `_sensitive/` is still a plain folder (the default, pre-`link` state), breaking the
  existing `_sensitive/*` + `!_sensitive/.gitkeep`/`!_sensitive/README.md` negation
  exceptions that ship the folder with every fresh vault (git can't re-include a path
  under an excluded parent directory).
- Follow-up (`unlink` symmetry): since the rule now lives in the hidden `.git/info/exclude`,
  `unlink` now removes the `/_sensitive` line it `link` added. Otherwise, restoring
  `_sensitive/` to a plain directory would leave a `/_sensitive` line excluding the whole
  folder — the exact negation-breakage above, just relocated to a file the user won't find
  via `git status`. Verified with a `link`→`unlink` round-trip: `.gitkeep` is re-includable
  after unlink.
- Extended [[onedrive-sensitive-plane-setup-gotchas]] with this as gotcha 4.
