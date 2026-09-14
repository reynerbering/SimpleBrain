<#
.SYNOPSIS
    Installs the four-agent ship pipeline into ~/.claude on this machine.

.DESCRIPTION
    Copies the ship-* agents and the /ship slash command from this vault into
    the user-level Claude Code config, so /ship works in every repo without
    anything being checked into those repos.

    The vault is the source of truth. This script only ever copies vault -> ~/.claude.
    Safe to re-run; it reports what changed and leaves unchanged files alone.

    Run after every `git pull` that touches coding/ship/.

.PARAMETER Check
    Report what would change without writing anything.

.PARAMETER SkipGitIgnore
    Skip the global gitignore setup for .pipeline/.

.EXAMPLE
    .\install.ps1
    .\install.ps1 -Check
#>
#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$Check,
    [switch]$SkipGitIgnore
)

$ErrorActionPreference = 'Stop'

$SourceRoot = $PSScriptRoot
$ClaudeHome = Join-Path $env:USERPROFILE '.claude'

$added = 0; $updated = 0; $same = 0

function Get-FileHashOrNull($path) {
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    }
    return $null
}

function Install-One($sourcePath, $destPath) {
    $name = Split-Path -Leaf $destPath
    $srcHash = Get-FileHashOrNull $sourcePath
    $dstHash = Get-FileHashOrNull $destPath

    if ($null -eq $dstHash) {
        $state = 'ADD'
    } elseif ($srcHash -eq $dstHash) {
        $script:same++
        Write-Host ("  ok      {0}" -f $name) -ForegroundColor DarkGray
        return
    } else {
        $state = 'UPDATE'
    }

    if ($Check) {
        Write-Host ("  {0,-7} {1}  (dry run)" -f $state.ToLower(), $name) -ForegroundColor Yellow
    } else {
        $destDir = Split-Path -Parent $destPath
        if (-not (Test-Path -LiteralPath $destDir)) {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }
        Copy-Item -LiteralPath $sourcePath -Destination $destPath -Force
        Write-Host ("  {0,-7} {1}" -f $state.ToLower(), $name) -ForegroundColor Green
    }

    if ($state -eq 'ADD') { $script:added++ } else { $script:updated++ }
}

Write-Host ""
Write-Host "ship pipeline installer" -ForegroundColor Cyan
Write-Host ("  source: {0}" -f $SourceRoot)
Write-Host ("  target: {0}" -f $ClaudeHome)
Write-Host ""

# --- Sanity check the source ------------------------------------------------
$agentSource = Join-Path $SourceRoot 'agents'
$commandSource = Join-Path $SourceRoot 'commands'

if (-not (Test-Path -LiteralPath $agentSource)) {
    throw "Source folder not found: $agentSource. Run this script from its place in the vault, not a copy."
}

$expectedAgents = @('ship-planner.md', 'ship-coder.md', 'ship-tester.md', 'ship-reviewer.md')
$missing = @($expectedAgents | Where-Object { -not (Test-Path -LiteralPath (Join-Path $agentSource $_)) })
if ($missing.Count -gt 0) {
    throw ("Source is incomplete, missing: {0}. Pull the vault before installing." -f ($missing -join ', '))
}

# --- Install ----------------------------------------------------------------
Write-Host "agents ->  $ClaudeHome\agents" -ForegroundColor White
foreach ($a in $expectedAgents) {
    Install-One (Join-Path $agentSource $a) (Join-Path $ClaudeHome "agents\$a")
}

Write-Host ""
Write-Host "command -> $ClaudeHome\commands" -ForegroundColor White
Install-One (Join-Path $commandSource 'ship.md') (Join-Path $ClaudeHome 'commands\ship.md')

# --- Global gitignore for .pipeline/ ---------------------------------------
if (-not $SkipGitIgnore) {
    Write-Host ""
    Write-Host "global gitignore" -ForegroundColor White

    # `git config --get` exits 1 when the key is unset. That is not an error here,
    # so read it, then clear the exit code before it poisons the script's own status.
    $excludesFile = & git config --global core.excludesFile
    if ($LASTEXITCODE -ne 0) { $excludesFile = $null }
    $global:LASTEXITCODE = 0
    if ($excludesFile) { $excludesFile = $excludesFile.Trim() }

    if ([string]::IsNullOrWhiteSpace($excludesFile)) {
        $excludesFile = Join-Path $env:USERPROFILE '.gitignore_global'
        if ($Check) {
            Write-Host ("  would set core.excludesFile = {0}  (dry run)" -f $excludesFile) -ForegroundColor Yellow
        } else {
            git config --global core.excludesFile $excludesFile
            Write-Host ("  set     core.excludesFile = {0}" -f $excludesFile) -ForegroundColor Green
        }
    } else {
        # git may return a ~-prefixed or forward-slash path; normalise for file IO
        if ($excludesFile.StartsWith('~')) {
            $excludesFile = Join-Path $env:USERPROFILE $excludesFile.Substring(1).TrimStart('/', '\')
        }
        Write-Host ("  using   {0}" -f $excludesFile) -ForegroundColor DarkGray
    }

    $hasRule = $false
    if (Test-Path -LiteralPath $excludesFile) {
        $lines = @(Get-Content -LiteralPath $excludesFile)
        $hasRule = @($lines | Where-Object { $_.Trim() -eq '.pipeline/' }).Count -gt 0
    }

    if ($hasRule) {
        Write-Host "  ok      .pipeline/ already ignored" -ForegroundColor DarkGray
    } elseif ($Check) {
        Write-Host "  would add .pipeline/  (dry run)" -ForegroundColor Yellow
    } else {
        Add-Content -LiteralPath $excludesFile -Value '.pipeline/' -Encoding utf8
        Write-Host "  add     .pipeline/" -ForegroundColor Green
    }
}

# --- Summary ----------------------------------------------------------------
Write-Host ""
if ($Check) {
    Write-Host ("dry run: {0} to add, {1} to update, {2} already current" -f $added, $updated, $same) -ForegroundColor Cyan
    Write-Host "re-run without -Check to apply."
} else {
    Write-Host ("done: {0} added, {1} updated, {2} unchanged" -f $added, $updated, $same) -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Restart Claude Code, then try:  /ship <feature request>"
}
Write-Host ""

exit 0
