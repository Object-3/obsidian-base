#!/usr/bin/env bash
# ── ENGINE FILE (base-owned) — AGENT NOTICE ─────────────────────────────────
# In a DERIVED VAULT (git origin is not the obsidian-base repo): if this script
# is buggy, do NOT fix it here and do NOT open a PR against the base repo —
# FILE A GITHUB ISSUE against the upstream base (.agents/.base-url if present,
# else Object-3/obsidian-base) with the error + proposed fix in the issue body.
# Local patches are overwritten by the next update-base and help no other clone.
# See AGENTS.md → "Engine bugs & improvements found in a derived vault".
# ─────────────────────────────────────────────────────────────────────────────
# Smoke test for tag/SHA pinning + the enriched lock in sync-skills.sh.
#
# Self-contained and OFFLINE: the real sync-skills.sh is copied into a scratch
# "repo" (ROOT derives from the script's own location, so nothing here touches
# this checkout), and `curl` / `git` are mocked in PATH — the mock curl serves
# pre-built local tarballs for specific codeload URLs and fails everything else.
# Run from anywhere in the repo:
#
#   .agents/scripts/test-sync-fetch-smoke.sh
#
# Covers the guarantees added for tag/SHA pinning (issue #56):
#   1. a TAG pin fetches via refs/tags/<ref> (heads fetch fails) — pin honored
#   2. a COMMIT-SHA pin fetches via the bare /tar.gz/<sha> URL — pin honored
#   3. an unfetchable EXPLICIT pin falls back to main WITH a loud PIN FALLBACK
#      warning (never silently), and honored pins emit no such warning
#   4. the lock records per-source {name, repo, ref, fetched_sha} — SHA resolved
#      via the ref itself (SHA pin), git ls-remote (tag), or the tarball ETag
#   5. a legacy names-only lock is readable; the first sync rewrites it in the
#      enriched schema with .skills/.agents name arrays intact
#
# Exits non-zero if any assertion fails.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
command -v jq >/dev/null || { echo "jq is required"; exit 1; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
pass=0; fail=0
ok()  { echo "  ok:   $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }

SHA_TAG="1111111111111111111111111111111111111111"
SHA_MAIN="2222222222222222222222222222222222222222"
SHA_PIN="3333333333333333333333333333333333333333"

# --- scratch repo with the REAL script (ROOT follows the script's location) ---
SANDBOX="$WORK/repo"
mkdir -p "$SANDBOX/.agents/scripts"
cp "$ROOT/.agents/scripts/sync-skills.sh" "$SANDBOX/.agents/scripts/sync-skills.sh"

cat > "$SANDBOX/.agents/skill-sources.json" <<EOF
{ "sources": [
  { "name": "tagged", "repo": "up/tagged", "ref": "v1",       "skillsPath": "skills" },
  { "name": "pinned", "repo": "up/pinned", "ref": "$SHA_PIN", "skillsPath": "skills" },
  { "name": "gone",   "repo": "up/gone",   "ref": "v9",       "skillsPath": "skills" }
] }
EOF

# Legacy names-only lock (pre-enrichment schema) — must be readable, then rewritten.
printf '{"skills":["stale-old"],"agents":[]}\n' > "$SANDBOX/.agents/skill-sources.lock.json"

# --- fake upstreams as local tarballs ---
mkupstream() { # tarball-stem top-dir skill-name marker-text
  local d="$WORK/src-$1"
  mkdir -p "$d/$2/skills/$3"
  printf -- '---\nname: %s\ndescription: %s\n---\n# %s\n' "$3" "$4" "$3" \
    > "$d/$2/skills/$3/SKILL.md"
  tar -czf "$WORK/$1.tgz" -C "$d" "$2"
}
mkupstream tagged-v1  "tagged-v1"        alpha-tag  "from the v1 tag"
mkupstream pinned-sha "pinned-$SHA_PIN"  alpha-sha  "from the pinned sha"
mkupstream gone-main  "gone-main"        alpha-gone "from main fallback"

# --- mock curl: serves the tarballs for exact codeload URLs, fails the rest ---
mkdir -p "$WORK/bin"
cat > "$WORK/bin/curl" <<EOF
#!/bin/sh
# mock codeload: understands  -fsSL [-D hdr] <url> -o <out>
url=""; out=""; hdr=""
while [ \$# -gt 0 ]; do
  case "\$1" in
    -o) out="\$2"; shift ;;
    -D) hdr="\$2"; shift ;;
    http*) url="\$1" ;;
  esac
  shift
done
serve() { cp "\$1" "\$out" && { [ -z "\$hdr" ] || printf 'ETag: "%s"\r\n' "\$2" > "\$hdr"; }; exit 0; }
case "\$url" in
  */up/tagged/tar.gz/refs/tags/v1)  serve "$WORK/tagged-v1.tgz"  "$SHA_TAG" ;;
  */up/pinned/tar.gz/$SHA_PIN)      serve "$WORK/pinned-sha.tgz" "$SHA_PIN" ;;
  */up/gone/tar.gz/refs/heads/main) serve "$WORK/gone-main.tgz"  "$SHA_MAIN" ;;
  *) exit 22 ;;
