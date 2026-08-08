#!/usr/bin/env bash
# ── ENGINE FILE (base-owned) — AGENT NOTICE ─────────────────────────────────
# In a DERIVED VAULT (git origin is not the obsidian-base repo): if this script
# is buggy, do NOT fix it here and do NOT open a PR against the base repo —
# FILE A GITHUB ISSUE against the upstream base (.agents/.base-url if present,
# else Object-3/obsidian-base) with the error + proposed fix in the issue body.
# Local patches are overwritten by the next update-base and help no other clone.
# See AGENTS.md → "Engine bugs & improvements found in a derived vault".
# ─────────────────────────────────────────────────────────────────────────────
# dream-scan.sh — scope-aware discovery of agent session transcripts recorded SINCE the
# dream watermark. Feeds two callers: the SessionStart nudge (.claude/hooks/dream-if-stale.sh,
# which uses --count to gate) and the /vault-dream skill (which reads the paths to consolidate).
#
# It counts CLAUDE CODE sessions — the one session store that is precisely partitioned per
# repo checkout (~/.claude/projects/<slug>/), so the count is repo-scoped and cheap (a
# maxdepth-1 mtime scan, no file-content reads). That keeps the hook fast and free of
# cross-repo false positives. Codex and Cursor breadth is reached by the /vault-dream skill
# itself via the vendored `ce-session-inventory` skill (which CWD-filters Codex and parses
# Cursor); the lightweight gate here deliberately does not, and the nudge hook is
# Claude-Code-specific anyway (other agents invoke /vault-dream manually).
#
# It also carries a PORTABLE fallback extractor (`--extract <file>`): a compact digest of a
# single session JSONL (user + assistant text only; tool calls, tool results, and reasoning
# stripped) so the /vault-dream skill can harvest learnings without loading multi-megabyte
# files into context. This is the default extraction path in forks/cloud that don't have the
# compound-engineering plugin's richer `ce-session-extract`; when that skill IS present, the
# dream prefers it for cross-agent (Codex/Cursor) breadth.
#
# Usage:
#   .agents/scripts/dream-scan.sh                 # print session paths newer than the watermark
#   .agents/scripts/dream-scan.sh --count         # print only the integer count (what the hook uses)
#   .agents/scripts/dream-scan.sh --scope all-worktrees   # override the vault-profile scope
#   .agents/scripts/dream-scan.sh --since 2026-07-01T00:00:00Z   # override the watermark
#   .agents/scripts/dream-scan.sh --extract <file.jsonl>  # print a compact digest of one session
#   .agents/scripts/dream-scan.sh --doctor        # diagnose session-store wiring (see below)
#
# Scope (default read from .agents/vault-profile.md `dream_session_scope`, else this-checkout):
#   this-checkout  — only the current checkout's Claude Code sessions
#   all-worktrees  — every git worktree of this vault (via `git worktree list`)
#
# Slug resolution. Claude Code keys transcripts to the directory it was LAUNCHED from
# (~/.claude/projects/<slug-of-launch-dir>), which is not always the vault repo root — in
# multi-vault / parent-dir layouts sessions land under the PARENT directory's slug and a
# naive root-slug scan counts 0 forever (issue #54). So, in order:
#   1. `dream_project_slug:` in .agents/vault-profile.md, when set, names the exact
#      ~/.claude/projects/<slug> directory to scan (explicit override; no fallback, no
#      content filter — you told us where the sessions are).
#   2. Otherwise the vault root's slug is scanned; if that directory is MISSING or holds
#      no *.jsonl transcripts NEWER than the watermark (a stale pre-watermark transcript
#      must not suppress the fallback — that would recreate the silent-0 bug), the scan
#      FALLS BACK to ancestor-directory slugs (parent upward, bounded to 3 levels or
#      $HOME, whichever comes first), counting ONLY transcripts whose content references
#      this vault's path — matched with a path boundary (…/vault never matches
#      …/vault-fork) and against both the logical and physical (symlink-resolved) root —
#      so sessions from sibling vaults under the same parent are never miscounted.
# --doctor reports how the slugs resolved and how many transcripts each directory holds,
# distinguishing "0 new sessions" (healthy) from "expected session directory not found /
# empty and no fallback transcripts reference this vault" (broken wiring — exit 3). The
# SessionStart nudge hook never uses --doctor and keeps its silent-on-broken-state
# posture; the diagnostic surfaces via the /doctor skill.
#
# Read-only. Never mutates any file. Degrades to empty output + exit 0 when the session
# store is absent, so a caller (a hook) can never be crashed by it. Exit: 0 normal,
# 2 usage error, 3 broken session-store wiring (--doctor mode only).
#
# Test hooks (honored so the smoke test never touches your real ~/. or git):
#   CLAUDE_PROJECTS_DIR   override ~/.claude/projects (point at a fixture store)
#   DREAM_SLUGS           whitespace-separated slug list; short-circuits scope resolution
#                         (including the ancestor fallback) entirely
#   DREAM_STATE           override the .agents/dream-state watermark path (fixture watermark)
#   DREAM_ROOT            override the vault root used for slug derivation + content filter
#   DREAM_PROFILE         override the .agents/vault-profile.md path (fixture profile)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VROOT="${DREAM_ROOT:-$ROOT}"                    # the vault root as slugged/filtered (test hook)
PROFILE="${DREAM_PROFILE:-$ROOT/.agents/vault-profile.md}"
STATE="${DREAM_STATE:-$ROOT/.agents/dream-state}"
PROJECTS_DIR="${CLAUDE_PROJECTS_DIR:-$HOME/.claude/projects}"

