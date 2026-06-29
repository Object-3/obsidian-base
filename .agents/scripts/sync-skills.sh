#!/usr/bin/env bash
# Vendor curated GitHub-hosted Agent Skills into the repo so they load in every
# session of every agent — Claude Code, OpenAI Codex, and any tool that reads the
# open SKILL.md standard — including ephemeral cloud containers that do NOT
# auto-install marketplace/GitHub skills.
#
# AGNOSTIC-FIRST LAYOUT
#   .agents/skills/   canonical skills   (real files, committed)   <- source of truth
#   .agents/agents/   canonical subagents
#   .claude/skills -> ../.agents/skills   (pointer for Claude Code)
#   .codex/skills  -> ../.agents/skills   (pointer for OpenAI Codex)
#   .claude/agents -> ../.agents/agents
#
# Pointers are symlinks where the OS supports them, and AUTOMATICALLY fall back to
# real copies where it does not (notably Windows checkouts without symlink
# support / Developer Mode). Re-running this script repairs/refreshes everything,
# so the Windows copy path needs no manual thought — just run the sync.
#
# Source of truth: .agents/skill-sources.json
# Usage:           .agents/scripts/sync-skills.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MANIFEST="$ROOT/.agents/skill-sources.json"
LOCAL_MANIFEST="$ROOT/.agents/skill-sources.local.json"
CANON_SKILLS="$ROOT/.agents/skills"
CANON_AGENTS="$ROOT/.agents/agents"
LOCK="$ROOT/.agents/skill-sources.lock.json"
STAMP="$ROOT/.agents/.skills-last-sync"
INDEX="$CANON_SKILLS/INDEX.md"
LOCKDIR="$ROOT/.agents/.sync-skills.lock"   # concurrency guard (mkdir-based, portable)

# ---- user-scope mirror (opt-in) ------------------------------------------
# Mirroring also copies the vendored PORTABLE skills into each CLI tool's
# USER-SCOPE dir, so they resolve in every project on this machine — not just
# this vault. Strictly additive: the in-repo vendoring below is untouched, and
# cloud/web sessions (which only see the repo checkout) are unaffected.
# Enable with --user-scope, --mirror-only (mirror without re-fetching), or
# MIRROR_USER_SCOPE=1. The *_USER_SKILLS / MIRROR_MANIFEST vars are overridable
# (handy for tests; point them at a temp dir to avoid touching real ~/.).
CLAUDE_USER_SKILLS="${CLAUDE_USER_SKILLS:-$HOME/.claude/skills}"   # Claude Code (also Desktop Code tab + Conductor via shared $HOME)
CODEX_USER_SKILLS="${CODEX_USER_SKILLS:-$HOME/.agents/skills}"     # OpenAI Codex native user-scope
MIRROR_MANIFEST="${MIRROR_MANIFEST:-${XDG_CONFIG_HOME:-$HOME/.config}/obsidian-base/skill-mirror.json}"
USER_SCOPE=""; MIRROR_ONLY=""
for _arg in "$@"; do case "$_arg" in
  --user-scope)  USER_SCOPE=1 ;;
  --mirror-only) USER_SCOPE=1; MIRROR_ONLY=1 ;;
esac; done
[ -n "${MIRROR_USER_SCOPE:-}" ] && USER_SCOPE=1

# tool pointer dirs -> what they point at (relative target | canonical abs)
POINTERS=(
  ".claude/skills|../.agents/skills|$CANON_SKILLS"
  ".codex/skills|../.agents/skills|$CANON_SKILLS"
  ".claude/agents|../.agents/agents|$CANON_AGENTS"
)

command -v jq   >/dev/null || { echo "jq is required"   >&2; exit 1; }

