# ===========================================================================
# Connect an existing LOCAL vault to GitHub for backup/sync (Windows)
# ===========================================================================
# Optional, run anytime AFTER setup.ps1 from inside your vault folder. Creates a
# PRIVATE repo under your account OR an org you belong to, pushes, and sets it as
# 'origin'. Your 'base' remote (for update-base) is left untouched. Idempotent.
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
$defaultName = Split-Path $root -Leaf
$Repo = Read-Host "Repository name [$defaultName]"; if (-not $Repo) { $Repo = $defaultName }
$Vis = Read-Host "Visibility (private/public) [private]"; if (-not $Vis) { $Vis = "private" }

$origin = (git remote get-url origin) 2>$null
if ($origin) {
  Say "An 'origin' already exists ($origin); pushing to it."
  git push -u origin (git branch --show-current)
} else {
  Say "Creating $Owner/$Repo ($Vis) and pushing..."
  gh repo create "$Owner/$Repo" --$Vis --source=. --remote=origin --push
}
Write-Host ""
Write-Host "Backed up: $Owner/$Repo - Obsidian Git will keep it synced." -ForegroundColor Green
Write-Host "Your 'base' remote (for update-base) is unchanged."
