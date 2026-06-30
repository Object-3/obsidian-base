#!/usr/bin/env bash
# ===========================================================================
# setup-sensitive-plane.sh — durability / multi-device backing for `_sensitive/`
# ===========================================================================
# The Sensitive plane is the gitignored `_sensitive/` folder: candid, named,
# number-heavy notes that must stay OUT of git but ARE first-class Obsidian
# notes (graph, links, search). Its real weakness is that it's single-machine,
# unbacked, and not multi-device. This script operationalizes the validated fix:
# back `_sensitive/` with an org-tenant cloud-synced folder, WITHOUT putting it
# in git or breaking Obsidian — applying the proven-safe config.
#
# (Earlier base versions called this folder `_local/`. That name was a misnomer
# once it's cloud-backed, so it's now `_sensitive/`. Legacy `_local/` is still
# gitignored for safety; `migrate` renames it on disk.)
#
# It is the mechanical core driven by the `/setup-sensitive-plane` skill, which
# owns the judgment (provider choice, org-vs-personal warnings, agent-read
# wiring). Everything here is read-only or idempotent — safe to re-run.
#
# Subcommands:
#   detect            (default) OS, detected cloud-sync clients, `_sensitive/`
#                     state, any legacy `_local/`, and the recorded choice. Read-only.
#   migrate           Rename a legacy `_local/` → `_sensitive/` on disk (or
#                     re-point its symlink). Idempotent; no-ops if already done.
#   link              Point `_sensitive/` at a cloud-backed folder via symlink,
#                     migrating existing contents. Idempotent; no-ops if already
#                     linked to the same target. Requires --backing-dir.
#   unlink            Restore `_sensitive/` to a plain local directory (keeps the
#                     notes; just removes the symlink indirection). Idempotent.
#   verify            Probe round-trip: write a note into `_sensitive/`, confirm it
#                     materializes (non-zero, readable — not a 0-byte stub), then
#                     remove it. Idempotent.
#   check             Proven-safe non-negotiables we can check locally
#                     (.obsidian/ outside the synced subtree, no whole-vault
#                     sync, no 0-byte dehydration stubs). Read-only.
#   record            Write/update the Sensitive-plane block in vault-profile.md
#                     (provider/account/mechanism/agent-read). Idempotent.
#   explain           Print a plain-English, non-technical "here's your private
#                     folder and how to use it" card (tailored to the recorded
#                     provider). Re-runnable anytime. Read-only.
#
# Flags (for link / record):
#   --provider <s>      free-text provider class (e.g. "Google Workspace / Drive")
#   --account-type <s>  org | personal
#   --backing-dir <d>   absolute path of the cloud-synced folder (link/record)
#   --mechanism <s>     symlink | drive-mirror | obsidian-sync | scripted-backup
#   --agent-read <s>    how headless agents read it (e.g. "Google service account")
#   --force             allow link to re-point an existing differing symlink
#   --yes               non-interactive (assume yes to prompts)
#
# Override the vault root for testing:  VAULT_ROOT=/path/to/vault ...
set -euo pipefail

VAULT_ROOT="${VAULT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
cd "$VAULT_ROOT"
PLANE="$VAULT_ROOT/_sensitive"          # the Sensitive plane (current name)
LEGACY="$VAULT_ROOT/_local"             # pre-rename name; still gitignored for safety
PROFILE="$VAULT_ROOT/.agents/vault-profile.md"
BEGIN_MARK="<!-- BEGIN sensitive-plane (managed by setup-sensitive-plane) -->"
END_MARK="<!-- END sensitive-plane -->"

c_say()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
c_ok()   { printf '\033[1;32m  ✓ %s\033[0m\n' "$*"; }
c_warn() { printf '\033[1;33m  ! %s\033[0m\n' "$*" >&2; }
c_err()  { printf '\033[1;31m  ✗ %s\033[0m\n' "$*" >&2; }
die()    { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

# ---- arg parsing ----------------------------------------------------------
CMD="${1:-detect}"; [ $# -gt 0 ] && shift || true
PROVIDER=""; ACCOUNT_TYPE=""; BACKING_DIR=""; MECHANISM=""; AGENT_READ=""
FORCE=""; ASSUME_YES=""
while [ $# -gt 0 ]; do
  case "$1" in
    --provider)     PROVIDER="${2:-}"; shift 2 ;;
    --account-type) ACCOUNT_TYPE="${2:-}"; shift 2 ;;
    --backing-dir)  BACKING_DIR="${2:-}"; shift 2 ;;
    --mechanism)    MECHANISM="${2:-}"; shift 2 ;;
    --agent-read)   AGENT_READ="${2:-}"; shift 2 ;;
    --force)        FORCE=1; shift ;;
    --yes)          ASSUME_YES=1; shift ;;
    *) die "unknown flag: $1" ;;
  esac
