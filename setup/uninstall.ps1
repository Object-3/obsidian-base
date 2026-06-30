# ===========================================================================
# obsidian-base - reverse the agent integration (Windows / PowerShell)
# ===========================================================================
# Undoes what setup.ps1 wired up, WITHOUT EVER TOUCHING YOUR NOTES. By default
# it only DISCONNECTS the integration:
#   1. removes the mcp-obsidian server from Claude Desktop's config
#   2. removes the mcp-obsidian server from Claude Code (claude mcp remove)
#   3. removes the managed block from ~/.claude/CLAUDE.md (between sentinels)
#
# It does NOT delete your vault, and it does NOT uninstall prerequisites
# (git, jq, uv, Obsidian) - those are general-purpose tools. Your notes are
# never deleted by this script; it prints the vault location if you want to
# remove it yourself.
#
# It also NEVER removes skills you installed into your tools' user-scope
# (~/.claude\skills, ~/.agents\skills) - once installed those are yours. This
# script only informs you they remain.
#
# Optional flag:
#   -RemovePlugins   also remove the Local REST API + Git plugins and the REST
#                    API key from the vault's .obsidian\ (reversible - re-run
#                    setup.ps1). Needs the vault: run inside it or set VAULT_DIR.
#
# Idempotent. Override paths with env CLAUDE_MD, VAULT_DIR.
param([switch]$RemovePlugins)
$ErrorActionPreference = "Stop"

$ClaudeMd = $env:CLAUDE_MD; if (-not $ClaudeMd) { $ClaudeMd = "$HOME\.claude\CLAUDE.md" }
$VaultDir = $env:VAULT_DIR

function Say($m)  { Write-Host "==> $m" -ForegroundColor Cyan }
function Warn($m) { Write-Host "  ! $m" -ForegroundColor Yellow }
function Have($c) { return [bool](Get-Command $c -ErrorAction SilentlyContinue) }

# ---- 1. Claude Desktop config --------------------------------------------
$cfg = "$env:APPDATA\Claude\claude_desktop_config.json"
if (Test-Path $cfg) {
  $json = Get-Content $cfg -Raw | ConvertFrom-Json
  if ($json.mcpServers -and $json.mcpServers.PSObject.Properties.Name -contains "mcp-obsidian") {
    $json.mcpServers.PSObject.Properties.Remove("mcp-obsidian")
    $json | ConvertTo-Json -Depth 10 | Set-Content $cfg
    Say "Removed mcp-obsidian from Claude Desktop config."
  } else {
    Say "mcp-obsidian not present in Claude Desktop config - nothing to do."
  }
} else {
  Say "No Claude Desktop config at $cfg - skipping."
}

# ---- 2. Claude Code ------------------------------------------------------
if (Have claude) {
  $ok = $false
  try { claude mcp remove mcp-obsidian --scope user 2>$null; $ok = $true; Say "Removed mcp-obsidian from Claude Code (user scope)." } catch {}
  if (-not $ok) {
    try { claude mcp remove mcp-obsidian 2>$null; Say "Removed mcp-obsidian from Claude Code." }
    catch { Say "mcp-obsidian not registered in Claude Code - nothing to do." }
  }
} else {
  Say "Claude Code CLI not found - skipping."
}

# ---- 3. global ~/.claude/CLAUDE.md ----------------------------------------
if (Test-Path $ClaudeMd) {
  $lines = Get-Content $ClaudeMd
  if ($lines -match "BEGIN obsidian-base vault rules") {
    $out = New-Object System.Collections.Generic.List[string]
    $skip = $false
    foreach ($l in $lines) {
      if ($l -match "BEGIN obsidian-base vault rules") { $skip = $true; continue }
      if ($l -match "END obsidian-base vault rules")   { $skip = $false; continue }
      if (-not $skip) { $out.Add($l) }
    }
    Set-Content $ClaudeMd $out
    Say "Removed the managed vault-rules block from $ClaudeMd."
    if (-not (($out -join "").Trim())) { Warn "$ClaudeMd is now empty - delete it if you like." }
  } else {
    Warn "No managed sentinels found in $ClaudeMd."
    Warn "If you added the vault rules by hand, remove the '## Obsidian knowledge base' section yourself."
  }
} else {
  Say "No $ClaudeMd - skipping."
}

# ---- 4. optional: Obsidian plugins in the vault --------------------------
if ($RemovePlugins) {
  $v = $VaultDir
  if (-not $v) { try { $v = (git rev-parse --show-toplevel 2>$null) } catch {} }
  if ($v -and (Test-Path "$v\.obsidian")) {
    Say "Removing Local REST API + Git plugins from $v\.obsidian ..."
    Remove-Item -Recurse -Force "$v\.obsidian\plugins\obsidian-local-rest-api" -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force "$v\.obsidian\plugins\obsidian-git" -ErrorAction SilentlyContinue
    Remove-Item -Force "$v\.obsidian\.rest-api-key" -ErrorAction SilentlyContinue
    if (Test-Path "$v\.obsidian\community-plugins.json") { '[]' | Set-Content "$v\.obsidian\community-plugins.json" }
    Say "Plugins removed (re-run setup.ps1 to restore them)."
  } else {
    Warn "Couldn't locate a vault (run inside it or set VAULT_DIR). Skipping plugin removal."
  }
}

# ---- 5. user-scope skills: INFORM, never remove --------------------------
# The portable skills you installed into your tools' user-scope are YOURS - left
# in place. We only tell you they remain (removal is your manual choice).
$man = $env:MIRROR_MANIFEST
if (-not $man) {
  $xdg = $env:XDG_CONFIG_HOME; if (-not $xdg) { $xdg = Join-Path $HOME ".config" }
  $man = Join-Path $xdg "obsidian-base\skill-mirror.json"   # match sync-skills.sh / uninstall.sh
}
if (Test-Path $man) {
  try {
    # @(...) forces array semantics so a single-element owned list doesn't unwrap to a
    # scalar (whose .Count is 1 only by luck); an empty/missing list counts as 0.
    $n = @((Get-Content $man -Raw | ConvertFrom-Json).owned).Count
    if ($n -gt 0) {
      Say "$n skill(s) you installed into user-scope are KEPT - offboarding never removes them."
      Write-Host "    They stay in ~/.claude\skills and ~/.agents\skills, yours to use anywhere."
      Write-Host "    To remove them yourself: delete those skill dirs and $man"
    }
  } catch {}
}

$vloc = $VaultDir
if (-not $vloc) { try { $vloc = (git rev-parse --show-toplevel 2>$null) } catch {} }
Write-Host ""
Write-Host "OK Disconnected. Restart Claude Desktop / start a fresh Claude Code session to drop the server." -ForegroundColor Green
if ($vloc -and (Test-Path "$vloc\.obsidian")) {
  Write-Host "Your vault (your notes) is untouched at: $vloc"
} else {
  Write-Host "Your vault was not deleted. If you want it gone, delete the vault folder yourself."
}
