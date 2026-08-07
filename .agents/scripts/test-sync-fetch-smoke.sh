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
# Covers the guarantees added for tag/SHA pinning (issue #56 + review of PR #76):
#   1. a TAG pin fetches via refs/tags/<ref>; tags are tried BEFORE heads (git's
#      own refname precedence), and a name existing in BOTH namespaces vendors
#      the tag with a loud ambiguity warning
#   2. a COMMIT-SHA pin fetches via the bare /tar.gz/<sha> URL
#   3. an unfetchable EXPLICIT pin falls back to main WITH a loud PIN FALLBACK
#      warning; an implicit-default source (no ref) falls back QUIETLY
#   4. the lock records per-source {name, repo, ref, ref_type, fetched_sha} —
#      SHA resolved via the ref itself (SHA pin), the PEELED tag from git
#      ls-remote (never the tag-object SHA), or the tarball ETag (incl. weak
#      W/"..." shape); an explicit fallback leaves a fallback_from breadcrumb
#      that --status surfaces with a nonzero exit
#   5. a legacy names-only lock is readable; the first sync rewrites it in the
#      enriched schema with .skills/.agents name arrays intact
#   6. carry-forward: a source that fails to download (or downloads but yields
#      zero skills) on a later run keeps its previous lock provenance entry
#
# Exits non-zero if any assertion fails.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
command -v jq >/dev/null || { echo "jq is required"; exit 1; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
pass=0; fail=0
ok()  { echo "  ok:   $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }

SHA_TAG="1111111111111111111111111111111111111111"    # commit the v1 tag peels to
SHA_TAGOBJ="4444444444444444444444444444444444444444" # v1's annotated-tag OBJECT (decoy)
SHA_MAIN="2222222222222222222222222222222222222222"
SHA_PIN="3333333333333333333333333333333333333333"
SHA_BOTH_TAG="5555555555555555555555555555555555555555"
SHA_BOTH_TAGOBJ="6666666666666666666666666666666666666666"
SHA_BOTH_BRANCH="7777777777777777777777777777777777777777"
SHA_QUIET="8888888888888888888888888888888888888888"

# --- scratch repo with the REAL script (ROOT follows the script's location) ---
SANDBOX="$WORK/repo"
mkdir -p "$SANDBOX/.agents/scripts"
cp "$ROOT/.agents/scripts/sync-skills.sh" "$SANDBOX/.agents/scripts/sync-skills.sh"

cat > "$SANDBOX/.agents/skill-sources.json" <<EOF
{ "sources": [
  { "name": "tagged", "repo": "up/tagged", "ref": "v1",       "skillsPath": "skills" },
  { "name": "pinned", "repo": "up/pinned", "ref": "$SHA_PIN", "skillsPath": "skills" },
  { "name": "gone",   "repo": "up/gone",   "ref": "v9",       "skillsPath": "skills" },
  { "name": "quiet",  "repo": "up/quiet",                     "skillsPath": "skills" },
  { "name": "both",   "repo": "up/both",   "ref": "v1",       "skillsPath": "skills" }
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
mkupstream tagged-v1  "tagged-v1"        alpha-tag   "from the v1 tag"
mkupstream pinned-sha "pinned-$SHA_PIN"  alpha-sha   "from the pinned sha"
mkupstream gone-main  "gone-main"        alpha-gone  "from main fallback"
mkupstream quiet-mstr "quiet-master"     alpha-quiet "from quiet master"
mkupstream both-v1    "both-v1"          alpha-both  "from the both tag"
# A tarball that downloads fine but contains NO skillsPath (zero-skills run-2 case).
mkdir -p "$WORK/src-empty/both-empty"; printf 'nothing\n' > "$WORK/src-empty/both-empty/README.md"
tar -czf "$WORK/empty.tgz" -C "$WORK/src-empty" "both-empty"

# --- mock curl: serves the tarballs for exact codeload URLs, fails the rest ---
# Kill switches for run 2: kill-tagged (download failure), empty-both (zero skills).
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
case "\$url" in
  */up/tagged/*) [ -f "$WORK/kill-tagged" ] && exit 22 ;;
esac
serve() { cp "\$1" "\$out" && { [ -z "\$hdr" ] || printf 'ETag: %s\r\n' "\$2" > "\$hdr"; }; exit 0; }
case "\$url" in
  */up/tagged/tar.gz/refs/tags/v1)     serve "$WORK/tagged-v1.tgz"  '"$SHA_TAGOBJ"' ;;
  */up/pinned/tar.gz/$SHA_PIN)         serve "$WORK/pinned-sha.tgz" '"$SHA_PIN"' ;;
  */up/gone/tar.gz/refs/heads/main)    serve "$WORK/gone-main.tgz"  'W/"$SHA_MAIN"' ;;
  */up/quiet/tar.gz/refs/heads/master) serve "$WORK/quiet-mstr.tgz" '"$SHA_QUIET"' ;;
  */up/both/tar.gz/refs/tags/v1)
    if [ -f "$WORK/empty-both" ]; then serve "$WORK/empty.tgz" '"$SHA_BOTH_TAG"'
    else serve "$WORK/both-v1.tgz" '"$SHA_BOTH_TAG"'; fi ;;
  *) exit 22 ;;