COUNT_ONLY=""; SCOPE=""; SINCE=""; EXTRACT=""; DOCTOR=""
# Each value-taking flag consumes its value with `shift 2`; if the value is missing (the
# flag was the last arg), `shift 2` fails and we report a usage error (exit 2) instead of
# letting `set -e` abort with a bare crash. No trailing shift, so there's no double-shift.
while [ "$#" -gt 0 ]; do
  case "$1" in
    --count)   COUNT_ONLY=1; shift ;;
    --doctor)  DOCTOR=1; shift ;;
    --scope)   SCOPE="${2:-}";   shift 2 2>/dev/null || { echo "dream-scan: --scope needs a value" >&2; exit 2; } ;;
    --since)   SINCE="${2:-}";   shift 2 2>/dev/null || { echo "dream-scan: --since needs a value" >&2; exit 2; } ;;
    --extract) EXTRACT="${2:-}"; shift 2 2>/dev/null || { echo "dream-scan: --extract needs a value" >&2; exit 2; } ;;
    -h|--help) awk 'NR==1{next} /^#/{print;next} {exit}' "$0"; exit 0 ;;
    *) echo "dream-scan: unknown argument: $1" >&2; exit 2 ;;
  esac
done

# --extract: compact, portable digest of ONE session JSONL. Handles both Claude Code
# ({type:user|assistant, message:{role,content}}) and Codex ({payload:{role,content}} or a
# bare {role,content}) shapes defensively; skips tool_use / tool_result / thinking /
# reasoning; truncates long turns; tolerates malformed lines. Emits a final _meta line.
if [ -n "$EXTRACT" ]; then
  [ -f "$EXTRACT" ] || { echo "dream-scan: no such file: $EXTRACT" >&2; exit 2; }
  python3 - "$EXTRACT" <<'PY'
import json, sys
path = sys.argv[1]
def texts(content):
    out = []
    if isinstance(content, str):
        if content.strip(): out.append(content)
    elif isinstance(content, list):
        for b in content:
            if isinstance(b, dict):
                if b.get("type") in ("text", "input_text", "output_text") and b.get("text"):
                    out.append(b["text"])
            elif isinstance(b, str) and b.strip():
                out.append(b)
    return out
u = a = errs = 0
try:
    fh = open(path, encoding="utf-8", errors="replace")
except OSError as e:
    print(f"dream-scan: cannot read {path}: {e}", file=sys.stderr); sys.exit(2)
