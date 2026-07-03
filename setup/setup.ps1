# ===========================================================================
# obsidian-base - clean-slate, LOCAL-FIRST onboarding (Windows / PowerShell)
# ===========================================================================
# Run on a brand-new machine. No GitHub account or prior tools required. It
# installs prerequisites (via winget), creates a LOCAL vault from the base
# template, wires the Obsidian MCP into Claude Desktop and/or Claude Code, and
# opens it. GitHub backup is OPTIONAL and added later with connect-github.ps1.
#
# One-command install (PowerShell):
#   irm https://raw.githubusercontent.com/Object-3/obsidian-base/main/setup/setup.ps1 | iex
#
# Idempotent. Override defaults with env vars (BASE_REPO_URL, VAULT_PARENT,
# VAULT_NAME, MCP_CLIENTS=desktop|code|both|none, MIRROR_SKILLS=ask|yes|no).
$ErrorActionPreference = "Stop"

$BaseRepoUrl = $env:BASE_REPO_URL; if (-not $BaseRepoUrl) { $BaseRepoUrl = "https://github.com/Object-3/obsidian-base.git" }
$VaultParent = $env:VAULT_PARENT; if (-not $VaultParent) { $VaultParent = "$HOME\Documents" }
$VaultName   = $env:VAULT_NAME
$McpClients  = $env:MCP_CLIENTS;  if (-not $McpClients)  { $McpClients = "both" }
$MirrorSkills = $env:MIRROR_SKILLS; if (-not $MirrorSkills) { $MirrorSkills = "ask" }
$ObsidianHost = "127.0.0.1"; $ObsidianPort = "27124"
# Clients reach the Local REST API plugin's own /mcp/ endpoint over the vault's loopback
# HTTP (insecure) port = HTTPS port - 1. Port lives in the URL, so no OBSIDIAN_PORT (the
# old uvx mcp-obsidian server ignored it and hardcoded 27124 — broken for a 2nd vault).
$InsecurePort = [string]([int]$ObsidianPort - 1)
$McpUrl = "http://127.0.0.1:$InsecurePort/mcp/"

function Say($m)  { Write-Host "==> $m" -ForegroundColor Cyan }
function Warn($m) { Write-Host "  ! $m" -ForegroundColor Yellow }
function Have($c) { return [bool](Get-Command $c -ErrorAction SilentlyContinue) }
function Winget($id) { if (Have winget) { winget install --id $id -e --accept-source-agreements --accept-package-agreements -h } else { Warn "winget not available; install $id manually." } }

# ---- 1. prerequisites -----------------------------------------------------
Say "Checking prerequisites (winget)..."
if (-not (Have git))  { Winget "Git.Git" }
if (-not (Have jq))   { Winget "jqlang.jq" }
# node provides npx, which runs the mcp-remote bridge for Claude Desktop.
if (-not (Have node)) { Winget "OpenJS.NodeJS.LTS" }
if (-not (Test-Path "$env:LOCALAPPDATA\Obsidian\Obsidian.exe") -and -not (Have obsidian)) { Winget "Obsidian.Obsidian" }
# refresh PATH for this session
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
if (-not (Have git)) { throw "git is required and could not be installed." }
$bash = (Get-Command bash -ErrorAction SilentlyContinue).Source   # Git for Windows ships bash; used to run the .sh helpers

# ---- 2. create the local vault -------------------------------------------
if (-not $VaultName) { $VaultName = Read-Host "Name your knowledge vault" }
if (-not $VaultName) { $VaultName = "My Knowledge Base" }
$slug = ($VaultName.ToLower() -replace '[^a-z0-9]+','-').Trim('-')
$VaultDir = Join-Path $VaultParent $slug
# Per-vault MCP label `obsidian-<slug>` (matches setup/lib.sh's lib_mcp_label — strips a
# redundant leading "obsidian" so "Obsidian Puma" -> obsidian-puma, not obsidian-obsidian-puma).
$labelSlug = ($slug -replace '^obsidian','') -replace '^-',''
if (-not $labelSlug) { $labelSlug = "vault" }
$McpLabel = "obsidian-$labelSlug"
$FreshVault = $false
if (Test-Path (Join-Path $VaultDir ".git")) {
  Say "Vault already exists at $VaultDir - reusing it."
} else {
  New-Item -ItemType Directory -Force -Path $VaultParent | Out-Null
  Say "Creating your vault at $VaultDir (from the base template)..."
  git clone --depth 1 $BaseRepoUrl $VaultDir
  Set-Location $VaultDir
  Remove-Item -Recurse -Force .git
  # No standing `base` git remote: update-base.sh adds one ephemerally per fetch and removes
  # it, so `base` can't be mis-picked in Obsidian Git's remote picker and push private notes
  # into the (public) template. Persist a NON-DEFAULT base URL so update-base still finds a
  # fork/custom base; the public default needs nothing. Clear any .base-url the clone source
  # carried first, so the base is exactly what setup resolved — not a stowaway from the clone.
  Remove-Item -Force -ErrorAction SilentlyContinue ".agents\.base-url"
  if ($BaseRepoUrl -ne "https://github.com/Object-3/obsidian-base.git") {
    Set-Content ".agents\.base-url" $BaseRepoUrl -NoNewline
  }
  # Explicit -b main so the default branch never inherits the machine's init.defaultBranch
  # (may be `master`); fall back for git < 2.28. The initial commit is DEFERRED to after
  # personalization (section 3a) so the first commit holds real values, not {{PLACEHOLDER}}s.
  git init -q -b main 2>$null
  if ($LASTEXITCODE -ne 0) { git init -q; git symbolic-ref HEAD refs/heads/main }
  git config core.hooksPath .githooks
  $FreshVault = $true
}
Set-Location $VaultDir

