<#
CBS-4436 gate experiment - RegisterJobs flip count.

Splits the affected postings into:
  cause 1  = row was never created        -> clickToApplyUrl flips null -> non-null
  cause 2/3= site opted out, or nothing maskable -> stays null

Phase A (default)  : READ ONLY. Resolves spider postings, captures BEFORE state.
Phase B (-Execute) : PROD WRITE. POSTs RegisterJobs, captures AFTER, reports the split.

NOTE 2026-09-18: core-api did not require X-API-KEY on these GETs in prod - the header is
sent but not enforced. $env:CORE_API_KEY is still honoured if set; set it to anything if
you just want the script to run.

FIXED 2026-09-18: the spider resolution used count=200&page=1 and always returned HTTP 400.
The endpoint rejects count > 100 (PostingController.cs:173) and page is 0-based.

  $env:CORE_API_KEY = '<your prod key>'
  ./cbs4436-experiment.ps1                # safe, read-only
  ./cbs4436-experiment.ps1 -Execute       # performs the prod write
#>
[CmdletBinding()]
param(
    [switch]$Execute,
    [string]$BaseUrl = 'https://core-api.jobtarget.com',
    [string]$OutDir  = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'

if (-not $env:CORE_API_KEY) { throw "Set `$env:CORE_API_KEY first. It is not stored by this script." }
$headers = @{ 'X-API-KEY' = $env:CORE_API_KEY; 'Accept' = 'application/json' }

# From CBS-4436. The 13 'posted' postings are listed explicitly in the ticket.
$postedIds = @(285573508,285581645,285584140,285590567,285610360,285610883,
               285645440,285645542,285671961,285672020,285673325,285699513,285699605)
# The 22 'spider' postings are NOT listed - only their job ids. Resolved below.
$spiderJobIds = @(41067728,41063570,41063651)

function Get-Posting([int]$id) {
    try   { Invoke-RestMethod -Method Get -Uri "$BaseUrl/api/v2/posting/$id" -Headers $headers -TimeoutSec 30 }
    catch { [pscustomobject]@{ id = $id; clickToApplyUrl = $null; __error = $_.Exception.Message } }
}

Write-Host "`n=== Resolving spider postings ===" -ForegroundColor Cyan
$spiderIds = @()
foreach ($jobId in $spiderJobIds) {
    try {
        $rows = Invoke-RestMethod -Method Get -Uri "$BaseUrl/api/v2/job/$jobId/posting?count=100&page=0" -Headers $headers -TimeoutSec 30
        $ids  = @($rows | ForEach-Object { $_.id })
        $spiderIds += $ids
        Write-Host ("  job {0,-10} -> {1,3} postings" -f $jobId, $ids.Count)
    } catch {
        Write-Warning "  job $jobId -> FAILED: $($_.Exception.Message)"
    }
}

$allIds = @($postedIds + $spiderIds | Select-Object -Unique)
Write-Host ("`nTotal postings under test: {0} ({1} posted + {2} spider)" -f $allIds.Count, $postedIds.Count, $spiderIds.Count) -ForegroundColor Cyan
Write-Host "Ticket expects 13 posted + 22 spider = 35. Investigate any mismatch before trusting the result."

Write-Host "`n=== BEFORE ===" -ForegroundColor Cyan
$before = @{}
foreach ($id in $allIds) {
    $p = Get-Posting $id
    $before[$id] = $p.clickToApplyUrl
    if ($p.__error) { Write-Warning ("  {0}  ERROR {1}" -f $id, $p.__error) }
}
$nullBefore = @($allIds | Where-Object { -not $before[$_] })
Write-Host ("  null clickToApplyUrl before: {0} / {1}" -f $nullBefore.Count, $allIds.Count)

$stamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
$before | ConvertTo-Json -Depth 3 | Set-Content (Join-Path $OutDir "cbs4436-before-$stamp.json")

if (-not $Execute) {
    Write-Host "`nPhase A complete (read-only). Nothing was written." -ForegroundColor Yellow
    Write-Host "Re-run with -Execute to perform the prod write." -ForegroundColor Yellow
    return
}

if ($nullBefore.Count -eq 0) {
    Write-Host "`nNothing is null. The experiment has no signal to produce - stopping." -ForegroundColor Yellow
    return
}

Write-Host "`n=== PROD WRITE: POST /internal/analytics/RegisterJobs ===" -ForegroundColor Red
Write-Host ("  Registering {0} postings that are currently null." -f $nullBefore.Count)
$body = @{ postings = @($nullBefore); encodeUrl = $false } | ConvertTo-Json -Compress
$resp = Invoke-RestMethod -Method Post -Uri "$BaseUrl/internal/analytics/RegisterJobs" `
            -Headers $headers -ContentType 'application/json' -Body $body -TimeoutSec 300
Write-Host ("  response: " + ($resp | ConvertTo-Json -Compress))

Start-Sleep -Seconds 5

Write-Host "`n=== AFTER ===" -ForegroundColor Cyan
$rows = foreach ($id in $nullBefore) {
    $after = (Get-Posting $id).clickToApplyUrl
    [pscustomobject]@{
        postingId = $id
        channel   = if ($postedIds -contains $id) { 'posted' } else { 'spider' }
        flipped   = [bool]$after
        cause     = if ($after) { '1 - row was missing' } else { '2 or 3 - opted out / nothing maskable' }
        afterUrl  = $after
    }
}
$rows | Sort-Object channel, postingId | Format-Table -AutoSize

$flipped = @($rows | Where-Object flipped).Count
$stuck   = $rows.Count - $flipped
Write-Host ("`nRESULT: {0} flipped (cause 1), {1} stayed null (cause 2 or 3), of {2} tested." -f $flipped, $stuck, $rows.Count) -ForegroundColor Green
Write-Host "`nReading the gate:" -ForegroundColor Cyan
Write-Host "  mostly flipped -> ticket's root cause holds; Q2 direction (wrap at create) is correct."
Write-Host "  mostly stuck   -> root cause is WRONG. Reopen Q2 before any Phase 2 work."
Write-Host "  by channel     -> a split along posted/spider means the cause differs per channel."

$rows | Export-Csv -NoTypeInformation (Join-Path $OutDir "cbs4436-result-$stamp.csv")
Write-Host ("`nSaved: cbs4436-result-{0}.csv" -f $stamp)
