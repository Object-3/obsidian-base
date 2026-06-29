---
name: install-skills
description: Install or refresh this vault's portable skills into your machine's user-scope so they work in EVERY project, not just inside the vault — and check whether your global copies have drifted from the vault. Use when someone says "make these skills available everywhere", "install my skills globally", "use these skills in other projects", "refresh my global skills", "are my installed skills up to date", "update my user-scope skills", or asks why a skill isn't showing up outside the vault. Drives .agents/scripts/sync-skills.sh and SELF-HEALS with tools when steps differ or fail.
---

# Install skills into user-scope (make them available everywhere)

Your job: install (or refresh, or status-check) the vault's **portable** skills into the
user-scope location each CLI tool reads, so they resolve in **any** project on this
machine — not only inside this vault. This is **additive**: the vault keeps its own
vendored copy (that copy is what cloud / Claude-Code-on-the-web sessions need), and
this step just *also* puts the skills where your local tools find them everywhere.

**What gets installed:** only the **vendored third-party skills** (the set in
`.agents/skill-sources.lock.json` — `kw-*`, writing, marketing, etc.). The vault-engine
skills (`onboard`, `setup-vault`, `update-base`, `offboard`, `normalize-vault`,
`install-skills`) are **not** installed globally — they only make sense inside a vault.

**Where they go:**
- `~/.claude/skills/` — Claude Code (also the Claude Desktop **Code tab**, and Conductor, via shared `$HOME`)
- `~/.agents/skills/` — OpenAI Codex's native user-scope

**It is non-destructive and reversible-but-retained:** a skill *you* installed yourself
is never overwritten, and offboarding the vault never removes these — once installed
they're yours (see the `offboard` skill).

## 0. Read the situation
- Confirm you're in a vault repo (a `.agents/skill-sources.lock.json` exists). If not,
  there's nothing to mirror from — tell the user to run this from inside their vault.
- Figure out what they want: **install/refresh** (default) or **status/check**.

## 1. Install or refresh
Two paths — pick based on intent, both are idempotent and safe to re-run:

```bash
# Fast, offline: mirror the vault's CURRENT committed skill set into user-scope.
# Use this for first-time install and most refreshes.
.agents/scripts/sync-skills.sh --mirror-only

# Latest: re-fetch skills from their upstream registries, then mirror.
# Use when the user wants the newest upstream versions (needs network).
.agents/scripts/sync-skills.sh --user-scope
```
Report what changed: the script prints how many skills it mirrored and which it
**skipped because they're the user's own**. Surface skips plainly — they're intentional,
not errors.

## 2. Status / drift check (offer-then-act — never auto-refresh)
When the user asks "are my global skills current?", compare the manifest's recorded
content hash against the vault's current lock, and flag a cross-vault writer:

```bash
MAN="${MIRROR_MANIFEST:-${XDG_CONFIG_HOME:-$HOME/.config}/obsidian-base/skill-mirror.json}"
[ -f "$MAN" ] || { echo "Not installed yet (no manifest at $MAN)."; exit 0; }
hash() { jq -S '.skills | sort' .agents/skill-sources.lock.json | { command -v sha256sum >/dev/null 2>&1 && sha256sum || shasum -a 256; } | cut -d' ' -f1; }
CUR="$(hash)"; HAVE="$(jq -r .lock_hash "$MAN")"; WROTE="$(jq -r .vault_path "$MAN")"; N="$(jq -r '.owned|length' "$MAN")"
echo "Installed: $N skill(s). Last written by vault: $WROTE"
[ "$CUR" = "$HAVE" ] && echo "Up to date." || echo "DRIFT: your global skills differ from this vault's current set."
[ "$WROTE" = "$(pwd)" ] || echo "NOTE: last written by a DIFFERENT vault — refreshing here will make this vault the owner."
```
- If **up to date**: say so; do nothing.
- If **drift** or **different-vault writer**: explain it, then **offer** to refresh (run
  step 1) — do not refresh without a yes.

## 3. Explain the model (so the user isn't surprised later)
Tell them, briefly:
- These skills are **machine-global now** — they work in every project, and they
  **stay even if you offboard this vault** (offboarding only removes the MCP wiring and
  the global rules block, never your skills).
- **Precedence:** your user-scope copy shadows the vault's in-repo copy locally
  (personal > project). Within one vault both come from the same registry so they match;
  if you keep **multiple vaults**, the last one you refreshed from wins — `--status`
  flags that.
- **Codex** reads `~/.agents/skills`; **Claude Code / Desktop Code tab / Conductor** read
  `~/.claude/skills`. (If a freshly installed personal skill doesn't *auto-trigger* in
  Claude Code, that's a known upstream quirk — it's still invocable by name.)
- **Consumer chat** (claude.ai chat, ChatGPT) can't be scripted; if they want a skill
  there, they upload its folder as a zip in that app's settings. Not something this skill does.

## Notes
- Idempotent — safe to re-run. When stuck, prefer reading `.agents/scripts/sync-skills.sh`
  (the `mirror_user_scope` function) and running its steps over guessing.
- The manifest (`{owned, lock_hash, vault_path, written}`) is the source of truth for
  which copies are *ours* (safe to refresh) vs *yours* (never touched).
- This skill is hand-authored and repo-local (not vendored, not in the lock);
  `sync-skills.sh` won't overwrite it, and `update-base` propagates it to the fleet.
