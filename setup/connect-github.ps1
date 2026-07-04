# ===========================================================================
# Connect an existing LOCAL vault to GitHub for backup/sync (Windows)
# ===========================================================================
# Optional, run anytime AFTER setup.ps1 from inside your vault folder. Creates a
# PRIVATE repo under your account OR an org you belong to, pushes, and sets it as
# 'origin'. Idempotent.
$ErrorActionPreference = "Stop"
function Have($c) { return [bool](Get-Command $c -ErrorAction SilentlyContinue) }
function Say($m) { Write-Host "==> $m" -ForegroundColor Cyan }

$root = (git rev-parse --show-toplevel) 2>$null
if (-not $root) { throw "Run this inside your vault folder." }
Set-Location $root

if (-not (Have gh)) { Say "Installing GitHub CLI..."; if (Have winget) { winget install --id GitHub.cli -e -h } else { throw "Install GitHub CLI from https://cli.github.com then re-run." } }
gh auth status 2>$null; if ($LASTEXITCODE -ne 0) { Say "Sign in to GitHub (a code will open in your browser)..."; gh auth login }

$defaultOwner = (gh api user --jq .login) 2>$null
Write-Host "Repo can live under your account or any org you belong to:"
(gh api user/orgs --jq '.[].login') 2>$null | ForEach-Object { Write-Host "  - (org) $_" }
$Owner = Read-Host "GitHub owner (your username or an org) [$defaultOwner]"; if (-not $Owner) { $Owner = $defaultOwner }
# NOTE: defaults to the folder name, not an "obsidian-<slug>" MCP label like the
# macOS/Linux script does -- setup.ps1 always wires the fixed legacy label
# "mcp-obsidian" (no per-vault label yet, since add-vault.ps1/multi-vault doesn't
# exist on Windows), so there's no vault-specific label to match here yet.
$defaultName = Split-Path $root -Leaf
$Repo = Read-Host "Repository name [$defaultName]"; if (-not $Repo) { $Repo = $defaultName }
$Vis = Read-Host "Visibility (private/public) [private]"; if (-not $Vis) { $Vis = "private" }

# Retry a push once with a larger post buffer if the first attempt fails -- works
# around a transient "RPC failed; HTTP 400 ... unexpected disconnect while reading
# sideband packet" seen in practice on an otherwise-tiny repo (not a size issue; a
# known HTTP/2 flakiness pattern).
function Push-WithRetry($remote, $branch) {
  git push -u $remote $branch
  if ($LASTEXITCODE -eq 0) { return }
  Say "Push failed (transient HTTP/2 hiccups happen) - retrying once with a larger post buffer..."
  git -c http.postBuffer=524288000 push -u $remote $branch
}

$origin = (git remote get-url origin) 2>$null
if ($origin) {
  Say "An 'origin' already exists ($origin); pushing to it."
  Push-WithRetry origin (git branch --show-current)
} else {
  Say "Creating $Owner/$Repo ($Vis) and pushing..."
  gh repo create "$Owner/$Repo" --$Vis --source=. --remote=origin --push
  if ($LASTEXITCODE -ne 0) {
    Say "gh repo create's push failed (the repo itself is very likely already created) - retrying the push..."
    Push-WithRetry origin (git branch --show-current)
  }
}

# 'origin' now exists, so it's safe to turn on Obsidian Git's auto-sync.
# setup.ps1 ships it OFF so a vault with no 'origin' yet never auto-pushes.
# (The 'base' remote is no longer standing -- update-base.sh adds it only
# per-fetch and removes it -- so it can't be offered as an auto-sync target
# and leak private notes into the public template.)
$gitPluginData = Join-Path $root ".obsidian\plugins\obsidian-git\data.json"
if (Test-Path $gitPluginData) {
  $cfg = Get-Content $gitPluginData -Raw | ConvertFrom-Json
  $cfg.autoSaveInterval = 10
  $cfg.autoPullInterval = 10
  $cfg.autoPullOnBoot = $true
  $cfg.autoBackupAfterFileChange = $true
  $cfg.disablePush = $false
  $cfg | ConvertTo-Json -Depth 10 | Set-Content $gitPluginData
  Say "Enabled Obsidian Git auto-sync (commit + pull + push) now that 'origin' is connected."
}

Write-Host ""
Write-Host "Backed up: $Owner/$Repo - Obsidian Git will keep it synced." -ForegroundColor Green
Write-Host "Base updates still work: update-base.sh manages its own ephemeral remote."