with fh:
    for line in fh:
        line = line.strip()
        if not line: continue
        try:
            o = json.loads(line)
        except Exception:
            errs += 1; continue
        if not isinstance(o, dict): continue
        msg = o.get("message") if isinstance(o.get("message"), dict) else None
        payload = o.get("payload") if isinstance(o.get("payload"), dict) else None
        src = msg or payload or o
        role = src.get("role") or (o.get("type") if o.get("type") in ("user", "assistant") else None)
        content = src.get("content")
        if role not in ("user", "assistant") or content is None: continue
        for t in texts(content):
            t = " ".join(t.split())
            if not t: continue
            if len(t) > 600: t = t[:600] + "…"
            print(f"[{role}] {t}")
            print("---")
            if role == "user": u += 1
            else: a += 1
print(json.dumps({"_meta": True, "user": u, "assistant": a, "parse_errors": errs}))
PY
  exit 0
fi

# ISO-8601 -> epoch seconds, portable across GNU (date -d) and BSD/macOS (date -j -f).
# Unparseable / empty -> 0, i.e. "never run" (everything counts as new). GNU date -d is
# NOT available on macOS, so trying it alone would silently break the elapsed math there.
iso_to_epoch() {
  local iso e
  iso=$(printf '%s' "$1" | tr -d '[:space:]')   # strip CR (CRLF from a Windows-synced vault) / stray whitespace
  [ -n "$iso" ] || { echo 0; return; }
  e=$(date -u -d "$iso" +%s 2>/dev/null)                          && { echo "$e"; return; }
  e=$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$iso" +%s 2>/dev/null)   && { echo "$e"; return; }
  echo 0
}

# File mtime -> epoch seconds. GNU `stat -c %Y` first (Linux/Git-Bash/WSL/busybox),
# then BSD `stat -f %m` (macOS). The order matters: on GNU, `-f` means --file-system,
# so `stat -f %m <file>` *succeeds* for the file operand and prints a multi-line
# filesystem block to stdout — poisoning the numeric comparison even though the GNU
# fallback also runs. BSD exits non-zero on the unknown `-c`, printing nothing, so
# GNU-first is clean on both platforms. The case guard drops any non-numeric output.
mtime_epoch() {
  local m
  m=$(stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0)
  case "$m" in ''|*[!0-9]*) m=0 ;; esac
  echo "$m"
}

# A filesystem path -> the Claude Code project-dir slug (every non-alphanumeric -> '-'),
# matching how Claude Code names ~/.claude/projects/<slug>.
path_to_slug() { printf '%s' "$1" | sed 's/[^A-Za-z0-9]/-/g'; }

# Escape a string for use inside a grep -E (ERE) pattern.
ere_escape() { printf '%s' "$1" | sed 's/[][\.|$(){}?+*^\\]/\\&/g'; }

# The content-filter pattern for fallback transcripts: the vault root path followed by a
# PATH BOUNDARY (any char that couldn't extend the last path component, or end-of-line) —
# a raw substring match would let …/vault also claim …/vault-fork's sessions. Matched
# against both the logical root and its physical (symlink-resolved) form, since transcripts
# may record either (e.g. macOS /tmp vs /private/tmp).
VROOT_BOUND='([^A-Za-z0-9_.~-]|$)'
VROOT_PAT="$(ere_escape "$VROOT")$VROOT_BOUND"
VROOT_REAL=$(cd "$VROOT" 2>/dev/null && pwd -P || printf '%s' "$VROOT")
if [ -n "$VROOT_REAL" ] && [ "$VROOT_REAL" != "$VROOT" ]; then
  VROOT_PAT="$VROOT_PAT|$(ere_escape "$VROOT_REAL")$VROOT_BOUND"
fi

# Resolve the watermark string early (the fallback gate below compares against it):
# explicit --since wins, else line 1 of the state file.
watermark_str="$SINCE"
if [ -z "$watermark_str" ] && [ -f "$STATE" ]; then watermark_str=$(head -n1 "$STATE"); fi
watermark_epoch=$(iso_to_epoch "$watermark_str")

# Resolve the scope: explicit flag > vault-profile key > this-checkout default.
if [ -z "$SCOPE" ] && [ -f "$PROFILE" ]; then
  SCOPE=$(sed -n 's/^dream_session_scope:[[:space:]]*//p' "$PROFILE" | head -n1 \
          | sed 's/[[:space:]]*#.*$//' | tr -d '"'"'"'[:space:]')