esac
EOF
chmod +x "$WORK/bin/curl"

# --- mock git: ls-remote resolves ONLY the tag pin (so 'gone' exercises the ETag path) ---
cat > "$WORK/bin/git" <<EOF
#!/bin/sh
if [ "\$1" = "ls-remote" ]; then
  case "\$*" in
    *up/tagged*) printf '%s\trefs/tags/v1\n' "$SHA_TAG"; exit 0 ;;
  esac
  exit 2
fi
exit 0
EOF
chmod +x "$WORK/bin/git"

# --- run the sandboxed sync ---
OUT="$WORK/out.txt"
PATH="$WORK/bin:$PATH" bash "$SANDBOX/.agents/scripts/sync-skills.sh" > "$OUT" 2>&1
rc=$?
CANON="$SANDBOX/.agents/skills"
NEWLOCK="$SANDBOX/.agents/skill-sources.lock.json"

echo "== 1: tag pin fetches via refs/tags (heads URL fails) =="
[ "$rc" -eq 0 ] && ok "sync exits 0" || { bad "sync exited $rc"; sed 's/^/    | /' "$OUT"; }
grep -q "from the v1 tag" "$CANON/alpha-tag/SKILL.md" 2>/dev/null \
  && ok "alpha-tag vendored from the v1 TAG content" || bad "alpha-tag missing or not the tag content"

echo "== 2: commit-SHA pin fetches via the bare tarball URL =="
grep -q "from the pinned sha" "$CANON/alpha-sha/SKILL.md" 2>/dev/null \
  && ok "alpha-sha vendored from the pinned-SHA tarball" || bad "alpha-sha missing or wrong content"

echo "== 3: unfetchable explicit pin falls back LOUDLY, honored pins stay quiet =="
[ -f "$CANON/alpha-gone/SKILL.md" ] \
  && ok "'gone' still vendored via the main fallback" || bad "'gone' fallback did not vendor"
grep "PIN FALLBACK" "$OUT" | grep -q "'gone'" \
  && ok "PIN FALLBACK warning names 'gone'" || bad "no loud PIN FALLBACK warning for 'gone'"
grep -q "pins are NOT in effect" "$OUT" \
  && ok "end-of-run pin-fallback summary printed" || bad "no end-of-run pin-fallback summary"
if grep "PIN FALLBACK" "$OUT" | grep -Eq "'tagged'|'pinned'"; then
  bad "honored pin wrongly reported as fallback"
else
  ok "no fallback warning for the honored tag/SHA pins"
fi

echo "== 4: lock records per-source {name, repo, ref, fetched_sha} =="
jq -e '.sources | length == 3' "$NEWLOCK" >/dev/null 2>&1 \
  && ok "lock has 3 source entries" || bad "lock .sources missing/wrong length"
jq -e --arg sha "$SHA_TAG" \
   '.sources[] | select(.name=="tagged") | .repo=="up/tagged" and .ref=="v1" and .fetched_sha==$sha' \
   "$NEWLOCK" >/dev/null 2>&1 \
  && ok "tagged: ref v1 + SHA via git ls-remote" || bad "tagged entry wrong: $(jq -c '.sources[]? | select(.name=="tagged")' "$NEWLOCK")"
jq -e --arg sha "$SHA_PIN" \
   '.sources[] | select(.name=="pinned") | .ref==$sha and .fetched_sha==$sha' \
   "$NEWLOCK" >/dev/null 2>&1 \
  && ok "pinned: a 40-hex ref records itself as fetched_sha" || bad "pinned entry wrong: $(jq -c '.sources[]? | select(.name=="pinned")' "$NEWLOCK")"
jq -e --arg sha "$SHA_MAIN" \
   '.sources[] | select(.name=="gone") | .ref=="main" and .fetched_sha==$sha' \
   "$NEWLOCK" >/dev/null 2>&1 \
  && ok "gone: fallback ref recorded truthfully + SHA via the tarball ETag" || bad "gone entry wrong: $(jq -c '.sources[]? | select(.name=="gone")' "$NEWLOCK")"

echo "== 5: legacy names-only lock readable; rewritten in the enriched schema =="
jq -e '.skills | sort == ["alpha-gone","alpha-sha","alpha-tag"]' "$NEWLOCK" >/dev/null 2>&1 \
  && ok ".skills name array intact (legacy 'stale-old' reconciled away)" || bad ".skills wrong: $(jq -c '.skills' "$NEWLOCK")"
jq -e '(.agents == []) and has("sources")' "$NEWLOCK" >/dev/null 2>&1 \
  && ok "enriched schema {skills, agents, sources} written" || bad "lock schema not enriched"

echo
echo "smoke: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
