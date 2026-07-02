#!/usr/bin/env bash
# lint-vault.sh — deterministic frontmatter conformance check for vault notes.
#
# Flags notes that don't meet the AGENTS.md frontmatter contract: missing/partial
# frontmatter, INVALID YAML (frontmatter that won't parse — Obsidian then rejects the
# whole block and renders it as raw text), missing required keys, an out-of-enum
# type/status, or a missing primary tag. It only checks what a script can check
# *reliably* — structure (TL;DR…Caveats), voice, and linking are judgment calls left to
# the `/normalize-vault` skill.
#
# Usage:
#   .agents/scripts/lint-vault.sh                 # scan the whole note area
#   .agents/scripts/lint-vault.sh NOTE.md DIR/    # check specific files/dirs
#   PRIMARY_TAG=acme .agents/scripts/lint-vault.sh # override the primary tag
#   YAML_CHECK=heuristic .agents/scripts/lint-vault.sh # force the parser-free YAML check
#
# Exit: 0 = all conform (or nothing to check), 1 = offenders found, 2 = usage error.
#
# Scope: TWO tiers.
#   • Full frontmatter-standard check (required keys, enum type/status, primary tag, and
#     valid YAML): the note area — vault root + topical folders. Same set the
#     /normalize-vault skill operates on.
#   • YAML-VALIDITY only (does the frontmatter parse at all?): docs/, plans/, and the
#     backbone index.md + log.md. These carry their OWN schema (kw-*/ce-*), so the note
#     standard doesn't apply — but broken YAML there still makes Obsidian render the whole
#     block as raw text, so parseability is worth enforcing across the vault.
#   Always SKIPPED: raw/ (immutable sources), _sensitive/ (+ legacy _local/), assets/,
#   setup/, dot-folders, and frontmatter-less engine/meta markdown (AGENTS/CLAUDE/README/
#   SETUP/llms).
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

# YAML validity: a note can pass every structural check below and still be BROKEN in
# Obsidian — if the frontmatter isn't valid YAML (classically, an unquoted value
# containing ": ", which YAML reads as a nested mapping), Obsidian's parser rejects the
# WHOLE block and renders it as raw body text. Catch that with a real YAML parser when
# one is present (python3+PyYAML, else ruby/Psych); on a minimal box with neither, fall
# back to a targeted check for that #1 breakage. Override via YAML_CHECK (mainly tests).
YAML_CHECK="${YAML_CHECK:-}"
if [ -z "$YAML_CHECK" ]; then
  if python3 -c 'import yaml' >/dev/null 2>&1; then YAML_CHECK=python
  elif command -v ruby >/dev/null 2>&1 && ruby -rpsych -e '' >/dev/null 2>&1; then YAML_CHECK=ruby
  else YAML_CHECK=heuristic
  fi
fi