fi
case "$SCOPE" in this-checkout|all-worktrees) ;; *) SCOPE="this-checkout" ;; esac

# Explicit slug override: `dream_project_slug:` in vault-profile.md pins the exact
# ~/.claude/projects/<slug> directory (for layouts where Claude Code is launched from a
# directory other than the vault root — see "Slug resolution" in the header).
SLUG_OVERRIDE=""
if [ -f "$PROFILE" ]; then
  SLUG_OVERRIDE=$(sed -n 's/^dream_project_slug:[[:space:]]*//p' "$PROFILE" | head -n1 \
                  | sed 's/[[:space:]]*#.*$//' | tr -d '"'"'"'[:space:]')
fi

# Resolve the slug list to scan. DREAM_SLUGS (test hook) wins, then the profile override.
# Otherwise this-checkout is the current repo root; all-worktrees enumerates every worktree
# of this vault precisely via `git worktree list` (Conductor workspaces are real worktrees),
# degrading to the current checkout if git is unavailable.
#
# `slugs` are scanned as-is; `fb_slugs` are the ancestor-fallback candidates, scanned only
# with a content filter (the transcript must reference this vault's path) so sessions from
# sibling vaults sharing an ancestor launch dir are never miscounted.
slugs=""; fb_slugs=""
primary_slug="$(path_to_slug "$VROOT")"
if [ -n "${DREAM_SLUGS:-}" ]; then
  slugs="$DREAM_SLUGS"
elif [ "$SCOPE" = "all-worktrees" ]; then
  if wt=$(git -C "$VROOT" worktree list --porcelain 2>/dev/null); then
    while IFS= read -r line; do
      case "$line" in "worktree "*) slugs="$slugs $(path_to_slug "${line#worktree }")" ;; esac
    done <<EOF
$wt
EOF
  fi
  [ -n "$slugs" ] || slugs="$primary_slug"
  [ -n "$SLUG_OVERRIDE" ] && slugs="$slugs $SLUG_OVERRIDE"
elif [ -n "$SLUG_OVERRIDE" ]; then
  slugs="$SLUG_OVERRIDE"
else
  slugs="$primary_slug"
  # Ancestor fallback: when the exact-root slug dir is missing OR holds no transcripts
  # NEWER than the watermark, Claude Code was likely launched from an ancestor directory
  # (multi-vault / parent-dir layout) — walk parents, bounded to 3 levels or $HOME,
  # whichever comes first. Gating on watermark-new (not mere presence) matters: one stale
  # pre-watermark transcript in the exact dir must not suppress the fallback forever —
  # that would recreate the silent-0 bug. The content filter + slug dedup below keep the
  # fallback from ever double- or mis-counting.
  exact_new=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    [ "$(mtime_epoch "$f")" -gt "$watermark_epoch" ] && exact_new=$((exact_new + 1))
  done < <(find "$PROJECTS_DIR/$primary_slug" -maxdepth 1 -type f -name '*.jsonl' 2>/dev/null)
  if [ "$exact_new" -eq 0 ]; then
    anc="$VROOT"; level=0
    while [ "$level" -lt 3 ]; do
      parent=$(dirname "$anc")
      [ "$parent" = "$anc" ] && break          # reached filesystem root
      anc="$parent"; level=$((level + 1))
      fb_slugs="$fb_slugs $(path_to_slug "$anc")"
      [ "$anc" = "${HOME:-}" ] && break        # never climb past $HOME
      [ "$anc" = "/" ] && break
    done
  fi
fi

# Collect session files newer than the watermark across the resolved slug dirs. Dedup
# slugs (an all-worktrees list can repeat); a file lives in exactly one slug dir.
# Fallback slug dirs additionally require the transcript to reference this vault's path.
found=""
seen_slug=" "
scan_slug() {  # $1 = slug, $2 = non-empty -> content-filter to transcripts mentioning $VROOT
  local slug="$1" filt="${2:-}" dir f
  [ -n "$slug" ] || return 0
  case "$seen_slug" in *" $slug "*) return 0 ;; esac
  seen_slug="$seen_slug$slug "
  dir="$PROJECTS_DIR/$slug"
  [ -d "$dir" ] || return 0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    [ "$(mtime_epoch "$f")" -gt "$watermark_epoch" ] || continue
    if [ -n "$filt" ]; then grep -qsE -- "$VROOT_PAT" "$f" || continue; fi
    found="$found$f"$'\n'
  done < <(find "$dir" -maxdepth 1 -type f -name '*.jsonl' 2>/dev/null | sort)
  return 0
}
for slug in $slugs;    do scan_slug "$slug" ""; done
for slug in $fb_slugs; do scan_slug "$slug" "vault-filter"; done

