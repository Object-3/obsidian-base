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

**What gets installed:** only the **vendored third-party skills** — exactly the set in
`.agents/skill-sources.lock.json` (`kw-*`, writing, marketing, etc.). The vault-engine
skills — everything *not* in the lock (`onboard`, `setup-vault`, `update-base`,
`offboard`, `normalize-vault`, `ingest-pdf`, and `install-skills` itself) — are **not**
installed globally; they only make sense inside a vault.

**Where they go:**
- `~/.claude/skills/` — Claude Code (also the Claude Desktop **Code tab**, and Conductor, via shared `$HOME`)
- `~/.agents/skills/` — OpenAI Codex's native user-scope

**Where they do NOT go — say this out loud at completion, every time:** the mirror
does **not** reach **Claude Desktop's regular chat window** (the same product as
claude.ai chat). That surface has no folder-based skill loading; it takes skills only
as a **manual per-skill zip upload** via **Settings → Capabilities**. A user who
restarts Desktop expecting the mirrored skills in the chat window will be confused —
head that off in your completion summary. For that surface, see step 4 (zip exports).

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

**At completion, state the reach prominently** (the script also prints it):
- **Reaches:** Claude Code (CLI), Claude Desktop's **Code tab**, Conductor, Codex.
- **Does NOT reach:** Claude Desktop's **regular chat window** — zip upload only
  (Settings → Capabilities). Offer step 4 if the user wants skills there.

## 2. Status / drift check (offer-then-act — never auto-refresh)
When the user asks "are my global skills current?", run the read-only status check. It
compares the manifest's recorded content hash against the vault's current lock and flags
a cross-vault writer — without writing anything:

```bash
.agents/scripts/sync-skills.sh --status
```
Exit-code contract — every applicable condition prints, and the exit is the **lowest**
applicable nonzero code (most actionable first):
- **0** — everything clean.
- **1** — mirror **stale**: this vault's portable set changed since the mirror was
  written.
- **2** — mirror **not installed** yet (or nothing to compare against).
- **3** — chat-surface **zip export(s) stale or no longer vendored** (step 4).
- **4** — a **pinned skill source is off its pin** (fell back on the last sync).
- **5** — **cannot evaluate**: the lock exists but is corrupt (not valid JSON).

It also prints the owned count, when the mirror was last written, and — if another
vault wrote it last — a last-writer-wins note. What to do per code:
- **0**: say so; do nothing.
- **1** or a **different-vault writer**: explain it, then **offer** to refresh (run
  step 1) — do not refresh without a yes.
- **3** (stale exports): offer to re-run the export (step 4) for that surface; remind
  the user the re-upload into the app is manual. A skill flagged "no longer vendored"
  is different: the fix is deleting the uploaded zip in the app (the manifest entry
  clears itself on the next export).
- **4** (pin fallback, recorded in the lock's `fallback_from`): the fix is correcting
  the `ref` in `.agents/skill-sources.json` and re-running the sync.
- **5**: the lock file is corrupt — re-run the sync, or restore
  `.agents/skill-sources.lock.json` from git.

## 3. Explain the model (so the user isn't surprised later)
Tell them, briefly:
- These skills are **machine-global now** — they work in every project, and they
  **stay even if you offboard this vault** (offboarding only removes the MCP wiring and
  the global rules block, never your skills).
- **Precedence:** your user-scope copy shadows the vault's in-repo copy locally
  (personal > project). Within one vault both come from the same registry so they match;
  if you keep **multiple vaults**, the last one you refreshed from wins — the status
  check (`sync-skills.sh --status`, step 2) flags that.
- **Codex** reads `~/.agents/skills`; **Claude Code / Desktop Code tab / Conductor** read
  `~/.claude/skills`. (If a freshly installed personal skill doesn't *auto-trigger* in
  Claude Code, that's a known upstream quirk — it's still invocable by name.)
- **Consumer chat** (claude.ai chat / Claude Desktop's chat window, ChatGPT) can't be
  scripted — no folder loading, no upload API. If they want skills there, use the zip
  exports in step 4: this skill generates the zips and tracks their staleness, but the
  **upload itself stays manual** in that app's settings.

## 4. Chat-surface zip exports (optional — Claude Desktop chat, etc.)

When the user wants the skills in a **chat-only surface** (Claude Desktop's regular
chat window today; any future zip-import app), generate per-skill zips and record
them so staleness is visible later:

```bash
# Default surface is claude-desktop-chat; zips land under
# ~/.config/obsidian-base/skill-exports/<surface>/ unless --export-dir= is given.
.agents/scripts/sync-skills.sh --export-zips --surface=claude-desktop-chat
```

- Each export writes a manifest entry `{surface, skill, hash, written}` into the same
  mirror manifest, keyed by a content hash of the vendored skill.
- Tell the user the **upload is manual**: in Claude Desktop chat, Settings →
  Capabilities → Skills, upload each zip. There is no API to automate this.
- The loop closes via `--status` (step 2): when a vendored skill later changes
  (`update-base`, `--user-scope` refresh), the status check flags exactly which
  uploaded zips are stale — "re-export and re-upload: …" — instead of letting the
  chat-surface copy silently fork from the vault.
- The surface name is generic: a future zip-import app is just another
  `--surface=<name>`, no redesign needed.

## Notes
- Idempotent — safe to re-run. When stuck, prefer reading `.agents/scripts/sync-skills.sh`
  (the `mirror_user_scope` function) and running its steps over guessing.
- **Self-heal means working around a step, not rewriting the engine.** If the script
  itself is buggy, do **not** edit `sync-skills.sh` in this vault and do **not** open a
  PR against the base repo — **file a GitHub issue** against the upstream base
  (`.agents/.base-url` if set, else `Object-3/obsidian-base`) with the error and your
  proposed fix in the body. See *Engine bugs & improvements found in a derived vault*
  in `AGENTS.md`.
- The manifest (`{owned, lock_hash, vault_path, written, exports}`) is the source of
  truth for which copies are *ours* (safe to refresh) vs *yours* (never touched), and
  — via `exports` — which skills were zip-exported for which chat surface.
- This skill is hand-authored and repo-local (not vendored, not in the lock);
  `sync-skills.sh` won't overwrite it, and `update-base` propagates it to the fleet.
