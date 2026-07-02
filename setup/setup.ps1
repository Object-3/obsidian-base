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

function Say($m)  { Write-Host "==> $m" -ForegroundColor Cyan }
function Warn($m) { Write-Host "  ! $m" -ForegroundColor Yellow }
function Have($c) { return [bool](Get-Command $c -ErrorAction SilentlyContinue) }
function Winget($id) { if (Have winget) { winget install --id $id -e --accept-source-agreements --accept-package-agreements -h } else { Warn "winget not available; install $id manually." } }

# ---- 1. prerequisites -----------------------------------------------------
Say "Checking prerequisites (winget)..."
if (-not (Have git))  { Winget "Git.Git" }
if (-not (Have jq))   { Winget "jqlang.jq" }
if (-not (Have uv))   { Winget "astral-sh.uv" }
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
  # fork/custom base; the public default needs nothing.
  if ($BaseRepoUrl -ne "https://github.com/Object-3/obsidian-base.git") {
    Set-Content ".agents\.base-url" $BaseRepoUrl -NoNewline
  }
  git init -q; git add -A
  git -c user.name="Vault Owner" -c user.email="vault@localhost" commit -q -m "Initial vault from obsidian-base"
  git config core.hooksPath .githooks
}
Set-Location $VaultDir

# ---- 3. fill profile + sync skills (via Git Bash) ------------------------
if ($bash) {
  $env:VAULT_NAME = $VaultName; if (-not $env:PRIMARY_TAG) { $env:PRIMARY_TAG = "kb" }
  & $bash ".agents/scripts/init-vault.sh" "--yes"
} else {
  Warn "Git Bash not found; run .agents/scripts/init-vault.sh manually (it needs bash/jq)."
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
    # Resolve uvx to an absolute path for the Desktop config, mirroring setup.sh.
    # GUI-launched MCP servers may not inherit the user PATH, so a bare "uvx" can
    # fail to start. (Lower risk on Windows than macOS, but kept consistent.)
    $uvxBin = (Get-Command uvx -ErrorAction SilentlyContinue).Source; if (-not $uvxBin) { $uvxBin = "uvx" }
    $cfg = "$env:APPDATA\Claude\claude_desktop_config.json"
    New-Item -ItemType Directory -Force -Path (Split-Path $cfg) | Out-Null
    $json = if (Test-Path $cfg) { Get-Content $cfg -Raw | ConvertFrom-Json } else { [pscustomobject]@{} }
    if (-not $json.mcpServers) { $json | Add-Member mcpServers ([pscustomobject]@{}) -Force }
    $json.mcpServers | Add-Member "mcp-obsidian" ([pscustomobject]@{
      command=$uvxBin; args=@("mcp-obsidian");
      env=[pscustomobject]@{ OBSIDIAN_API_KEY=$ApiKey; OBSIDIAN_HOST=$ObsidianHost; OBSIDIAN_PORT=$ObsidianPort } }) -Force
    Say "Wiring MCP into Claude Desktop..."
    $json | ConvertTo-Json -Depth 10 | Set-Content $cfg
  }
  if ($McpClients -eq "code" -or $McpClients -eq "both") {
    if (Have claude) {
      $AssistantPresent = $true
      Say "Wiring MCP into Claude Code..."
      # --scope user → available across ALL the user's projects, not just this
      # directory (default scope is "local"). The vault is a consume-from-anywhere
      # knowledge base, so the MCP must be reachable from every Claude Code session.
      claude mcp add mcp-obsidian --scope user --env OBSIDIAN_API_KEY=$ApiKey --env OBSIDIAN_HOST=$ObsidianHost --env OBSIDIAN_PORT=$ObsidianPort -- uvx mcp-obsidian
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