# Mirror the vendored PORTABLE set (the lock's .skills[]) into each CLI tool's
# user-scope dir. Non-destructive: a same-named skill we did NOT install is never
# overwritten. Ours-only: refresh touches only names in our manifest. Reads the set
# from the lock (authoritative, == the hand-authored-excluding vendored set), so it
# also works standalone via --mirror-only. set -e is locally disabled around the
# $HOME writes so a permission/space failure logs and is skipped without aborting the
# (already-completed) repo sync. The manifest records a content hash of the sorted
# skill set (drift signal) and the writing vault's path (cross-vault diagnostic).
mirror_user_scope() {
  [ -f "$LOCK" ] || { echo "   ! no lock at $LOCK; nothing to mirror" >&2; return 0; }
  local hasher
  if   command -v sha256sum >/dev/null 2>&1; then hasher="sha256sum"
  elif command -v shasum    >/dev/null 2>&1; then hasher="shasum -a 256"
  else echo "   ! no sha256sum/shasum; skipping user-scope mirror" >&2; return 0; fi

  local lock_hash owned_json
  lock_hash="$(jq -S '.skills | sort' "$LOCK" | $hasher | cut -d' ' -f1)"
  owned_json="[]"; [ -f "$MIRROR_MANIFEST" ] && owned_json="$(jq -c '.owned // []' "$MIRROR_MANIFEST" 2>/dev/null || echo '[]')"

  echo ">> user-scope mirror"
  echo "   targets: $CLAUDE_USER_SKILLS , $CODEX_USER_SKILLS"
  local installed=() name owned dest stage did_any collision
  set +e   # a $HOME write failure must not abort the already-finished repo sync
  while IFS= read -r name; do
    [ -n "$name" ] && [ -d "$CANON_SKILLS/$name" ] || continue
    owned=0; [ "$(jq -r --arg n "$name" 'index($n) != null' <<<"$owned_json" 2>/dev/null)" = "true" ] && owned=1
    # Non-destructive: if a skill of this name exists in ANY target and we don't own
    # it, it's yours — leave it untouched in EVERY target (consistent name-level
    # ownership, so a later refresh never clobbers a skill you installed yourself).
    if [ "$owned" -eq 0 ]; then
      collision=0
      for dest in "$CLAUDE_USER_SKILLS" "$CODEX_USER_SKILLS"; do [ -e "$dest/$name" ] && collision=1; done
      [ "$collision" -eq 1 ] && { echo "   skip (your own): $name"; continue; }
    fi
    did_any=0
    for dest in "$CLAUDE_USER_SKILLS" "$CODEX_USER_SKILLS"; do
      mkdir -p "$dest" 2>/dev/null || { echo "   ! cannot create $dest; skipping" >&2; continue; }
      stage="$dest/.$name.tmp.$$"; rm -rf "$stage" 2>/dev/null
      if cp -R "$CANON_SKILLS/$name" "$stage" 2>/dev/null && rm -rf "$dest/$name" 2>/dev/null && mv "$stage" "$dest/$name" 2>/dev/null; then
        did_any=1
      else
        rm -rf "$stage" 2>/dev/null; echo "   ! failed to write $dest/$name" >&2
      fi
    done
    [ "$did_any" -eq 1 ] && installed+=("$name")
  done < <(jq -r '.skills[]?' "$LOCK")
  set -e

  # owned = the set we installed/refreshed this run (skipped-as-yours names are NOT recorded).
  local owned_now; owned_now="$(printf '%s\n' "${installed[@]:-}" | jq -R . | jq -s 'map(select(. != "")) | unique')"
  mkdir -p "$(dirname "$MIRROR_MANIFEST")" 2>/dev/null || true
  jq -n --argjson owned "$owned_now" --arg hash "$lock_hash" --arg vault "$ROOT" \
        --arg when "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{owned:$owned, lock_hash:$hash, vault_path:$vault, written:$when}' \
        > "$MIRROR_MANIFEST" 2>/dev/null || echo "   ! could not write manifest $MIRROR_MANIFEST" >&2
  echo "   mirrored $(jq 'length' <<<"$owned_now") skill(s) into user-scope (manifest: $MIRROR_MANIFEST)"
}

# --mirror-only: refresh the user-scope mirror from the repo's CURRENT vendored set
# (the committed lock) WITHOUT re-fetching upstream — fast, offline, no concurrency
# guard needed. This is the path /install-skills uses for a local refresh.
if [ -n "$MIRROR_ONLY" ]; then mirror_user_scope; exit 0; fi

command -v curl >/dev/null || { echo "curl is required" >&2; exit 1; }
[ -f "$MANIFEST" ] || [ -f "$LOCAL_MANIFEST" ] || { echo "no skill-sources.json or skill-sources.local.json found" >&2; exit 1; }