esac
EOF
chmod +x "$WORK/bin/curl"

# --- mock git: peeled-tag listings; fails for repos with no listed refs so the
# --- 'gone' and 'quiet' sources exercise the ETag resolution path ---
cat > "$WORK/bin/git" <<EOF
#!/bin/sh
if [ "\$1" = "ls-remote" ]; then
  case "\$*" in
    *up/tagged*)
      printf '%s\trefs/tags/v1\n'    "$SHA_TAGOBJ"
      printf '%s\trefs/tags/v1^{}\n' "$SHA_TAG"
      exit 0 ;;
    *up/both*)
      printf '%s\trefs/heads/v1\n'   "$SHA_BOTH_BRANCH"
      printf '%s\trefs/tags/v1\n'    "$SHA_BOTH_TAGOBJ"
      printf '%s\trefs/tags/v1^{}\n' "$SHA_BOTH_TAG"
      exit 0 ;;
  esac
  exit 2
fi
exit 0
EOF
chmod +x "$WORK/bin/git"

# --- run 1 ---
OUT="$WORK/out.txt"
PATH="$WORK/bin:$PATH" bash "$SANDBOX/.agents/scripts/sync-skills.sh" > "$OUT" 2>&1
rc=$?
CANON="$SANDBOX/.agents/skills"
NEWLOCK="$SANDBOX/.agents/skill-sources.lock.json"

echo "== 1: tag precedence (tags tried before heads) + ambiguity warning =="
[ "$rc" -eq 0 ] && ok "sync exits 0" || { bad "sync exited $rc"; sed 's/^/    | /' "$OUT"; }
grep -q "from the v1 tag" "$CANON/alpha-tag/SKILL.md" 2>/dev/null \
  && ok "alpha-tag vendored from the v1 TAG content" || bad "alpha-tag missing or not the tag content"
grep -q "from the both tag" "$CANON/alpha-both/SKILL.md" 2>/dev/null \
  && ok "tag-and-branch name vendored the TAG" || bad "'both' did not vendor the tag content"
grep "BOTH a tag and a branch" "$OUT" | grep -q "up/both" \
  && ok "ambiguity warning for up/both" || bad "no ambiguity warning for up/both"
grep "BOTH a tag and a branch" "$OUT" | grep -q "up/tagged" \
  && bad "spurious ambiguity warning for tag-only repo" || ok "no ambiguity warning for tag-only repo"

echo "== 2: commit-SHA pin fetches via the bare tarball URL =="
grep -q "from the pinned sha" "$CANON/alpha-sha/SKILL.md" 2>/dev/null \
  && ok "alpha-sha vendored from the pinned-SHA tarball" || bad "alpha-sha missing or wrong content"

echo "== 3: explicit-pin fallback is LOUD; implicit-default fallback stays quiet =="
[ -f "$CANON/alpha-gone/SKILL.md" ] \
  && ok "'gone' still vendored via the main fallback" || bad "'gone' fallback did not vendor"
grep "PIN FALLBACK" "$OUT" | grep -q "'gone'" \
  && ok "PIN FALLBACK warning names 'gone'" || bad "no loud PIN FALLBACK warning for 'gone'"
grep -q "pins are NOT in effect" "$OUT" \
  && ok "end-of-run pin-fallback summary printed" || bad "no end-of-run pin-fallback summary"
if grep "PIN FALLBACK" "$OUT" | grep -Eq "'tagged'|'pinned'|'both'|'quiet'"; then
  bad "honored pin or implicit-default source wrongly reported as fallback"
else
  ok "no fallback warning for honored pins or the ref-less source"
fi
grep -q "from quiet master" "$CANON/alpha-quiet/SKILL.md" 2>/dev/null \
  && ok "ref-less source fell back main->master and vendored" || bad "'quiet' master fallback did not vendor"

echo "== 4: lock records {name, repo, ref, ref_type, fetched_sha} (+fallback_from) =="
jq -e '.sources | length == 5' "$NEWLOCK" >/dev/null 2>&1 \
  && ok "lock has 5 source entries" || bad "lock .sources missing/wrong length: $(jq -c '.sources | length' "$NEWLOCK")"
jq -e --arg sha "$SHA_TAG" \
   '.sources[] | select(.name=="tagged") | .repo=="up/tagged" and .ref=="v1" and .ref_type=="tag" and .fetched_sha==$sha and (has("fallback_from") | not)' \
   "$NEWLOCK" >/dev/null 2>&1 \
  && ok "tagged: PEELED commit SHA recorded (not the tag-object SHA)" \
  || bad "tagged entry wrong: $(jq -c '.sources[]? | select(.name=="tagged")' "$NEWLOCK")"
jq -e --arg sha "$SHA_PIN" \
   '.sources[] | select(.name=="pinned") | .ref==$sha and .ref_type=="commit" and .fetched_sha==$sha' \
   "$NEWLOCK" >/dev/null 2>&1 \
  && ok "pinned: a 40-hex ref records itself, ref_type commit" \
  || bad "pinned entry wrong: $(jq -c '.sources[]? | select(.name=="pinned")' "$NEWLOCK")"
