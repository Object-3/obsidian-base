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
#
# Scope (default read from .agents/vault-profile.md `dream_session_scope`, else this-checkout):
#   this-checkout  — only the current checkout's Claude Code sessions
#   all-worktrees  — every git worktree of this vault (via `git worktree list`)
#
# Read-only. Never mutates any file. Degrades to empty output + exit 0 when the session
# store is absent, so a caller (a hook) can never be crashed by it. Exit: 0 normal,
# 2 usage error.
#
# Test hooks (honored so the smoke test never touches your real ~/. or git):
#   CLAUDE_PROJECTS_DIR   override ~/.claude/projects (point at a fixture store)
#   DREAM_SLUGS           whitespace-separated slug list; short-circuits scope resolution
#   DREAM_STATE           override the .agents/dream-state watermark path (fixture watermark)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROFILE="$ROOT/.agents/vault-profile.md"
STATE="${DREAM_STATE:-$ROOT/.agents/dream-state}"
PROJECTS_DIR="${CLAUDE_PROJECTS_DIR:-$HOME/.claude/projects}"

COUNT_ONLY=""; SCOPE=""; SINCE=""; EXTRACT=""
# Each value-taking flag consumes its value with `shift 2`; if the value is missing (the
# flag was the last arg), `shift 2` fails and we report a usage error (exit 2) instead of
# letting `set -e` abort with a bare crash. No trailing shift, so there's no double-shift.
while [ "$#" -gt 0 ]; do
  case "$1" in
    --count)   COUNT_ONLY=1; shift ;;
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

# File mtime -> epoch seconds, portable across BSD (stat -f %m) and GNU (stat -c %Y).
mtime_epoch() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0; }

# A filesystem path -> the Claude Code project-dir slug (every non-alphanumeric -> '-'),
# matching how Claude Code names ~/.claude/projects/<slug>.
path_to_slug() { printf '%s' "$1" | sed 's/[^A-Za-z0-9]/-/g'; }

# Resolve the scope: explicit flag > vault-profile key > this-checkout default.
if [ -z "$SCOPE" ] && [ -f "$PROFILE" ]; then
  SCOPE=$(sed -n 's/^dream_session_scope:[[:space:]]*//p' "$PROFILE" | head -n1 \
          | sed 's/[[:space:]]*#.*$//' | tr -d '"'"'"'[:space:]')
fi
case "$SCOPE" in this-checkout|all-worktrees) ;; *) SCOPE="this-checkout" ;; esac

# Resolve the slug list to scan. DREAM_SLUGS (test hook) wins. Otherwise this-checkout is
# the current repo root; all-worktrees enumerates every worktree of this vault precisely
# via `git worktree list` (Conductor workspaces are real worktrees), degrading to the
# current checkout if git is unavailable.
slugs=""
if [ -n "${DREAM_SLUGS:-}" ]; then
  slugs="$DREAM_SLUGS"
elif [ "$SCOPE" = "all-worktrees" ]; then
  if wt=$(git -C "$ROOT" worktree list --porcelain 2>/dev/null); then
    while IFS= read -r line; do
      case "$line" in "worktree "*) slugs="$slugs $(path_to_slug "${line#worktree }")" ;; esac
    done <<EOF
$wt
EOF
  fi
  [ -n "$slugs" ] || slugs="$(path_to_slug "$ROOT")"
else
  slugs="$(path_to_slug "$ROOT")"
fi

# Resolve the watermark string: explicit --since wins, else line 1 of the state file.
watermark_str="$SINCE"
if [ -z "$watermark_str" ] && [ -f "$STATE" ]; then watermark_str=$(head -n1 "$STATE"); fi
watermark_epoch=$(iso_to_epoch "$watermark_str")

# Collect session files newer than the watermark across the resolved slug dirs. Dedup
# slugs (an all-worktrees list can repeat); a file lives in exactly one slug dir.
found=""
seen_slug=" "
for slug in $slugs; do
  [ -n "$slug" ] || continue
  case "$seen_slug" in *" $slug "*) continue ;; esac
  seen_slug="$seen_slug$slug "
  dir="$PROJECTS_DIR/$slug"
  [ -d "$dir" ] || continue
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if [ "$(mtime_epoch "$f")" -gt "$watermark_epoch" ]; then
      found="$found$f"$'\n'
    fi
  done < <(find "$dir" -maxdepth 1 -type f -name '*.jsonl' 2>/dev/null | sort)
done

# Normalize once: drop blanks, dedup, sort. Count and path modes stay consistent.
normalized=$(printf '%s' "$found" | sed '/^$/d' | sort -u)
if [ -n "$COUNT_ONLY" ]; then
  if [ -z "$normalized" ]; then printf '0\n'; else printf '%s\n' "$normalized" | wc -l | tr -d ' '; fi
else
  [ -n "$normalized" ] && printf '%s\n' "$normalized"
fi
exit 0
