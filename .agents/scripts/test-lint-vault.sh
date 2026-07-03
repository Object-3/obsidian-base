#!/usr/bin/env bash
# Smoke test for the frontmatter YAML-validity check in .agents/scripts/lint-vault.sh.
#
# Self-contained and offline: writes only to a temp dir, passes notes to the linter by
# explicit path, and forces each detection mode via YAML_CHECK. Run from anywhere:
#
#   .agents/scripts/test-lint-vault.sh
#
# Covers the guarantee this check exists for: a note that passes every STRUCTURAL check
# but whose frontmatter won't parse (Obsidian then renders it as raw text) is flagged.
#   1. an unquoted colon-space value is flagged in EVERY available mode
#   2. a conforming note (quoted colon value) passes cleanly in every mode
#   3. a real parser catches structural errors the parser-free fallback can't (by design)
#   4. docs/ (own-schema tier) is YAML-validated but exempt from the note standard
#   5. a non-kebab note filename is flagged in the full tier (a kebab name passes)
#
# Exits non-zero if any assertion fails.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LINT="$ROOT/.agents/scripts/lint-vault.sh"
[ -x "$LINT" ] || { echo "not executable: $LINT"; exit 1; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

pass=0; fail=0
ok()  { echo "  ok:   $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }

# A fully-conforming note EXCEPT the frontmatter contains an unquoted colon-space value.
cat > "$WORK/bad-colon.md" <<'EOF'
---
title:   "Broken source demo"
type:    research
status:  active
tags:    [object3, test]
created: 2026-07-02
updated: 2026-07-02
source:  discovered "vault backup: <ts>" commits during the re-platform
---

# Broken

body
EOF

# The same note with the colon-bearing value single-quoted — valid YAML, fully conforming.
cat > "$WORK/good.md" <<'EOF'
---
title:   "Fixed source demo"
type:    research
status:  active
tags:    [object3, test]
created: 2026-07-02
updated: 2026-07-02
source:  'discovered "vault backup: <ts>" commits during the re-platform'
---

# Fixed

body
EOF

# A structural break (unclosed flow sequence) — invalid YAML, but with no ": " in a plain
# value, so the parser-free heuristic deliberately does NOT catch it; a real parser does.
cat > "$WORK/bad-flow.md" <<'EOF'
---
title:   "Unclosed flow"
type:    research
status:  active
tags:    [object3, test
created: 2026-07-02
updated: 2026-07-02
---

# Unclosed

body
EOF

# Which detection modes can we actually exercise here?
MODES=(heuristic)
python3 -c 'import yaml' >/dev/null 2>&1 && MODES+=(python)
command -v ruby >/dev/null 2>&1 && ruby -rpsych -e '' >/dev/null 2>&1 && MODES+=(ruby)
echo "modes under test: ${MODES[*]}"

run() { YAML_CHECK="$1" PRIMARY_TAG=object3 bash "$LINT" "$2" 2>&1; }

echo "== 1: unquoted colon-space value is flagged in every mode =="
for m in "${MODES[@]}"; do
  out=$(run "$m" "$WORK/bad-colon.md"); rc=$?
  if printf '%s' "$out" | grep -q 'invalid YAML frontmatter' && [ "$rc" -ne 0 ]; then
    ok "[$m] flagged bad-colon.md (exit $rc)"
  else
    bad "[$m] did NOT flag bad-colon.md (exit $rc): $out"
  fi
done

echo "== 2: conforming note (quoted colon value) passes cleanly in every mode =="
for m in "${MODES[@]}"; do
  out=$(run "$m" "$WORK/good.md"); rc=$?
  if [ "$rc" -eq 0 ] && ! printf '%s' "$out" | grep -q 'invalid YAML\|✗'; then
    ok "[$m] good.md passed clean (exit 0)"
  else
    bad "[$m] good.md not clean (exit $rc): $out"
  fi
done

echo "== 3: a real parser catches a structural error the fallback can't =="
for m in "${MODES[@]}"; do
  [ "$m" = heuristic ] && continue
  out=$(run "$m" "$WORK/bad-flow.md")
  if printf '%s' "$out" | grep -q 'invalid YAML frontmatter'; then
    ok "[$m] flagged unclosed-flow bad-flow.md"
  else
    bad "[$m] did NOT flag bad-flow.md: $out"
  fi
done
# Document the fallback's known boundary (not an assertion — the heuristic is allowed to
# improve later): show whether it caught the structural break.
hout=$(run heuristic "$WORK/bad-flow.md")
if printf '%s' "$hout" | grep -q 'invalid YAML frontmatter'; then
  echo "  info: heuristic also caught bad-flow.md"
else
  echo "  info: heuristic left bad-flow.md to a real parser (expected)"
fi

echo "== 4: docs/ is YAML-validated but exempt from the note standard =="
mkdir -p "$WORK/docs"
# Own-schema (ce/kw) frontmatter — no title/status/tags — with a BROKEN unquoted colon.
cat > "$WORK/docs/docs-broken.md" <<'EOF'
---
type: bug
severity: high
summary: cache stampede: the fix
---

# x
EOF
# Same own-schema shape, valid YAML (colon value quoted). Must NOT trip the note standard.
cat > "$WORK/docs/docs-ok.md" <<'EOF'
---
type: bug
severity: high
summary: "cache stampede: the fix"
category: performance
---

# x
EOF
for m in "${MODES[@]}"; do
  out=$(run "$m" "$WORK/docs/docs-broken.md"); rc=$?
  if printf '%s' "$out" | grep -q 'invalid YAML frontmatter' && [ "$rc" -ne 0 ]; then
    ok "[$m] flagged broken YAML under docs/"
  else
    bad "[$m] missed broken YAML under docs/ (exit $rc): $out"
  fi
  out=$(run "$m" "$WORK/docs/docs-ok.md"); rc=$?
  if [ "$rc" -eq 0 ] && ! printf '%s' "$out" | grep -qE 'invalid YAML|✗|missing'; then
    ok "[$m] valid non-standard docs/ note passed (no 'missing title' etc.)"
  else
    bad "[$m] wrongly flagged a valid non-standard docs/ note (exit $rc): $out"
  fi
done

echo "== 5: non-kebab filename is flagged (full tier); a kebab name is not =="
# Perfect frontmatter, but the FILENAME has spaces + an ampersand + capitals.
cat > "$WORK/Bad Name & Thing.md" <<'EOF'
---
title:   "Bad Name Thing"
type:    research
status:  active
tags:    [object3, test]
created: 2026-07-02
updated: 2026-07-02
---

# Bad Name Thing

body
EOF
# Same perfect frontmatter, but a clean kebab filename — must NOT get a filename flag.
cat > "$WORK/good-kebab-name.md" <<'EOF'
---
title:   "Good Kebab Name"
type:    research
status:  active
tags:    [object3, test]
created: 2026-07-02
updated: 2026-07-02
---

# Good Kebab Name

body
EOF
for m in "${MODES[@]}"; do
  out=$(run "$m" "$WORK/Bad Name & Thing.md"); rc=$?
  if printf '%s' "$out" | grep -q 'filename not kebab-case' && [ "$rc" -ne 0 ]; then
    ok "[$m] flagged non-kebab filename (exit $rc)"
  else
    bad "[$m] did NOT flag non-kebab filename (exit $rc): $out"
  fi
  out=$(run "$m" "$WORK/good-kebab-name.md"); rc=$?
  if [ "$rc" -eq 0 ] && ! printf '%s' "$out" | grep -q 'filename'; then
    ok "[$m] kebab filename passed clean"
  else
    bad "[$m] wrongly flagged kebab filename (exit $rc): $out"
  fi
done

echo
echo "lint-vault yaml check: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
