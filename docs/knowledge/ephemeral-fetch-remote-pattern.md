---
title: "Ephemeral fetch remotes: a dedicated, reclaimable name beats a standing one"
type: playbook
status: active
base_seed: true
tags: [plumbing, git, update-base, setup, remote-safety, security]
confidence: high
created: 2026-07-02
updated: 2026-07-02
source: ce-code-review of PR #26 (make the base git remote ephemeral) — empirically verified
related:
  - "[[vendor-skills-into-repo-for-cloud-sessions]]"
  - "[[vet-vendored-skills-and-avoid-sync-clobber]]"
---

# Ephemeral fetch remotes: a dedicated, reclaimable name beats a standing one

`update-base.sh` fetches the shared engine from the upstream template over a git
remote. Leaving that remote **standing** is a data-leak footgun: once the vault also
has a private `origin`, Obsidian Git's remote picker will happily offer the template
remote, and one mis-pick pushes **private notes into the public template**. Making the
remote ephemeral is the fix — but *how* you make it ephemeral matters.

## TL;DR

- **Don't keep a standing remote to a public upstream** in a repo that will later gain a
  private `origin`. Add the fetch remote only for the fetch; remove it on exit.
- **A bare `EXIT` trap is enough for interrupts, not for kills.** Empirically (bash 3.2,
  macOS), a terminal Ctrl-C (SIGINT to the whole process group) **and** SIGTERM both fire
  the `EXIT` trap and clean up. Only **SIGKILL / power-loss** can't be trapped — so design
  for that case explicitly rather than by trapping more signals.
- **Use a dedicated, reserved remote name** the script owns end to end (here:
  `base-ephemeral`), not the user-facing `base`. Reclaim any stray one at the **start** of
  every run, add it for the fetch, remove it on exit. This makes a SIGKILL orphan
  **self-healing** — the next run deletes it — instead of stranding it.
- **Never mutate the user's own remote.** Read a legacy `base` remote's URL for
  resolution, but never `add` / `remove` / `set-url` it. That preserves back-compat for
  power users *and* removes the accidental "repoint their remote" side effect.

## Why a shared name fails, and the two traps it hides

The tempting first cut adds the ephemeral remote under the real name `base` and only
removes it "if this run added it" (to protect a legacy vault that deliberately kept one).
Two failure modes hide in that heuristic:

1. **SIGKILL orphan.** No trap catches SIGKILL, OOM, or power-loss. A kill during the
   (short) fetch window leaves `base` standing.
2. **The orphan becomes permanent.** The very next run sees a pre-existing `base` and —
   unable to tell a crash-orphan from a deliberately-kept remote — *preserves* it. The
   safety guarantee silently, permanently reverts, next to the private `origin`.

A **dedicated name** dissolves both. `base-ephemeral` is unambiguously the script's own:
a stray one is *always* a leftover, so reclaiming it at start-of-run is safe, and a
user's `base` is never touched. Net effect: crash-orphan self-healing, perfect
back-compat, **no new state file** (no sentinel, no gitignore entry), and the
"accidentally repointed a legacy remote via `set-url`" bug disappears for free.

Shape:

```sh
EPHEMERAL_REMOTE="base-ephemeral"
cleanup() { git remote remove "$EPHEMERAL_REMOTE" 2>/dev/null || true; }
trap cleanup EXIT
git remote remove "$EPHEMERAL_REMOTE" 2>/dev/null || true   # reclaim a crash/SIGKILL orphan
git remote add "$EPHEMERAL_REMOTE" "$RESOLVED_URL"
git fetch -q --depth 1 "$EPHEMERAL_REMOTE" "$REF"           # downstream reads FETCH_HEAD, not the remote name
```

Because everything downstream reads `FETCH_HEAD` (not a `base/<ref>` tracking ref),
renaming the remote is fully contained to these lines.

## Caveats

- **The fetch window still exists.** Between `add` and `remove` the ephemeral remote is
  briefly present, so a picker mis-pick during a running fetch is still theoretically
  possible — but it's seconds long, self-heals next run, and no longer becomes permanent.
- **`base-ephemeral` is reserved.** The start-of-run reclaim will delete a remote of that
  name, so don't hand-create one. Document it.
- **The persisted config replaces the remote.** With no standing remote, a fork/custom
  base URL must live somewhere the next run can read it — here, a tracked
  `.agents/.base-url` file (mind credentials in it; keep the resolution precedence in one
  place). See [[vendor-skills-into-repo-for-cloud-sessions]] for how base updates flow.
- **Verify the signal behavior on your target shells.** The SIGINT/SIGTERM-fires-EXIT
  result above was reproduced on bash 3.2; treat it as the baseline, but re-check if you
  rely on it under an unusual shell or `wait`-heavy control flow.
