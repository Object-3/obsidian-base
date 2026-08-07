---
name: doctor
description: Run a health check across this vault's machine-level wiring and structure, then offer to repair whatever drifted — consent-gated, never auto-applied. The flagship check is MCP wiring (every vault reachable from every AI client on the plugin /mcp/ endpoint, with the abandoned uvx mcp-obsidian server eradicated); it also checks frontmatter/lint health, skills freshness, and whether the vault's base engine is behind the upstream base (one git ls-remote against the .agents/.base-sync stamp — use for "is my vault's engine up to date", "am I behind the base", "check base staleness"). Use when the user says "run the doctor", "doctor the vault", "check my vault health", "why can't my assistant see a vault", "an MCP connection is broken / off air / erroring", "my vaults are out of sync across apps", "reconnect my vaults", "fix my MCP", or after /update-base pulls in changes that need reconciling.
---

# Vault doctor

A thin health-check + repair **conductor**. It runs a series of independent checks,
reports one summary (`✓ ok` / `⚠ drift` / `✗ broken`), then **offers** to apply the
fixes. It never repairs silently — surface the findings, get a yes, then act (matching
this vault's offer-then-act, value-gated posture). Each check wraps an existing script,
so the doctor stays a conductor, not a second implementation.

This touches **machine-level config** (MCP client wiring, plugin settings), not notes —
so it's safe to run anytime and changes nothing until you confirm.

## How to run it

Work top to bottom. Run every check in **report mode first**, print the combined
summary, then offer the repairs that apply. Only run a fix the user accepts.

### 1. MCP wiring (flagship) — every vault reachable from every AI client

```bash
./setup/sync-mcp.sh            # CHECK: reports drift, changes nothing (exit 3 = drift)
```

This is the convergence doctor. It discovers the vaults on this machine (from
Obsidian's own registry, keeping only the vaults created from obsidian-base — those
that carry `.agents/vault-profile.md`), and verifies that **every** vault is wired into **every**
installed AI client (Claude Desktop, Claude Code, Codex) on the **Local REST API
plugin's own `/mcp/` endpoint**. It flags three things:

- a vault **missing** from a client (per-surface drift — the classic "shows in Claude
  Code but not Claude Desktop"),
- a vault still wired to the **abandoned `uvx mcp-obsidian`** server (which hardcodes
  port 27124, so every 2nd+ vault silently fails to authenticate — the root cause of a
  vault that connects but errors `40101` / reads "off air"),
- a vault whose **loopback HTTP server is off**, so `/mcp/` can't answer.

**Repair (on consent):**
```bash
./setup/sync-mcp.sh --fix           # converge + eradicate mcp-obsidian (backs up configs first)
```
If it enables a vault's loopback server, it will name the vault(s) to **reload in
Obsidian** (close & reopen, or toggle the Local REST API plugin) so the port binds.
Then tell the user to **restart their assistant** (quit/reopen Claude Desktop; start a
fresh Claude Code / Codex session) to pick up the rewired connections. A vault is only
reachable while its Obsidian window is **open**.

### 2. Frontmatter & structure lint

```bash
.agents/scripts/lint-vault.sh        # reports notes missing the frontmatter standard / unparseable YAML
```
If it flags notes worth keeping, **offer** `/normalize-vault` (consent-gated; never
rewrite human prose silently). Leave `raw/` and `_sensitive/` untouched.

### 3. Skills freshness

```bash
.agents/scripts/sync-skills.sh       # re-vendor skills + repair broken pointers + regenerate INDEX
```
Run this if the vendored skills are stale or `.claude/skills` / `.codex/skills`
pointers are broken. If the user also installed skills into user-scope, **offer**
`/install-skills` to refresh the global copies (they don't auto-update).

### 4. (Optional) base freshness & sensitive plane

- **Base:** measure whether this vault's engine is behind the upstream base — one
  cheap remote call, no fetch, no working-tree mutation:

  ```bash
  url=$( [ -s .agents/.base-url ] && tr -d '[:space:]' <.agents/.base-url \
         || echo https://github.com/Object-3/obsidian-base.git )
  ref=$( [ -s .agents/.base-ref ] && tr -d '[:space:]' <.agents/.base-ref || echo main )
  if printf '%s' "$ref" | grep -qE '^[0-9a-f]{7,40}$'; then
    remote_sha="$ref"   # pinned to a raw SHA — the pin itself is the target
  else
    remote_sha=$(GIT_TERMINAL_PROMPT=0 git -c credential.helper= ls-remote "$url" \
                   "refs/heads/$ref" "refs/tags/$ref^{}" "refs/tags/$ref" 2>/dev/null \
                 | tail -1 | cut -f1)
  fi
  local_sha=$(cut -d' ' -f1 .agents/.base-sync 2>/dev/null || true)
  partial=$(cut -d' ' -f4 .agents/.base-sync 2>/dev/null || true)
  ```

  (The `refs/heads/… refs/tags/…^{}` spellings matter: a bare `git ls-remote "$url"
  "$ref"` returns **two lines** for an annotated tag — permanent false drift — and
  the `^{}` peel plus `tail -1` picks the commit SHA. `GIT_TERMINAL_PROMPT=0` +
  `-c credential.helper=` make a private/unreachable fork fail fast instead of
  hanging on a credential prompt.)

  `.agents/.base-sync` is the stamp `update-base.sh` writes on every run
  (`<sha> <ref> <iso-timestamp>`, plus an optional 4th field `partial-skills` when
  that run had to skip the base-authored skill overlay — no `jq`, or an unreadable
  base lock). Interpret:
  - both SHAs non-empty and **equal** → `✓ ok` — engine current as of the stamp's
    timestamp (report the date, third field of the stamp). **Except** if `partial`
    is `partial-skills` → `⚠ drift` — the last sync skipped base-authored skills;
    offer to re-run `/update-base` with `jq` installed.
  - **pinned to a raw SHA** (`ref` matched the hex test above): not stale by
    definition — the vault deliberately froze its base. Stamp SHA matching the pin
    (prefix match — pins may be short) → `✓ ok (pinned)`; mismatch → `⚠ drift` —
    the pin changed without a sync; offer `/update-base`.
  - both non-empty and **different** → `⚠ drift` — the base has moved since the last
    sync; **offer** `/update-base` (engine change → branch + PR, consent-gated as
    always). Compare **SHAs only** — never `git rev-list --count`: update-base
    fetches `--depth 1` and template instances share no history with the base, so
    there is no ancestry to count.
  - `remote_sha` empty (offline / unreachable base) or `local_sha` empty (no stamp —
    the vault has never run `/update-base` since the stamp shipped) → **degrade
    silently**: report the row as `base | unknown (no stamp / offline)` and move on;
    never fail the doctor over it.

  Don't run `/update-base` unprompted.
- **Sensitive plane:** if `_sensitive/` is meant to be cloud-backed and its symlink is
  missing/broken, offer `/setup-sensitive-plane` to repair it.

## Reporting

End with a compact table — one row per check: `check | status | what it means | fix
offered`. Lead with plain language (spell out MCP = Model Context Protocol on first
use). If everything is `✓ ok`, say so in one line and stop — don't invent work.

## Notes

- **Consent-gated:** report → offer → fix. Never apply a repair the user didn't accept.
- **Repairs fix wiring/state, never engine code.** If a check reveals the bug is in a
  base-owned script/hook/skill itself, don't edit it here and don't open a PR upstream —
  **file a GitHub issue** against the base repo (`.agents/.base-url` if set, else
  `Object-3/obsidian-base`) per *Engine bugs & improvements found in a derived vault*
  in `AGENTS.md`.
- **Extensible:** new checks slot in as additional numbered sections that wrap a script
  and report `ok/drift/broken` — keep the doctor a conductor, not a monolith.
- **After /update-base:** only nudge toward running the doctor when the sync actually
  brought in something that needs reconciling (e.g. the MCP wiring changed) — not on
  every update.
