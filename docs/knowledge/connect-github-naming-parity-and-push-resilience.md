---
type: correction
base_seed: true
tags: [connect-github, github, git, push, mcp, naming, gotcha]
confidence: high
created: 2026-07-02
source: connecting a new topic vault to GitHub via connect-github.sh
---

# `connect-github.sh`: naming parity with the MCP label, and push resilience

Two gaps found running `connect-github.sh` for real on a fresh vault, both fixed in the
same change that added this note.

**1. Default repo name didn't match the vault's MCP connection name.** The script
defaulted `REPO_NAME` to `basename "$PWD"` (the bare vault folder name, e.g.
`puma-peak`), but the assistant already addresses the vault via its MCP label
(`obsidian-<slug>`, e.g. `obsidian-puma-peak` — set by `add-vault.sh`/`setup.sh` at
creation time). The two names diverged by default, so "the repo on GitHub" and "the
connection the assistant calls it by" didn't match until a manual `gh repo rename`
after the fact. Fixed: the script now sources `lib.sh` and defaults `REPO_NAME` to
`lib_mcp_label "$(basename "$PWD")"` — reconstructing the same label without reading
any live MCP config. (Windows' `connect-github.ps1` still defaults to the bare folder
name — there's no per-vault MCP label to match yet, since `add-vault.ps1`/multi-vault
isn't ported to Windows.)

**2. The push wasn't resilient to a transient HTTP/2 failure — which silently skipped
the auto-sync re-enable step too.** Hit `error: RPC failed; HTTP 400 curl 22 ... /
send-pack: unexpected disconnect while reading sideband packet` on an otherwise-tiny
repo (3.7MB, largest file 69KB — not a size issue; a known HTTP/2 flakiness pattern).
Retrying the exact same push manually with `-c http.version=HTTP/1.1 -c
http.postBuffer=524288000` succeeded immediately. Because the script runs under `set
-euo pipefail`, that failure aborted it right there — **before** it reached the later
step that turns Obsidian Git's auto-sync back on now that `origin` exists. The vault
was left half-configured: `origin` connected and pushed (via the manual retry, outside
the script), but auto-sync still off, needing the same `jq` patch applied by hand to
finish what the script would have done. Fixed: the script now retries a failed push
once with those same flags before giving up, so a transient failure no longer strands
it mid-flow.

## Context

Running `/connect-github`-equivalent steps (before the dedicated skill existed) for a
new topic vault, targeting a freshly created dedicated GitHub org for that vault's
confidential content.

## Implication

Going forward, `connect-github.sh`/`.ps1` default naming to match the MCP label and
retry the push automatically, so neither of these should recur. If a push still fails
after the automatic retry (a genuinely broken connection, not transient flakiness),
the script still exits before the auto-sync step — re-run it once connectivity is
restored, or apply the `jq` patch to `.obsidian/plugins/obsidian-git/data.json` by hand
to finish manually.