done

OS="$(uname -s)"

# ---- shared helpers -------------------------------------------------------

# Print the absolute symlink target of $1, or empty if it's not a symlink.
link_target() { # path
  [ -L "$1" ] || return 0
  command -v readlink >/dev/null 2>&1 && { readlink "$1" 2>/dev/null || true; }
}

# Describe the state of a path: missing | dir | symlink | other.
path_state() { # path
  if [ -L "$1" ]; then echo "symlink"
  elif [ -d "$1" ]; then echo "dir"
  elif [ -e "$1" ]; then echo "other"
  else echo "missing"; fi
}

inside_git() { git -C "$VAULT_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; }

# Is $1 equal to, or an ancestor of, $2?  (both must exist)
is_ancestor() { # ancestor child
  local a c
  a="$(cd "$1" 2>/dev/null && pwd -P || echo /__nope_a__)"
  c="$(cd "$2" 2>/dev/null && pwd -P || echo /__nope_c__)"
  case "$c" in "$a"|"$a"/*) return 0 ;; *) return 1 ;; esac
}

# ---- detect ---------------------------------------------------------------
detect_clients() {
  # Emit "PROVIDER<TAB>ACCOUNT_HINT<TAB>PATH" lines for every cloud root found.
  local hint d
  shopt -s nullglob 2>/dev/null || true
  if [ "$OS" = "Darwin" ]; then
    for d in "$HOME/Library/CloudStorage/"OneDrive-* ; do
      case "$d" in *OneDrive-Personal) hint="personal" ;; *) hint="org?" ;; esac
      printf 'Microsoft 365 / OneDrive\t%s\t%s\n' "$hint" "$d"
    done
    for d in "$HOME/Library/CloudStorage/"GoogleDrive-* ; do
      case "$d" in *@gmail.com) hint="personal" ;; *) hint="org?" ;; esac
      printf 'Google Workspace / Drive\t%s\t%s\n' "$hint" "$d"
    done
    for d in "$HOME/Library/CloudStorage/"Dropbox* ; do
      printf 'Dropbox (not for confidential)\t?\t%s\n' "$d"
    done
    for d in "$HOME/Library/CloudStorage/"Box-* ; do
      printf 'Box\t?\t%s\n' "$d"
    done
    [ -d "$HOME/Library/Mobile Documents/com~apple~CloudDocs" ] && \
      printf 'iCloud Drive (NOT for NDA material)\tpersonal\t%s\n' "$HOME/Library/Mobile Documents/com~apple~CloudDocs"
    [ -d "$HOME/OneDrive" ] && printf 'Microsoft 365 / OneDrive (legacy path)\t?\t%s\n' "$HOME/OneDrive"
    [ -d "$HOME/Google Drive" ] && printf 'Google Workspace / Drive (legacy path)\t?\t%s\n' "$HOME/Google Drive"
  else
    for d in "$HOME/OneDrive" "$HOME/onedrive"; do [ -d "$d" ] && printf 'OneDrive (Linux client)\t?\t%s\n' "$d"; done
    for d in "$HOME/GoogleDrive" "$HOME/google-drive" "$HOME/gdrive"; do [ -d "$d" ] && printf 'Google Drive (Linux client)\t?\t%s\n' "$d"; done
    [ -d "$HOME/Dropbox" ] && printf 'Dropbox (not for confidential)\t?\t%s\n' "$HOME/Dropbox"
  fi
}

cmd_detect() {
  c_say "Sensitive-plane backing store — current state"
  echo "  OS:            $OS"
  echo "  Vault root:    $VAULT_ROOT"
  local st; st="$(path_state "$PLANE")"
  echo "  _sensitive/:   $st$([ "$st" = symlink ] && printf ' → %s' "$(link_target "$PLANE")")"
  local lst; lst="$(path_state "$LEGACY")"
  if [ "$lst" != "missing" ]; then
    c_warn "Legacy _local/ present ($lst). Run 'migrate' to rename it → _sensitive/ (it stays gitignored either way)."
  fi

  echo
  c_say "Detected cloud-sync clients (org tenant required for confidential):"
  local found="" provider hint path
  while IFS=$'\t' read -r provider hint path; do
    [ -n "${provider:-}" ] || continue
    found=1
    printf '  • %-42s [%s]\n      %s\n' "$provider" "$hint" "$path"
  done < <(detect_clients)
  [ -n "$found" ] || echo "  (none found — install an org-tenant cloud client, or use a fallback)"

  echo
  c_say "Recorded choice (.agents/vault-profile.md):"
  if [ -f "$PROFILE" ] && grep -qF "$BEGIN_MARK" "$PROFILE"; then
    awk -v b="$BEGIN_MARK" -v e="$END_MARK" '
      index($0,b){p=1; next} index($0,e){p=0} p{print "  " $0}' "$PROFILE"
  else
    echo "  (not configured — run: setup-sensitive-plane record …)"
  fi
}

# ---- migrate (legacy _local/ → _sensitive/) -------------------------------
cmd_migrate() {
  local lst pst; lst="$(path_state "$LEGACY")"; pst="$(path_state "$PLANE")"
  if [ "$lst" = "missing" ]; then
    c_ok "No legacy _local/ to migrate (idempotent)."
    return 0
  fi
  if [ "$pst" != "missing" ]; then
    die "Both _local/ and _sensitive/ exist. Merge _local/'s contents into _sensitive/ by hand, then remove _local/ (refusing to clobber)."
  fi
  if [ "$lst" = "symlink" ]; then
    local tgt; tgt="$(link_target "$LEGACY")"
    rm -f "$LEGACY"; ln -s "$tgt" "$PLANE"
    c_ok "Re-pointed symlink: _local/ → _sensitive/ (still → $tgt)."
  else
    mv "$LEGACY" "$PLANE"
    c_ok "Renamed _local/ → _sensitive/ (contents preserved)."
  fi
  if inside_git && [ -n "$(git -C "$VAULT_ROOT" ls-files -- _local 2>/dev/null)" ]; then
    git -C "$VAULT_ROOT" rm -r --cached --quiet --ignore-unmatch -- _local >/dev/null 2>&1 || true
    c_ok "Untracked stale _local/ placeholder paths from git."
  fi
  c_warn "Both _local/ and _sensitive/ stay gitignored — no confidential note is ever exposed by the rename."
}

# ---- link -----------------------------------------------------------------
cmd_link() {
  [ -n "$BACKING_DIR" ] || die "link requires --backing-dir <absolute path inside the cloud-synced root>"
  case "$BACKING_DIR" in /*) ;; *) die "--backing-dir must be an absolute path (got: $BACKING_DIR)";; esac

  mkdir -p "$BACKING_DIR"
  if is_ancestor "$VAULT_ROOT" "$BACKING_DIR"; then
    die "--backing-dir is inside the vault ($VAULT_ROOT). The cloud folder must live in the cloud-synced root, outside the vault."
  fi

  local st target want; st="$(path_state "$PLANE")"
  want="$(cd "$BACKING_DIR" && pwd -P)"
  if [ "$st" = "symlink" ]; then
    target="$(cd "$(link_target "$PLANE")" 2>/dev/null && pwd -P || echo "$(link_target "$PLANE")")"
    if [ "$target" = "$want" ]; then
      c_ok "_sensitive/ already linked to $want — nothing to do (idempotent)."
      return 0
    fi
    [ -n "$FORCE" ] || die "_sensitive/ is already a symlink → $target. Re-point with --force, or run 'unlink' first."
    c_warn "Re-pointing _sensitive/ from $target to $want (--force)."
    rm -f "$PLANE"; st="missing"
  fi

  if [ "$st" = "dir" ]; then
    c_say "Migrating existing _sensitive/ contents into $BACKING_DIR …"
    local moved=0 f base
    shopt -s dotglob nullglob 2>/dev/null || true
    for f in "$PLANE"/*; do
      base="$(basename "$f")"
      if [ -e "$BACKING_DIR/$base" ]; then c_warn "skip (already in backing dir): $base"
      else mv "$f" "$BACKING_DIR/"; moved=$((moved+1)); fi
    done
    shopt -u dotglob 2>/dev/null || true
    c_ok "Migrated $moved item(s)."
    rmdir "$PLANE" 2>/dev/null || rm -rf "$PLANE"
  elif [ "$st" = "other" ]; then
    die "_sensitive exists and is neither a directory nor a symlink — refusing to touch it."
  fi

  ln -s "$BACKING_DIR" "$PLANE"
  c_ok "Linked _sensitive/ → $BACKING_DIR"

  if [ ! -e "$BACKING_DIR/README.md" ]; then
    cat > "$BACKING_DIR/README.md" <<'RM'
# Sensitive plane (cloud-backed `_sensitive/`)

This folder is the backing store for the vault's gitignored `_sensitive/` plane —
surfaced into the vault as `_sensitive/` via a symlink. It is **cloud-synced for
durability/multi-device** but **never in git**. Keep these notes pinned-local
(no online-only/dehydration), and let only ONE sync engine touch this path.
RM
    c_ok "Seeded $BACKING_DIR/README.md"
  fi

  # Git hygiene: stop tracking placeholder files (behind the symlink now) and
  # ignore the bare `_sensitive` symlink. Idempotent.
  if inside_git && [ -n "$(git -C "$VAULT_ROOT" ls-files -- _sensitive 2>/dev/null)" ]; then
    git -C "$VAULT_ROOT" rm -r --cached --quiet --ignore-unmatch -- _sensitive >/dev/null 2>&1 || true
    c_ok "Untracked the old _sensitive/ placeholder files from git (notes were never tracked)."
  fi
  if inside_git; then
    local gi="$VAULT_ROOT/.gitignore"
    if [ -f "$gi" ] && ! grep -qxF "/_sensitive" "$gi"; then
      printf '\n# Bare `_sensitive` symlink (cloud-backed Sensitive plane; see setup-sensitive-plane)\n/_sensitive\n' >> "$gi"
      c_ok "Added /_sensitive to .gitignore (the symlink itself stays out of git)."
    fi
  fi

  echo
  c_warn "Filesystem link done. Still REQUIRED (provider GUI — see /setup-sensitive-plane):"
  echo "    1. Pin the backing folder LOCAL ('Always keep on this device' / disable"
  echo "       Files-On-Demand / Optimize-Storage) so files never dehydrate to 0-byte stubs."
  echo "    2. Only the cloud client touches this path — never Obsidian Sync / Obsidian-Git too."
  echo "    3. Agents read via the provider API (service account / app-only), not the sync client."
  echo "  Then run:  setup-sensitive-plane verify   and   setup-sensitive-plane check"
}

# ---- unlink ---------------------------------------------------------------
cmd_unlink() {
  local st; st="$(path_state "$PLANE")"
  if [ "$st" != "symlink" ]; then
    c_ok "_sensitive/ is not a symlink ($st) — nothing to unlink (idempotent)."
    return 0
  fi
  local target; target="$(link_target "$PLANE")"
  rm -f "$PLANE"; mkdir -p "$PLANE"
  if [ -d "$target" ]; then
    c_say "Copying contents back from $target into a plain _sensitive/ …"
    shopt -s dotglob nullglob 2>/dev/null || true
    cp -R "$target"/* "$PLANE"/ 2>/dev/null || true
    shopt -u dotglob 2>/dev/null || true
  fi
  [ -f "$PLANE/.gitkeep" ] || : > "$PLANE/.gitkeep"
  c_ok "_sensitive/ is now a plain local directory again (backing store at $target left intact)."
  c_warn "Re-tracking placeholders / removing the /_sensitive gitignore line is left to you (review git status)."
}

# ---- verify ---------------------------------------------------------------
cmd_verify() {
  local st; st="$(path_state "$PLANE")"
  [ "$st" = "missing" ] && die "_sensitive/ does not exist. Run 'link' first, or create it."
  local probe=".sensitive-probe-$$-${RANDOM:-x}.md"
  local path="$PLANE/$probe"
  local content="probe written by setup-sensitive-plane at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  c_say "Writing probe note: _sensitive/$probe"
  printf '%s\n' "$content" > "$path" || die "could not write into _sensitive/ (permissions? path not materialized?)"
  local size; size="$(wc -c < "$path" | tr -d '[:space:]')"
  if [ "${size:-0}" -le 0 ]; then
    rm -f "$path"; die "probe is 0 bytes — the path may be online-only/dehydrated. Pin it LOCAL and retry."
  fi
  if ! grep -qF "$content" "$path"; then
    rm -f "$path"; die "probe content did not round-trip — the path is not reading back what was written."
  fi
  rm -f "$path"
  c_ok "Probe round-trip OK ($size bytes written, read back, removed). _sensitive/ is writable & materialized."
  c_warn "Cross-device sync can't be auto-verified — confirm the probe appears on a second device the first time."
}

# ---- check ----------------------------------------------------------------
cmd_check() {
  local fails=0
  c_say "Proven-safe checks (the ones verifiable locally):"

  # 1. .obsidian/ must NOT be inside the synced subtree.
  local target; target="$(link_target "$PLANE")"
  if [ -n "$target" ] && [ -d "$target" ] && is_ancestor "$target" "$VAULT_ROOT/.obsidian"; then
    c_err ".obsidian/ is INSIDE the synced backing dir — most collision-prone path. Move it out."
    fails=$((fails+1))
  else
    c_ok ".obsidian/ is outside the synced subtree."
  fi

  # 2. The whole vault must not itself live inside a cloud root.
  local vp; vp="$(cd "$VAULT_ROOT" && pwd -P)"
  case "$vp" in
    *"/Library/CloudStorage/"*|*"/Mobile Documents/"*|*"/Dropbox/"*|"$HOME/OneDrive"/*|"$HOME/Google Drive"/*)
      c_err "The whole vault is inside a cloud-synced root ($vp). Sync ONLY _sensitive/, not the vault."
      fails=$((fails+1)) ;;
    *) c_ok "Vault root is not itself inside a cloud-synced root." ;;
  esac

  # 3. No 0-byte .md files in _sensitive/ (dehydration symptom → 0-byte stubs).
  local stubs=0 f
  if [ -e "$PLANE" ]; then
    while IFS= read -r f; do [ -n "$f" ] && stubs=$((stubs+1)); done < <(find -L "$PLANE" -type f -name '*.md' -size 0 2>/dev/null)
  fi
  if [ "$stubs" -gt 0 ]; then
    c_err "$stubs zero-byte .md file(s) in _sensitive/ — likely online-only/dehydrated stubs. Pin LOCAL."
    fails=$((fails+1))
  else
    c_ok "No zero-byte .md stubs in _sensitive/ (no dehydration symptom)."
  fi

  echo
  c_warn "Cannot be auto-checked — confirm manually (provider settings / behavior):"
  echo "    • Files pinned LOCAL ('Always keep on this device'), never online-only."
  echo "    • Exactly ONE sync engine on this path (cloud client only; not Obsidian Sync/Git)."
  echo "    • Org tenant on a compliant provider (DPA/BAA) — never personal account for NDA'd data."
  echo "    • Agents read via the provider API (service account / app-only), not the sync client."

  echo
  if [ "$fails" -eq 0 ]; then c_ok "Local checks passed."; else c_err "$fails local check(s) failed — fix before storing confidential notes."; return 1; fi
}

# ---- record ---------------------------------------------------------------
cmd_record() {
  [ -f "$PROFILE" ] || die "vault-profile not found: $PROFILE"
  local prov="${PROVIDER:-_(unset)_}" acct="${ACCOUNT_TYPE:-_(unset)_}"
  local mech="${MECHANISM:-symlink}" aread="${AGENT_READ:-_(unset)_}"
  local loc="_sensitive/" when; when="$(date -u +%Y-%m-%d)"
  local st; st="$(path_state "$PLANE")"
  [ "$st" = "symlink" ] && loc="_sensitive/ → cloud-synced backing dir (resolve with: readlink _sensitive)"

  local warnline=""
  case "$acct" in
    personal) warnline="> [!warning] Personal account — NOT covered by a DPA/BAA. Fine for personal knowledge work; **inappropriate for NDA-bound / regulated material**. Move to an org tenant before storing confidential third-party data." ;;
  esac
  local resolve='`_sensitive/` directly'
  [ "$st" = "symlink" ] && resolve='`readlink _sensitive`'

  local block
  block="$(cat <<EOF
$BEGIN_MARK
## Sensitive plane backing store

Where the gitignored \`_sensitive/\` (Sensitive) plane physically lives and how agents reach it.
Maintained by \`/setup-sensitive-plane\`. No secrets/paths here (vault-profile is in git) —
the exact local path is resolved at runtime ($resolve).

- **Status:** configured ($when)
- **Provider:** $prov
- **Account type:** $acct
- **Mechanism:** $mech
- **Local location:** $loc
- **Headless agent read:** $aread
${warnline:+
$warnline
}
$END_MARK
EOF
)"

  BLOCK="$block" MB="$BEGIN_MARK" ME="$END_MARK" python3 - "$PROFILE" <<'PY'
import os, sys, re
path = sys.argv[1]
block = os.environ["BLOCK"].rstrip("\n")
b, e = os.environ["MB"], os.environ["ME"]
s = open(path, encoding="utf-8").read()
pat = re.compile(re.escape(b) + r".*?" + re.escape(e), re.S)
if pat.search(s):
    s = pat.sub(lambda _m: block, s)
else:
    if not s.endswith("\n"):
        s += "\n"
    s += "\n" + block + "\n"
open(path, "w", encoding="utf-8").write(s)
PY
  c_ok "Recorded the Sensitive-plane choice in .agents/vault-profile.md (idempotent — block replaced in place)."
}

# ---- explain (plain-English, non-technical user handoff) ------------------
# REQUIRED at the end of any setup: whenever a sensitive location is created, the
# user must be told it exists and how to use it — simply. Re-runnable anytime.
cmd_explain() {
  local prov="your work cloud account (Google Drive / OneDrive)"
  if [ -f "$PROFILE" ] && grep -qF "$BEGIN_MARK" "$PROFILE"; then
    local p; p="$(awk -v b="$BEGIN_MARK" -v e="$END_MARK" 'index($0,b){f=1} f; index($0,e){f=0}' "$PROFILE" \
      | sed -n 's/^- \*\*Provider:\*\* //p' | head -n1)"
    [ -n "$p" ] && [ "$p" != "_(unset)_" ] && prov="$p"
  fi
  cat <<EOF

  ┌─ Your private folder: _sensitive/ ──────────────────────────────────────┐

  You now have a folder called  _sensitive/  in your knowledge base. Think of it
  as the locked drawer — the private side of your notes.

  • WHAT GOES IN IT  — anything confidential: client or NDA material, financials,
    private people's details, candid notes you'd never want shared.

  • WHAT HAPPENS TO IT  — it's backed up to $prov
    and shows up on your other devices, but it NEVER goes to GitHub / the shared
    repo, and ONLY people you've shared that cloud folder with can ever see it.
    Everyone else on the knowledge base (and their AI) sees only your normal notes.

  • HOW TO USE IT  — in Obsidian it looks like any other folder. To keep something
    private, just put the note or file inside  _sensitive/ . That's the whole trick.

  • THE ONE RULE  — sensitive things go ONLY in _sensitive/. Anything you put in
    your normal notes is shared with everyone who has the knowledge base.

  └─────────────────────────────────────────────────────────────────────────┘
EOF
}

# ---- dispatch -------------------------------------------------------------
case "$CMD" in
  detect)  cmd_detect ;;
  migrate) cmd_migrate ;;
  link)    cmd_link ;;
  unlink)  cmd_unlink ;;
  verify)  cmd_verify ;;
  check)   cmd_check ;;
  record)  cmd_record ;;
  explain) cmd_explain ;;
  -h|--help|help) sed -n '2,52p' "$0" | sed 's/^# \{0,1\}//' ;;
  *) die "unknown command: $CMD (try: detect | migrate | link | unlink | verify | check | record | explain | help)" ;;
esac
