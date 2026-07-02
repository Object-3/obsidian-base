#!/usr/bin/env bash
# lint-vault.sh — deterministic frontmatter conformance check for vault notes.
#
# Flags notes that don't meet the AGENTS.md frontmatter contract: missing/partial
# frontmatter, missing required keys, an out-of-enum type/status, or a missing primary
# tag. It only checks what a script can check *reliably* — structure (TL;DR…Caveats),
# voice, and linking are judgment calls left to the `/normalize-vault` skill.
#
# Usage:
#   .agents/scripts/lint-vault.sh                 # scan the whole note area
#   .agents/scripts/lint-vault.sh NOTE.md DIR/    # check specific files/dirs
#   PRIMARY_TAG=acme .agents/scripts/lint-vault.sh # override the primary tag
#
# Exit: 0 = all conform (or nothing to check), 1 = offenders found, 2 = usage error.
#
# Scope: the note area only — vault root + topical folders. It deliberately SKIPS
#   raw/ (immutable sources), _sensitive/ (+ legacy _local/), assets/, dot-folders, setup/, the backbone
#   (index.md, log.md), engine/meta markdown (AGENTS/CLAUDE/README/SETUP/llms), and
#   docs/ + plans/ (their own schema, maintained by the kw-* skills). Same exclusions
#   as the /normalize-vault skill.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"; cd "$ROOT"
PROFILE="$ROOT/.agents/vault-profile.md"

ALLOWED_TYPES="decision-record research playbook scratch index"
ALLOWED_STATUS="active draft reference archived"
REQUIRED_KEYS="title type status tags created updated"

# Primary tag: env override wins; else read it from vault-profile.md frontmatter. If it's
# unset or still the {{PRIMARY_TAG}} placeholder, skip the tag check (vault not set up).
primary_tag="${PRIMARY_TAG:-}"
if [ -z "$primary_tag" ] && [ -f "$PROFILE" ]; then
  primary_tag=$(sed -n 's/^primary_tag:[[:space:]]*//p' "$PROFILE" | head -n1 | tr -d '"'"'"'[:space:]')
fi
case "$primary_tag" in *"{{"*) primary_tag="" ;; esac

# Build the list of candidate files. The dir-prune speeds up the common (no-args)
# scan; excluded_path() below is the real filter and runs in BOTH modes.
list_default() {
  find . \
    \( -type d \( -name '.?*' -o -name raw -o -name _sensitive -o -name _local -o -name assets \
                  -o -name docs -o -name plans -o -name setup \) -prune \) -o \
    -type f -name '*.md' -print \
  | sed 's|^\./||' | sort
}
list_args() {
  local a
  for a in "$@"; do
    if [ -d "$a" ]; then find "$a" -type f -name '*.md' | sed 's|^\./||'
    elif [ -f "$a" ]; then printf '%s\n' "${a#./}"
    else echo "lint-vault: no such file or dir: $a" >&2
    fi
  done | sort -u
}

# Not a vault note → skip (mechanism/engine dirs, dot-folders, backbone, engine/meta
# markdown, and the own-schema docs/ + plans/). Keeps the lint scoped to content notes,
# even when files are passed explicitly (e.g. a `*.md` glob that sweeps in AGENTS.md).
excluded_path() {
  case "/$1" in */.*) return 0 ;; esac                       # any dot-folder segment
  case "$1" in
    raw/*|_sensitive/*|_local/*|assets/*|docs/*|plans/*|setup/*) return 0 ;;
    */raw/*|*/_sensitive/*|*/_local/*|*/assets/*|*/docs/*|*/plans/*|*/setup/*) return 0 ;;
  esac
  case "$(basename "$1")" in
    AGENTS.md|CLAUDE.md|README.md|SETUP.md|llms.txt|index.md|log.md|hot.md) return 0 ;;
  esac
  return 1
}

# Check one note. Echoes a "; "-joined list of problems, or nothing if it conforms.
check_note() {
  local f="$1" p="" fm tval sval tagsline k
  if [ "$(head -n1 "$f" 2>/dev/null || true)" != "---" ]; then
    printf 'no frontmatter (line 1 is not "---")'; return 0
  fi
  # Frontmatter body = lines between the opening --- (line 1) and the next --- line.
  fm=$(awk 'NR==1{next} /^---[[:space:]]*$/{exit} {print}' "$f")
  if ! printf '%s' "$fm" | grep -q .; then
    printf 'empty or unterminated frontmatter'; return 0
  fi
  for k in $REQUIRED_KEYS; do
    printf '%s\n' "$fm" | grep -qE "^${k}:[[:space:]]" || p="${p:+$p; }missing $k"
  done
  tval=$(printf '%s\n' "$fm" | sed -n 's/^type:[[:space:]]*//p'   | head -n1 | sed 's/[[:space:]]*#.*$//' | tr -d '[:space:]')
  sval=$(printf '%s\n' "$fm" | sed -n 's/^status:[[:space:]]*//p' | head -n1 | sed 's/[[:space:]]*#.*$//' | tr -d '[:space:]')
  [ -n "$tval" ] && case " $ALLOWED_TYPES "  in *" $tval "*) ;; *) p="${p:+$p; }invalid type '$tval'";;  esac
  [ -n "$sval" ] && case " $ALLOWED_STATUS " in *" $sval "*) ;; *) p="${p:+$p; }invalid status '$sval'";; esac
  if [ -n "$primary_tag" ]; then
    tagsline=$(printf '%s\n' "$fm" | grep -E '^tags:' || true)
    if [ -n "$tagsline" ] && ! printf '%s' "$tagsline" | grep -qw "$primary_tag"; then
      p="${p:+$p; }missing primary tag '$primary_tag'"
    fi
  fi
  printf '%s' "$p"; return 0
}

if [ "$#" -gt 0 ]; then files=$(list_args "$@"); else files=$(list_default); fi

[ -n "$primary_tag" ] || echo "note: primary tag not set (vault-profile.md) — skipping the primary-tag check" >&2

checked=0; bad=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  [ -f "$f" ] || continue
  excluded_path "$f" && continue
  checked=$((checked + 1))
  probs=$(check_note "$f")
  if [ -n "$probs" ]; then bad=$((bad + 1)); printf '  ✗ %s — %s\n' "$f" "$probs"; fi
done <<EOF
$files
EOF

if [ "$checked" -eq 0 ]; then
  echo "No notes to check in the note area."
  exit 0
fi
if [ "$bad" -eq 0 ]; then
  echo "✓ all $checked note(s) conform to the frontmatter standard."
  exit 0
fi
echo "$bad of $checked note(s) below standard. Bring them up with /normalize-vault (it asks first)."
exit 1