jq -e --arg sha "$SHA_MAIN" \
   '.sources[] | select(.name=="gone") | .ref=="main" and .ref_type=="branch" and .fetched_sha==$sha and .fallback_from=="v9"' \
   "$NEWLOCK" >/dev/null 2>&1 \
  && ok "gone: truthful fallback ref + weak-ETag SHA + fallback_from breadcrumb" \
  || bad "gone entry wrong: $(jq -c '.sources[]? | select(.name=="gone")' "$NEWLOCK")"
jq -e --arg sha "$SHA_QUIET" \
   '.sources[] | select(.name=="quiet") | .ref=="master" and .ref_type=="branch" and .fetched_sha==$sha and (has("fallback_from") | not)' \
   "$NEWLOCK" >/dev/null 2>&1 \
  && ok "quiet: implicit-default fallback recorded WITHOUT a fallback_from" \
  || bad "quiet entry wrong: $(jq -c '.sources[]? | select(.name=="quiet")' "$NEWLOCK")"
jq -e --arg sha "$SHA_BOTH_TAG" \
   '.sources[] | select(.name=="both") | .ref_type=="tag" and .fetched_sha==$sha' \
   "$NEWLOCK" >/dev/null 2>&1 \
  && ok "both: tag namespace + peeled SHA recorded" \
  || bad "both entry wrong: $(jq -c '.sources[]? | select(.name=="both")' "$NEWLOCK")"

echo "== 5: legacy names-only lock readable; rewritten in the enriched schema =="
jq -e '.skills | sort == ["alpha-both","alpha-gone","alpha-quiet","alpha-sha","alpha-tag"]' "$NEWLOCK" >/dev/null 2>&1 \
  && ok ".skills name array intact (legacy 'stale-old' reconciled away)" || bad ".skills wrong: $(jq -c '.skills' "$NEWLOCK")"
jq -e '(.agents == []) and has("sources")' "$NEWLOCK" >/dev/null 2>&1 \
  && ok "enriched schema {skills, agents, sources} written" || bad "lock schema not enriched"

echo "== 6: --status surfaces the fallback_from breadcrumb with nonzero exit =="
SOUT="$(MIRROR_MANIFEST="$WORK/no-manifest.json" bash "$SANDBOX/.agents/scripts/sync-skills.sh" --status 2>&1)"
src=$?
[ "$src" -ne 0 ] && ok "--status exits nonzero with a recorded pin fallback" || bad "--status exited 0 despite pin fallback"
printf '%s' "$SOUT" | grep -q "NOT at their pin" \
  && ok "--status names the off-pin condition" || bad "--status silent about the pin fallback"
printf '%s' "$SOUT" | grep -q "gone: pinned v9" \
  && ok "--status shows pinned ref -> vendored ref" || bad "--status missing the pin detail line"

echo "== 7: carry-forward — failing / zero-skill sources keep run-1 provenance =="
touch "$WORK/kill-tagged" "$WORK/empty-both"
OUT2="$WORK/out2.txt"
PATH="$WORK/bin:$PATH" bash "$SANDBOX/.agents/scripts/sync-skills.sh" > "$OUT2" 2>&1
rc2=$?
[ "$rc2" -eq 0 ] && ok "run 2 exits 0 despite partial failures" || { bad "run 2 exited $rc2"; sed 's/^/    | /' "$OUT2"; }
grep -q "download failed; keeping last-good copy for tagged" "$OUT2" \
  && ok "run 2: tagged download failure detected" || bad "run 2: tagged failure not reported"
grep -q "both yielded no skills/agents" "$OUT2" \
  && ok "run 2: 'both' zero-skills failure detected" || bad "run 2: zero-skills case not reported"
[ -f "$CANON/alpha-tag/SKILL.md" ] && [ -f "$CANON/alpha-both/SKILL.md" ] \
  && ok "last-good skills still on disk" || bad "last-good skills were pruned on a failing run"
jq -e --arg sha "$SHA_TAG" \
   '.sources[] | select(.name=="tagged") | .ref=="v1" and .fetched_sha==$sha' \
   "$NEWLOCK" >/dev/null 2>&1 \
  && ok "tagged provenance carried forward (download-failure branch)" \
  || bad "tagged provenance lost: $(jq -c '.sources[]? | select(.name=="tagged")' "$NEWLOCK")"
jq -e --arg sha "$SHA_BOTH_TAG" \
   '.sources[] | select(.name=="both") | .fetched_sha==$sha' \
   "$NEWLOCK" >/dev/null 2>&1 \
  && ok "'both' provenance carried forward (zero-skills branch)" \
  || bad "'both' provenance lost: $(jq -c '.sources[]? | select(.name=="both")' "$NEWLOCK")"
jq -e '.sources | length == 5' "$NEWLOCK" >/dev/null 2>&1 \
  && ok "run 2 lock still has 5 source entries" || bad "run 2 lock sources wrong length"

echo
echo "smoke: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
