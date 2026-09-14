<#
.SYNOPSIS
    Installs the vault's skills into ~/.claude/skills on this machine.

.DESCRIPTION
    Copies every skill directory from this vault into the user-level Claude
    Code skills folder, so they are available in EVERY repo rather than only
    inside the vault.

    The vault is the source of truth. This script only ever copies
    vault -> ~/.claude/skills. It never copies back and never deletes a skill
    that exists only in ~/.claude/skills.

    Run after every `git pull` that touches skills/.

.PARAMETER Check
    Report what would change without writing anything.

.EXAMPLE
    .\install.ps1
    .\install.ps1 -Check
#>
#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$Check
)

$ErrorActionPreference = 'Stop'

$SourceRoot = $PSScriptRoot
$SkillsHome = Join-Path $env:USERPROFILE '.claude\skills'

Write-Host "skills installer" -ForegroundColor Cyan
Write-Host "  source: $SourceRoot"
Write-Host "  target: $SkillsHome"
Write-Host ""

if (-not (Test-Path -LiteralPath $SourceRoot)) {
    Write-Host "source folder not found: $SourceRoot" -ForegroundColor Red
    exit 1
}

# Hash a whole directory by combining relative path + content hashes, so a
# change to ANY file in a skill marks that skill as needing an update.
function Get-DirHash($path) {
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    $sb = New-Object System.Text.StringBuilder
    Get-ChildItem -LiteralPath $path -Recurse -File | Sort-Object FullName | ForEach-Object {
        $rel = $_.FullName.Substring($path.Length).TrimStart('\', '/')
        $h = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
        [void]$sb.AppendLine("$rel|$h")
    }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($sb.ToString())
    $sha = [System.Security.Cryptography.SHA256]::Create()
    return [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '')
}

$added = 0; $updated = 0; $same = 0

# Only directories holding a SKILL.md are skills. This skips this script and
# any stray files sitting in skills/.
$skills = Get-ChildItem -LiteralPath $SourceRoot -Directory |
    Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md') }

if (-not $skills) {
    Write-Host "no skills found (a skill is a directory containing SKILL.md)" -ForegroundColor Yellow
    exit 1
}

if (-not $Check) { New-Item -ItemType Directory -Force -Path $SkillsHome | Out-Null }

foreach ($s in $skills) {
    $dst = Join-Path $SkillsHome $s.Name
    $srcHash = Get-DirHash $s.FullName
    $dstHash = Get-DirHash $dst

    if ($null -eq $dstHash) {
        Write-Host "  add     $($s.Name)$(if ($Check) { '  (dry run)' })" -ForegroundColor Green
        if (-not $Check) {
            Copy-Item -LiteralPath $s.FullName -Destination $dst -Recurse -Force
        }
        $added++
    }
    elseif ($srcHash -ne $dstHash) {
        Write-Host "  update  $($s.Name)$(if ($Check) { '  (dry run)' })" -ForegroundColor Yellow
        if (-not $Check) {
            # Replace wholesale so files deleted upstream actually go away.
            Remove-Item -LiteralPath $dst -Recurse -Force
            Copy-Item -LiteralPath $s.FullName -Destination $dst -Recurse -Force
        }
        $updated++
    }
    else {
        $same++
    }
}

Write-Host ""
if ($Check) {
    Write-Host "dry run: $added to add, $updated to update, $same already current"
    Write-Host "re-run without -Check to apply."
}
else {
    Write-Host "done: $added added, $updated updated, $same unchanged" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Run /reload-skills in Claude Code (or restart) to pick them up."
}