# ---- 3. fill profile + sync skills (via Git Bash) ------------------------
if ($bash) {
  $env:VAULT_NAME = $VaultName; if (-not $env:PRIMARY_TAG) { $env:PRIMARY_TAG = "kb" }
  & $bash ".agents/scripts/init-vault.sh" "--yes"
} else {
  Warn "Git Bash not found; run .agents/scripts/init-vault.sh manually (it needs bash/jq)."
}

# ---- 3a. make the initial commit, AFTER personalizing --------------------
# Deferred from vault creation so the first commit holds real values. Guard: if
# {{PLACEHOLDER}} tokens remain (init-vault failed, or Git Bash was missing so it never
# ran), warn loudly instead of silently committing template tokens as a false success.
if ($FreshVault) {
  Set-Location $VaultDir
  if (Select-String -Path .agents\vault-profile.md,index.md,log.md,llms.txt,README.md -Pattern '{{' -Quiet -ErrorAction SilentlyContinue) {
    Warn "Vault still has {{PLACEHOLDER}} tokens - personalization didn't complete; run .agents/scripts/init-vault.sh, then commit again."
  }
  git add -A
  git -c user.name="Vault Owner" -c user.email="vault@localhost" commit -q -m "Initial vault from obsidian-base"
}

# ---- 3b. (optional) mirror skills into user-scope ------------------------
# Opt-in: also install the vendored portable skills into the user's CLI tools so
# they work in EVERY project, not just this vault. Uses --mirror-only (no network
# re-fetch). Never enabled silently.
$SkillsMirrored = $false
if ($bash) {
  $choice = $MirrorSkills
  if ($choice -eq "ask") {
    $ans = Read-Host "Make these skills available in ALL your projects, not just this vault? [y/N]"
    if ($ans -match '^[Yy]') { $choice = "yes" } else { $choice = "no" }
  }
  if ($choice -eq "yes") {
    Say "Installing skills into your user-scope (~/.claude/skills, ~/.agents/skills)..."
    try { & $bash ".agents/scripts/sync-skills.sh" "--mirror-only"; $SkillsMirrored = $true }
    catch { Warn "skill mirror failed - run the /install-skills skill later." }
  }
}

# ---- 4. provision Obsidian plugins + REST API key ------------------------
function Get-Release($repo, $dest) {
  New-Item -ItemType Directory -Force -Path $dest | Out-Null
  $tag = (Invoke-RestMethod "https://api.github.com/repos/$repo/releases/latest").tag_name
  $base = "https://github.com/$repo/releases/download/$tag"
  foreach ($f in @("manifest.json","main.js")) { Invoke-WebRequest "$base/$f" -OutFile (Join-Path $dest $f) }
  try { Invoke-WebRequest "$base/styles.css" -OutFile (Join-Path $dest "styles.css") } catch {}
}
Say "Installing Obsidian plugins (Git + Local REST API)..."
try { Get-Release "Vinzent03/obsidian-git" ".obsidian\plugins\obsidian-git" } catch { Warn "obsidian-git download failed" }
try { Get-Release "coddingtonbear/obsidian-local-rest-api" ".obsidian\plugins\obsidian-local-rest-api" } catch { Warn "local-rest-api download failed" }
$ApiKey = -join ((1..64) | ForEach-Object { '{0:x}' -f (Get-Random -Max 16) })
Set-Content ".obsidian\.rest-api-key" $ApiKey -NoNewline
$lr = ".obsidian\plugins\obsidian-local-rest-api\data.json"
if (Test-Path ".obsidian\plugins\obsidian-local-rest-api\main.js") {
  @{ apiKey=$ApiKey; crypto=$null; port=27124; insecurePort=27123; enableInsecureServer=$true; bindingHost="127.0.0.1" } | ConvertTo-Json | Set-Content $lr
}
'["obsidian-local-rest-api","obsidian-git"]' | Set-Content ".obsidian\community-plugins.json"