# Concurrency guard. The Claude Code SessionStart hook backgrounds this sync, so a
# manual run (or a second session starting) can overlap one already in flight. Two
# concurrent runs racing on the per-skill rm+cp below produced nested self-duplicate
# dirs (.agents/skills/ab-testing/ab-testing/). A portable mkdir-based lock (flock is
# not built into macOS) lets the first run win; later runs exit early. A lock older
# than 5 min is treated as stale (a crashed run) and reclaimed, so we never wedge
# permanently.
if ! mkdir "$LOCKDIR" 2>/dev/null; then
  lock_mtime=$(stat -f %m "$LOCKDIR" 2>/dev/null || stat -c %Y "$LOCKDIR" 2>/dev/null || echo 0)
  if [ "$(( $(date +%s) - lock_mtime ))" -ge 300 ] && rm -rf "$LOCKDIR" && mkdir "$LOCKDIR" 2>/dev/null; then
    echo "reclaimed stale sync lock"
  else
    echo "another sync-skills run is in progress ($LOCKDIR); exiting" >&2
    exit 0
  fi
fi

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP" "$LOCKDIR"' EXIT
mkdir -p "$CANON_SKILLS" "$CANON_AGENTS"

# Merge the base-owned curation (skill-sources.json, refreshed by update-base) with
# this vault's OWN additions (skill-sources.local.json, never synced). On a name
# collision the LOCAL entry wins, so a vault can override a base source (e.g. pin a
# different ref or include-list). This is what lets base curation propagate to the
# fleet via update-base while each vault keeps its custom sources.
MERGED="$TMP/skill-sources.merged.json"
jq -s '{ sources: ( ((.[1].sources // []) + (.[0].sources // [])) | unique_by(.name) ) }' \
  <([ -f "$MANIFEST" ]       && cat "$MANIFEST"       || echo "{}") \
  <([ -f "$LOCAL_MANIFEST" ] && cat "$LOCAL_MANIFEST" || echo "{}") \
  > "$MERGED"
MANIFEST="$MERGED"
if [ -f "$LOCAL_MANIFEST" ]; then
  echo "merged $(jq '.sources | length' "$LOCAL_MANIFEST") local source(s) from skill-sources.local.json"
fi

# 1) Remove artifacts from the previous run (clean update; only locked paths,
#    so hand-made skills/agents placed in the canonical dirs are never touched).
#    First sweep any leftover atomic-swap staging dirs from a crashed prior run
#    (safe now that we hold the lock — no live run can own one).
find "$CANON_SKILLS" -maxdepth 1 -name '.*.tmp.*' -exec rm -rf {} + 2>/dev/null || true
if [ -f "$LOCK" ]; then
  while IFS= read -r d; do [ -n "$d" ] && rm -rf "$CANON_SKILLS/$d"; done < <(jq -r '.skills[]?' "$LOCK")
  while IFS= read -r f; do [ -n "$f" ] && rm -f  "$CANON_AGENTS/$f"; done < <(jq -r '.agents[]?' "$LOCK")
fi

VSKILLS=(); VAGENTS=()

fetch() { # repo ref -> echoes extracted dir, or non-zero on failure
  local repo="$1" ref="$2" dest="$TMP/${repo//\//_}__$ref"
  [ -d "$dest" ] && { printf '%s' "$dest"; return 0; }
  mkdir -p "$dest"
  if curl -fsSL "https://codeload.github.com/$repo/tar.gz/refs/heads/$ref" -o "$TMP/a.tgz" \
     && tar -xzf "$TMP/a.tgz" -C "$dest" --strip-components=1 2>/dev/null; then
    printf '%s' "$dest"; return 0
  fi
  rm -rf "$dest"; return 1
}

