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
#      W/"..." shape); a non-SHA ETag ("abc123-gzip", a 64-hex digest) records
#      EMPTY rather than a spurious substring; an explicit fallback leaves a
#      fallback_from breadcrumb
#   5. a legacy names-only lock is readable; the first sync rewrites it in the
#      enriched schema with .skills/.agents name arrays intact
#   6. --status exit contract: pin fallback exits 4 on an otherwise-clean
#      mirror, and 2 (mirror not installed) still wins as the lower code while
#      the pin warning is reported
#   7. carry-forward: a source that fails to download (or downloads but yields
#      zero skills) on a later run keeps its previous lock provenance entry
#   8. a lock that exists but is corrupt makes --status ERROR with exit 5
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
SHA64="9999999999999999999999999999999999999999999999999999999999999999"  # 64-hex decoy

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
  { "name": "both",   "repo": "up/both",   "ref": "v1",       "skillsPath": "skills" },
  { "name": "badetag",  "repo": "up/badetag",  "ref": "b1",   "skillsPath": "skills" },
  { "name": "longetag", "repo": "up/longetag", "ref": "b2",   "skillsPath": "skills" }
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
mkupstream badetag-b1 "badetag-b1"       alpha-be1   "non-sha etag"
mkupstream longetag-b2 "longetag-b2"     alpha-be2   "sixtyfour hex etag"
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
  */up/badetag/tar.gz/refs/tags/b1)    serve "$WORK/badetag-b1.tgz" '"abc123-gzip"' ;;
  */up/longetag/tar.gz/refs/tags/b2)   serve "$WORK/longetag-b2.tgz" '"$SHA64"' ;;
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
jq -e '.sources | length == 7' "$NEWLOCK" >/dev/null 2>&1 \
  && ok "lock has 7 source entries" || bad "lock .sources missing/wrong length: $(jq -c '.sources | length' "$NEWLOCK")"
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
jq -e '.sources[] | select(.name=="badetag") | .fetched_sha==""' "$NEWLOCK" >/dev/null 2>&1 \
  && ok "badetag: non-SHA ETag (\"abc123-gzip\") records EMPTY, not a substring" \
  || bad "badetag entry wrong: $(jq -c '.sources[]? | select(.name=="badetag")' "$NEWLOCK")"
jq -e '.sources[] | select(.name=="longetag") | .fetched_sha==""' "$NEWLOCK" >/dev/null 2>&1 \
  && ok "longetag: 64-hex ETag records EMPTY (no spurious 40-hex prefix)" \
  || bad "longetag entry wrong: $(jq -c '.sources[]? | select(.name=="longetag")' "$NEWLOCK")"
grep -q "could not resolve a commit SHA for badetag@b1" "$OUT" \
  && grep -q "could not resolve a commit SHA for longetag@b2" "$OUT" \
  && ok "empty-SHA note printed for both rejected ETags" || bad "missing empty-SHA note for rejected ETags"

echo "== 5: legacy names-only lock readable; rewritten in the enriched schema =="
jq -e '.skills | sort == ["alpha-be1","alpha-be2","alpha-both","alpha-gone","alpha-quiet","alpha-sha","alpha-tag"]' "$NEWLOCK" >/dev/null 2>&1 \
  && ok ".skills name array intact (legacy 'stale-old' reconciled away)" || bad ".skills wrong: $(jq -c '.skills' "$NEWLOCK")"
jq -e '(.agents == []) and has("sources")' "$NEWLOCK" >/dev/null 2>&1 \
  && ok "enriched schema {skills, agents, sources} written" || bad "lock schema not enriched"

echo "== 6: --status exit contract for the pin-fallback breadcrumb =="
# No mirror installed: the lower code (2) wins, but the pin condition still prints.
SOUT="$(MIRROR_MANIFEST="$WORK/no-manifest.json" bash "$SANDBOX/.agents/scripts/sync-skills.sh" --status 2>&1)"
src=$?
[ "$src" -eq 2 ] && ok "--status exits 2 (not installed wins as lower code)" || bad "--status rc=$src, want 2 (not installed + pin)"
printf '%s' "$SOUT" | grep -q "NOT at their pin" \
  && ok "pin condition still reported alongside" || bad "--status silent about the pin fallback"
printf '%s' "$SOUT" | grep -q "gone: pinned v9" \
  && ok "--status shows pinned ref -> vendored ref" || bad "--status missing the pin detail line"
# Clean, matching mirror manifest: the pin fallback is the ONLY condition -> exit 4.
hasher="sha256sum"; command -v sha256sum >/dev/null 2>&1 || hasher="shasum -a 256"
LHASH="$(jq -S '.skills | sort' "$NEWLOCK" | $hasher | cut -d' ' -f1)"
jq -n --arg h "$LHASH" --arg v "$SANDBOX" \
   '{owned:[], lock_hash:$h, vault_path:$v, written:"2026-01-01T00:00:00Z", exports:[]}' > "$WORK/mm.json"
SOUT="$(MIRROR_MANIFEST="$WORK/mm.json" bash "$SANDBOX/.agents/scripts/sync-skills.sh" --status 2>&1)"
src=$?
[ "$src" -eq 4 ] && ok "--status exits 4 when the pin fallback is the only condition" || bad "--status rc=$src, want 4 (pin code)"
printf '%s' "$SOUT" | grep -q "up to date with this vault's portable set" \
  && ok "mirror portion reads clean around the pin warning" || bad "mirror portion not clean in the exit-4 case"

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
jq -e '.sources | length == 7' "$NEWLOCK" >/dev/null 2>&1 \
  && ok "run 2 lock still has 7 source entries" || bad "run 2 lock sources wrong length"

echo "== 8: corrupt lock makes --status ERROR with exit 5 =="
printf '{"skills": [oops' > "$NEWLOCK"
SOUT="$(MIRROR_MANIFEST="$WORK/mm.json" bash "$SANDBOX/.agents/scripts/sync-skills.sh" --status 2>&1)"
src=$?
[ "$src" -eq 5 ] && ok "--status exits 5 on a corrupt lock" || bad "--status rc=$src on corrupt lock, want 5"
printf '%s' "$SOUT" | grep -q "not valid JSON" \
  && ok "corrupt lock reported with a clear ERROR message" || bad "no clear corrupt-lock error message"
printf '%s' "$SOUT" | grep -q "up to date with this vault's portable set" \
  && bad "corrupt lock still hashed as a comparison" || ok "no bogus up-to-date/stale verdict from a corrupt lock"

echo
echo "smoke: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