# ---- 5. wire the Obsidian MCP --------------------------------------------
$ClaudeDesktopMissing = $false   # set when the Claude Desktop app isn't installed
$ClaudeCodeMissing    = $false   # set when the Claude Code CLI isn't installed
$AssistantPresent     = $false   # set when at least one assistant is installed
if ($McpClients -ne "none") {
  if ($McpClients -eq "desktop" -or $McpClients -eq "both") {
    # The Claude Desktop app itself isn't installed by this script — wire the config
    # anyway (it activates the moment they install it), but flag it for the final note.
    if ((Test-Path "$env:LOCALAPPDATA\AnthropicClaude\claude.exe") -or (Test-Path "$env:LOCALAPPDATA\Programs\claude\claude.exe")) {
      $AssistantPresent = $true
    } else {
      $ClaudeDesktopMissing = $true
    }
    # Claude Desktop config carries only stdio servers, so it reaches the plugin's HTTP
    # /mcp/ endpoint through the mcp-remote bridge (key inline). Resolve npx to an absolute
    # path — GUI-launched servers may not inherit the user PATH, so a bare "npx" can fail.
    $npxBin = (Get-Command npx -ErrorAction SilentlyContinue).Source; if (-not $npxBin) { $npxBin = "npx" }
    $cfg = "$env:APPDATA\Claude\claude_desktop_config.json"
    New-Item -ItemType Directory -Force -Path (Split-Path $cfg) | Out-Null
    $json = if (Test-Path $cfg) { Get-Content $cfg -Raw | ConvertFrom-Json } else { [pscustomobject]@{} }
    if (-not $json.mcpServers) { $json | Add-Member mcpServers ([pscustomobject]@{}) -Force }
    # Eradicate any legacy uvx `mcp-obsidian` entry from a prior setup.
    if ($json.mcpServers.PSObject.Properties.Name -contains "mcp-obsidian") { $json.mcpServers.PSObject.Properties.Remove("mcp-obsidian") }
    $json.mcpServers | Add-Member $McpLabel ([pscustomobject]@{
      command=$npxBin; args=@("-y","mcp-remote",$McpUrl,"--header","Authorization: Bearer $ApiKey","--allow-http") }) -Force
    Say "Wiring MCP into Claude Desktop ($McpLabel -> $McpUrl)..."
    $json | ConvertTo-Json -Depth 10 | Set-Content $cfg
  }
  if ($McpClients -eq "code" -or $McpClients -eq "both") {
    if (Have claude) {
      $AssistantPresent = $true
      Say "Wiring MCP into Claude Code ($McpLabel -> $McpUrl)..."
      # Claude Code speaks Streamable HTTP natively (key inline) — no bridge needed.
      # --scope user → available across ALL the user's projects, not just this directory
      # (default scope is "local"). The vault is a consume-from-anywhere knowledge base,
      # so the MCP must be reachable from every Claude Code session. Eradicate any legacy
      # uvx entry first, and clear this label so a re-run refreshes it cleanly.
      claude mcp remove mcp-obsidian --scope user 2>$null
      claude mcp remove $McpLabel --scope user 2>$null
      claude mcp add $McpLabel --scope user --transport http $McpUrl --header "Authorization: Bearer $ApiKey"
    } else {
      $ClaudeCodeMissing = $true
      Warn "Claude Code CLI not found; skipping (install it, then re-run with MCP_CLIENTS=code)."
    }
  }
}

# ---- 6. open --------------------------------------------------------------
Say "Opening your vault in Obsidian..."
try { Start-Process "obsidian://open?path=$([uri]::EscapeDataString($VaultDir))" } catch {}

Write-Host ""
Write-Host "Done. Your vault: $VaultDir" -ForegroundColor Green
Write-Host ""

if ($SkillsMirrored) {
  Write-Host "Skills installed to your user-scope - they now work in every project, not just this vault." -ForegroundColor Green
  Write-Host "Manage them with the /install-skills skill; they stay even if you later offboard."
  Write-Host ""
}

# If NO AI assistant is installed, the MCP we just wired has nothing to load into.
# (If at least one is present we stay quiet — the config is live for it.)
if (-not $AssistantPresent) {
  Write-Host "No AI assistant is installed yet." -ForegroundColor Yellow
  Write-Host "The vault is ready and the connection is pre-wired, but it only activates once the assistant is on this machine:"
  if ($ClaudeDesktopMissing) { Write-Host "  - Claude Desktop:  https://claude.ai/download" }
  if ($ClaudeCodeMissing)    { Write-Host "  - Claude Code:     https://claude.com/claude-code" }
  Write-Host "Install it, then come back to the steps below."
  Write-Host ""
}

Write-Host "Next (one-time, in Obsidian):"
Write-Host "  - Click 'Trust author and enable plugins' if prompted. This switches the Local REST"
Write-Host "    API on - the bridge your assistant talks to. Until you do this, the assistant"
Write-Host "    cannot read or write the vault."
Write-Host ""
Write-Host "Then connect your assistant to the vault:"
Write-Host "  - The connection (MCP) was configured during setup, but Claude only loads it when a"
Write-Host "    session STARTS. So begin a NEW session before it works:"
Write-Host "      * Claude Desktop: fully quit and reopen the app."
Write-Host "      * Claude Code:    start a new session (the running one won't see it)."
Write-Host "  - To confirm, ask your assistant: 'list the files in my vault.'"
Write-Host ""
Write-Host "Optional cloud backup later:  cd `"$VaultDir`"; .\setup\connect-github.ps1"
Write-Host "Pull base updates anytime:    cd `"$VaultDir`"; bash .agents/scripts/update-base.sh"