count=$(jq '.sources | length' "$MANIFEST")
for i in $(seq 0 $((count - 1))); do
  name=$(jq -r ".sources[$i].name"   "$MANIFEST")
  repo=$(jq -r ".sources[$i].repo"   "$MANIFEST")
  ref=$(jq  -r ".sources[$i].ref   // \"main\""   "$MANIFEST")
  spath=$(jq -r ".sources[$i].skillsPath // \"skills\"" "$MANIFEST")
  apath=$(jq -r ".sources[$i].agentsPath // empty"      "$MANIFEST")
  inc=$(jq -r ".sources[$i].include // [] | .[]" "$MANIFEST" | paste -sd'|' -)
  [ -n "$inc" ] && inc="|$inc|"
  echo ">> $name  ($repo @ $ref)"

  src=""
  for r in "$ref" main master; do
    if src=$(fetch "$repo" "$r"); then break; else src=""; fi
  done
  [ -z "$src" ] && { echo "   ! download failed; skipping"; continue; }

  if [ -d "$src/$spath" ]; then
    while IFS= read -r skfile; do
      sdir=$(dirname "$skfile"); base=$(basename "$sdir")
      if [ -n "$inc" ] && [ "${inc/|$base|/}" = "$inc" ]; then continue; fi
      # Atomic swap: copy into a temp sibling, then mv into place. `cp -R src dest`
      # nests src *inside* dest when dest already exists, so copying straight onto a
      # live dir is the footgun that produced nested duplicates. Staging + mv also
      # keeps the canonical dir whole if the run is interrupted mid-copy.
      stage="$CANON_SKILLS/.$base.tmp.$$"
      rm -rf "$stage"; cp -R "$sdir" "$stage"
      rm -rf "$CANON_SKILLS/$base"; mv "$stage" "$CANON_SKILLS/$base"
      VSKILLS+=("$base"); echo "   skill: $base"
    done < <(find "$src/$spath" -type f -name 'SKILL.md' | sort)
  else
    echo "   ! skillsPath '$spath' not found in repo"
  fi

  if [ -n "$apath" ] && [ -d "$src/$apath" ]; then
    while IFS= read -r af; do
      b=$(basename "$af"); cp "$af" "$CANON_AGENTS/$b"
      VAGENTS+=("$b"); echo "   agent: $b"
    done < <(find "$src/$apath" -type f -name '*.md' | sort)
  fi
done

# 2a) Self-contain vendored skills: rewrite namespaced plugin agent IDs
#     (e.g. `compound-knowledge:research:stale-knowledge-checker`) down to the
#     flat basename (`stale-knowledge-checker`) — but ONLY when that agent was
#     vendored flat into .agents/agents/. The plugin namespace resolves only when
#     the upstream marketplace plugin is installed; the flat name resolves in
#     every agent and every ephemeral cloud container, which is the whole point
#     of vendoring. Re-run-safe: upstream re-introduces the namespaced form each
#     sync and this step re-normalizes it. Touches only lock-tracked vendored
#     files, so hand-authored skills/agents are never rewritten.
if [ "${#VSKILLS[@]}" -gt 0 ] || [ "${#VAGENTS[@]}" -gt 0 ]; then
  VENDORED_SKILL_DIRS="$(printf '%s\n' "${VSKILLS[@]:-}")" \
  VENDORED_AGENT_FILES="$(printf '%s\n' "${VAGENTS[@]:-}")" \
  python3 - "$CANON_SKILLS" "$CANON_AGENTS" <<'PY'
import os, re, sys
canon_skills, canon_agents = sys.argv[1], sys.argv[2]

# Flat agent names that actually exist locally to receive a call. We only ever
# collapse a namespace down to a name we can satisfy here — a reference like
# `compound-engineering:ce-foo` with no flat `ce-foo.md` is left untouched.
flat = {fn[:-3] for fn in os.listdir(canon_agents) if fn.endswith(".md")}
if not flat:
    print("normalize: no vendored agents; nothing to do"); raise SystemExit

# Collapse one-or-more `segment:` qualifiers that end in a known flat name.
pat = re.compile(
    r'(?<![\w:-])(?:[A-Za-z0-9_-]+:)+(' +
    '|'.join(re.escape(n) for n in sorted(flat, key=len, reverse=True)) +
    r')\b'
)

def normalize(path):
    with open(path, encoding="utf-8") as f:
        text = f.read()
    new = pat.sub(r'\1', text)
    if new == text:
        return False
    with open(path, "w", encoding="utf-8") as f:
        f.write(new)
    return True

targets = []
for d in os.environ.get("VENDORED_SKILL_DIRS", "").splitlines():
    d = d.strip()
    if d and os.path.isfile(p := os.path.join(canon_skills, d, "SKILL.md")):
        targets.append(p)