# Build the list of candidate files. The dir-prune speeds up the common (no-args) scan;
# scan_mode() below classifies each surviving path (full / yaml / skip) in BOTH modes.
# NOTE: docs/ and plans/ are traversed (not pruned) — they get the yaml-validity tier.
list_default() {
  find . \
    \( -type d \( -name '.?*' -o -name raw -o -name _sensitive -o -name _local -o -name assets \
                  -o -name setup \) -prune \) -o \
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

# Classify a path: "skip" (not a note / not our concern), "yaml" (own-schema but must
# still parse — docs/, plans/, backbone), or "full" (a content note → whole standard).
# Runs even for explicitly-passed files (e.g. a `*.md` glob that sweeps in AGENTS.md).
scan_mode() {
  case "/$1" in */.*) echo skip; return ;; esac              # any dot-folder segment
  case "$1" in
    raw/*|_sensitive/*|_local/*|assets/*|setup/*) echo skip; return ;;
    */raw/*|*/_sensitive/*|*/_local/*|*/assets/*|*/setup/*) echo skip; return ;;
  esac
  case "$(basename "$1")" in
    AGENTS.md|CLAUDE.md|README.md|SETUP.md|llms.txt) echo skip; return ;;   # no frontmatter
    index.md|log.md|hot.md) echo yaml; return ;;             # backbone: parse-only
  esac
  case "$1" in
    docs/*|plans/*|*/docs/*|*/plans/*) echo yaml; return ;;  # own schema: parse-only
  esac
  echo full
}

# Report a problem string if the frontmatter body ($1) isn't valid YAML, else nothing.
fm_yaml_problem() {
  local fm="$1" err line key val
  case "$YAML_CHECK" in
    python)
      err=$(printf '%s' "$fm" | python3 -c 'import sys, yaml
try:
    yaml.safe_load(sys.stdin.read())
except Exception as e:
    sys.stderr.write(str(e).replace("\n", " ")); sys.exit(1)' 2>&1) && return 0
      printf 'invalid YAML frontmatter (%s)' "$(printf '%s' "$err" | cut -c1-90)"
      ;;
    ruby)
      # Psych.parse checks SYNTAX only (no object construction), so date values like
      # `created: 2026-06-27` don't trip a safe-load class error across Ruby versions.
      err=$(printf '%s' "$fm" | ruby -rpsych -e 'begin; Psych.parse(STDIN.read); rescue => e; STDERR.write e.message.gsub("\n", " "); exit 1; end' 2>&1) && return 0
      printf 'invalid YAML frontmatter (%s)' "$(printf '%s' "$err" | cut -c1-90)"
      ;;
    heuristic)
      # No parser present: catch the most common breakage only — a top-level `key: value`
      # whose UNQUOTED plain value contains a colon-space (": ") or a trailing colon, both
      # of which YAML reads as a nested mapping and rejects. Quoted / flow ([]/{}) / block
      # (|/>) / anchor values are left for a real parser to judge.
      while IFS= read -r line; do
        case "$line" in [[:space:]]*|'#'*|'') continue ;; esac        # indented / comment / blank
        printf '%s\n' "$line" | grep -qE '^[[:alnum:]_.-]+:[[:space:]]' || continue
        key=${line%%:*}
        val=${line#*:}
        val="${val#"${val%%[![:space:]]*}"}"                          # ltrim
        val="${val%"${val##*[![:space:]]}"}"                          # rtrim
        [ -n "$val" ] || continue                                     # empty → block follows
        case "$val" in \'*|\"*|'['*|'{'*|'|'*|'>'*|'&'*|'*'*|'!'*) continue ;; esac
        if printf '%s' "$val" | grep -qE ': |:$'; then
          printf 'invalid YAML frontmatter: value for "%s" has an unquoted ":" (quote it)' "$key"
          return 0
        fi
      done <<EOF
$fm
EOF
      ;;
  esac
  return 0
}

# Check one note ($1) in a mode ($2): "full" runs the whole frontmatter standard; "yaml"
# runs ONLY the YAML-parseability check (docs/plans/backbone — own schema, but broken YAML
# still breaks Obsidian). Echoes a "; "-joined list of problems, or nothing if it's clean.
check_note() {
  local f="$1" mode="${2:-full}" p="" fm tval sval tagsline k yprob
  if [ "$(head -n1 "$f" 2>/dev/null || true)" != "---" ]; then
    # No frontmatter: a defect for a content note, but fine for a yaml-tier file (many
    # plans / docs legitimately have none) — nothing to parse there, so stay silent.
    [ "$mode" = full ] && printf 'no frontmatter (line 1 is not "---")'
    return 0
  fi
  # Frontmatter body = lines between the opening --- (line 1) and the next --- line.
  fm=$(awk 'NR==1{next} /^---[[:space:]]*$/{exit} {print}' "$f")
  if ! printf '%s' "$fm" | grep -q .; then
    printf 'empty or unterminated frontmatter'; return 0
  fi
  # Invalid YAML leads the report — it's the most severe (Obsidian shows raw text), and
  # it's the ONLY check that runs in yaml mode.
  yprob=$(fm_yaml_problem "$fm"); [ -n "$yprob" ] && p="$yprob"
  [ "$mode" = full ] || { printf '%s' "$p"; return 0; }
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
[ "$YAML_CHECK" = heuristic ] && echo "note: no python3+PyYAML or ruby found — YAML check limited to the common unquoted-colon case" >&2

checked=0; bad=0; yamlonly=0; mode=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  [ -f "$f" ] || continue
  mode=$(scan_mode "$f")
  [ "$mode" = skip ] && continue
  checked=$((checked + 1))
  [ "$mode" = yaml ] && yamlonly=$((yamlonly + 1))
  probs=$(check_note "$f" "$mode")
  if [ -n "$probs" ]; then bad=$((bad + 1)); printf '  ✗ %s — %s\n' "$f" "$probs"; fi
done <<EOF
$files
EOF

if [ "$checked" -eq 0 ]; then
  echo "No files to check."
  exit 0
fi
if [ "$bad" -eq 0 ]; then
  echo "✓ $checked file(s) checked — $((checked - yamlonly)) note(s) meet the standard, $yamlonly docs/backbone file(s) parse as valid YAML."
  exit 0
fi
echo "$bad of $checked file(s) have problems. Fix invalid YAML by quoting the offending value; bring notes up to standard with /normalize-vault (it asks first)."
exit 1