# Normalize once: drop blanks, dedup, sort. Count and path modes stay consistent.
normalized=$(printf '%s' "$found" | sed '/^$/d' | sort -u)

# --doctor: report how the slug resolution went and whether the wiring is healthy.
# Distinguishes "0 new sessions" (healthy — nothing new since the watermark) from
# "expected session directory not found / empty, and no fallback transcripts reference
# this vault" (broken — the nudge can never fire). Exit 0 healthy, 3 broken. Only this
# mode ever exits 3; --count/path modes stay exit-0 so the hook is never crashed.
if [ -n "$DOCTOR" ]; then
  if [ -z "$normalized" ]; then count_new=0; else count_new=$(printf '%s\n' "$normalized" | wc -l | tr -d ' '); fi
  echo "dream-scan doctor"
  echo "  vault root:     $VROOT"
  echo "  scope:          $SCOPE"
  echo "  slug override:  ${SLUG_OVERRIDE:-(none)}"
  if [ -d "$PROJECTS_DIR" ]; then
    echo "  projects store: $PROJECTS_DIR (present)"
  else
    echo "  projects store: $PROJECTS_DIR (MISSING)"
  fi
  healthy_new=""; any_present=""
  for slug in $slugs; do
    [ -n "$slug" ] || continue
    dir="$PROJECTS_DIR/$slug"
    if [ ! -d "$dir" ]; then echo "  slug dir:       $dir (MISSING)"; continue; fi
    n=0; m=0
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      n=$((n + 1))
      [ "$(mtime_epoch "$f")" -gt "$watermark_epoch" ] && m=$((m + 1))
    done < <(find "$dir" -maxdepth 1 -type f -name '*.jsonl' 2>/dev/null)
    echo "  slug dir:       $dir ($n transcript(s), $m new since watermark)"
    [ "$n" -gt 0 ] && any_present=1
    [ "$m" -gt 0 ] && healthy_new=1
  done
  fb_total=0
  for slug in $fb_slugs; do
    [ -n "$slug" ] || continue
    dir="$PROJECTS_DIR/$slug"
    [ -d "$dir" ] || continue
    n=$(grep -lsE -- "$VROOT_PAT" "$dir"/*.jsonl 2>/dev/null | wc -l | tr -d ' ' || true)
    echo "  fallback dir:   $dir ($n transcript(s) referencing this vault)"
    fb_total=$(( fb_total + n ))
  done
  echo "  new sessions since watermark: $count_new"
  if [ -n "$healthy_new" ]; then
    echo "  verdict: ok — session transcripts are found where expected"
    exit 0
  elif [ "$fb_total" -gt 0 ]; then
    echo "  verdict: ok (fallback) — the exact slug dir is missing/empty (or has nothing new), but ancestor-slug transcripts referencing this vault were found. Consider pinning dream_project_slug: in .agents/vault-profile.md to that directory name."
    exit 0
  elif [ -n "$any_present" ]; then
    echo "  verdict: ok — transcripts exist in the expected slug dir; none are newer than the watermark and no fallback transcripts reference this vault (nothing new to dream about)"
    exit 0
  else
    echo "  verdict: BROKEN — expected session directory not found (or empty), and no fallback transcripts reference this vault. The dream nudge can never fire. Fix: set dream_project_slug: \"<dir name under $PROJECTS_DIR>\" in .agents/vault-profile.md to where this vault's Claude Code sessions actually land."
    exit 3
  fi
fi

if [ -n "$COUNT_ONLY" ]; then
  if [ -z "$normalized" ]; then printf '0\n'; else printf '%s\n' "$normalized" | wc -l | tr -d ' '; fi
else
  [ -n "$normalized" ] && printf '%s\n' "$normalized"
fi
exit 0