for a in os.environ.get("VENDORED_AGENT_FILES", "").splitlines():
    a = a.strip()
    if a and os.path.isfile(p := os.path.join(canon_agents, a)):
        targets.append(p)

changed = sum(1 for p in targets if normalize(p))
print(f"normalize: flattened agent refs in {changed} of {len(targets)} vendored file(s)")
PY
fi

# 2) Auto-generate the skills index (agent-agnostic discovery surface).
python3 - "$CANON_SKILLS" "$INDEX" <<'PY'
import os, sys, re, datetime
skills_dir, out = sys.argv[1], sys.argv[2]
rows = []
for d in sorted(os.listdir(skills_dir)):
    p = os.path.join(skills_dir, d, "SKILL.md")
    if not os.path.isfile(p): continue
    name, desc, took = d, "", []
    with open(p, encoding="utf-8") as f:
        lines = f.read().splitlines()
    if lines and lines[0].strip() == "---":
        for ln in lines[1:]:
            if ln.strip() == "---": break
            took.append(ln)
    fm = "\n".join(took)
    m = re.search(r'^name:\s*(.+?)\s*$', fm, re.M)
    if m: name = m.group(1).strip().strip('"\'')
    m = re.search(r'^description:\s*(.+?)\s*$', fm, re.M | re.S)
    if m:
        desc = m.group(1).strip().strip('"\'')
        desc = re.split(r'(?<=[.!?])\s', desc.replace("\n", " "))[0]
        if len(desc) > 240: desc = desc[:237].rstrip() + "..."
    rows.append((d, name, desc))
ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d")
with open(out, "w", encoding="utf-8") as f:
    f.write("# Skills index\n\n")
    f.write(f"_Auto-generated by `.agents/scripts/sync-skills.sh` on {ts}. Do not edit by hand._\n\n")
    f.write(f"{len(rows)} skills available in this repo. Invoke as `/<command>` "
            "(Claude Code / Codex), or read the skill's `SKILL.md` directly in any agent.\n\n")
    f.write("| Command | Use when |\n|---|---|\n")
    for d, name, desc in rows:
        cmd = name if name else d
        f.write(f"| `/{cmd}` | {desc} |\n")
print(f"index: {len(rows)} skills")
PY

# 3) Create/refresh tool pointers (symlink, else automatic copy fallback).
make_pointer() { # relative_target  link_path  canonical_abs
  local rel="$1" link="$ROOT/$2" canon="$3"
  rm -rf "$link"; mkdir -p "$(dirname "$link")"
  if ln -s "$rel" "$link" 2>/dev/null && [ -L "$link" ] && [ -d "$link" ]; then
    echo "   pointer (symlink): $2 -> $rel"
  else
    # Same cp-into-existing-dir footgun as the skill copy above: stage then mv.
    local stage="$link.tmp.$$"
    rm -rf "$stage"; cp -R "$canon" "$stage"
    rm -rf "$link"; mv "$stage" "$link"
    echo "   pointer (copy):    $2  (symlinks unavailable; copied)"
  fi
}
echo ">> pointers"
for spec in "${POINTERS[@]}"; do
  IFS='|' read -r link rel canon <<< "$spec"
  make_pointer "$rel" "$link" "$canon"
done

# 4) Lock + timestamp
to_json_array() { printf '%s\n' "$@" | jq -R . | jq -s 'map(select(. != "")) | unique'; }
jq -n \
  --argjson s "$(to_json_array "${VSKILLS[@]:-}")" \
  --argjson a "$(to_json_array "${VAGENTS[@]:-}")" \
  '{skills: $s, agents: $a}' > "$LOCK"
date -u +"%Y-%m-%dT%H:%M:%SZ" > "$STAMP"

# 5) Opt-in: also mirror the portable set into user-scope. Runs LAST so the lock it
#    reads is fresh. Default runs (incl. the SessionStart hook, which passes no flags)
#    skip this entirely — user-scope is only ever written on explicit --user-scope.
[ -n "$USER_SCOPE" ] && mirror_user_scope

echo "synced ${#VSKILLS[@]} skills, ${#VAGENTS[@]} agents (canonical: .agents/)"
