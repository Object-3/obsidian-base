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

# tool pointer dirs -> what they point at (relative target | canonical abs)
POINTERS=(
  ".claude/skills|../.agents/skills|$CANON_SKILLS"
  ".codex/skills|../.agents/skills|$CANON_SKILLS"
  ".claude/agents|../.agents/agents|$CANON_AGENTS"
)

command -v jq   >/dev/null || { echo "jq is required"   >&2; exit 1; }
command -v curl >/dev/null || { echo "curl is required" >&2; exit 1; }
[ -f "$MANIFEST" ] || [ -f "$LOCAL_MANIFEST" ] || { echo "no skill-sources.json or skill-sources.local.json found" >&2; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
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
      rm -rf "$CANON_SKILLS/$base"; cp -R "$sdir" "$CANON_SKILLS/$base"
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
    rm -rf "$link"; cp -R "$canon" "$link"
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

echo "synced ${#VSKILLS[@]} skills, ${#VAGENTS[@]} agents (canonical: .agents/)"
