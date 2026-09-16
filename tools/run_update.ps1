<#
.SYNOPSIS
  Produce one quarterly release: estimate, check, promote, commit, tag, push.

.DESCRIPTION
  The release entry point. It runs run_release.m under `matlab -batch`, and
  commits only what that run promoted into estimates/.

  Everything that decides whether a release is fit to publish lives in MATLAB,
  in estimates/guardrails.m. This script decides nothing. It runs the release,
  reads its exit status, and stops on a non-zero one - because `matlab -batch`
  exits 0 on a NaN posterior, and the only thing that separates a refused
  release from a published one is run_release erroring and this script noticing.

  Nothing is committed when the guardrails fail. The staging tree under build/
  is git-ignored, so a refused release leaves the tracked tree exactly as it
  was, and the numbers are still there to look at.

.PARAMETER IfNewData
  How the Monday schedule calls this. Release only if FRED has a quarter, complete
  in both DPCERD3Q086SBEA and GDPC1, that is newer than the published vintage,
  and take the vintage from that quarter. Otherwise exit quietly. A release this
  mode starts and the guardrails refuse leaves build\release_failed_<vintage>.txt,
  and that vintage is not retried until the file is deleted.

.PARAMETER Vintage
  'YYYYQq'. Default: whatever run_release picks, which is the quarter that ended
  before today. Ignored with -IfNewData, which takes it from the data.

.PARAMETER Models
  Comma-separated model names. Default: all five.

.PARAMETER DryRun
  Estimate, check and stage, but promote nothing and commit nothing.

.PARAMETER NoPush
  Commit and tag locally, push nothing. For a release you want to look at first.

.PARAMETER AllowUnmeasured
  Run models whose runtime has not been measured. run_release refuses them by
  default, so an unattended job cannot quietly overrun.

.EXAMPLE
  .\tools\run_update.ps1 -IfNewData
  .\tools\run_update.ps1 -DryRun
  .\tools\run_update.ps1 -Vintage 2026Q3 -NoPush
#>

[CmdletBinding()]
param(
    [switch] $IfNewData,
    [string] $Vintage = '',
    [string] $Models = '',
    [switch] $DryRun,
    [switch] $NoPush,
    [switch] $AllowUnmeasured,
    [string] $MatlabExe = ''
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
Write-Host "checked:    $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

# ---- start from the published history -------------------------------------
# The freshness watchdog and the traffic snapshot commit to main every week, so
# a release machine that has not pulled is behind, and its push would be
# refused. Fast-forward only: a local branch that has diverged needs a person.
git pull --ff-only --quiet
if ($LASTEXITCODE -ne 0) { throw "git pull --ff-only failed: the local branch has diverged from origin." }

# ---- the Monday trigger -----------------------------------------------------
function Get-NewestQuarter([string] $sid) {
    $url  = "https://fred.stlouisfed.org/graph/fredgraph.csv?id=$sid"
    $ua   = 'trend-cycle-toolkit (https://github.com/joshuaccchan/trend-cycle-toolkit)'
    $body = (Invoke-WebRequest -Uri $url -UseBasicParsing -UserAgent $ua -TimeoutSec 90).Content
    if ($body -is [byte[]]) { $body = [Text.Encoding]::UTF8.GetString($body) }
    $lines = @($body -split "`r?`n" | Where-Object { $_ })
    # Status is not evidence: an error page served with 200 is not a CSV.
    if ($lines.Count -lt 2 -or -not $lines[0].StartsWith('observation_date')) {
        throw "$sid : the response is not a FRED CSV"
    }
    $last = $null
    foreach ($line in ($lines | Select-Object -Skip 1)) {
        $f = $line -split ','
        # FRED returns the running quarter as a present row with an empty value.
        if ($f.Count -ge 2 -and $f[1].Trim() -notin @('', '.')) { $last = $f[0].Trim() }
    }
    if (-not $last) { throw "$sid : no complete observations" }
    $d = [datetime]::ParseExact($last, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
    [pscustomobject]@{ Year = $d.Year; Q = [int][math]::Ceiling($d.Month / 3) }
}
function Get-QuarterIndex($q) { 4 * $q.Year + $q.Q }
function Format-Quarter($q)   { '{0}Q{1}' -f $q.Year, $q.Q }

if ($IfNewData) {
    $metaPath = Join-Path $root 'estimates\current\metadata.json'
    $published = (Get-Content $metaPath -Raw | ConvertFrom-Json).vintage
    if ($published -notmatch '^(\d{4})Q([1-4])$') { throw "estimates\current\metadata.json has no readable vintage." }
    $pub = [pscustomobject]@{ Year = [int]$Matches[1]; Q = [int]$Matches[2] }

    # Both series come from BEA's GDP release. The release covers the newest
    # quarter complete in both, and is taken from the data rather than the
    # calendar, so a BEA release that slips past a quarter end cannot be
    # labelled with a quarter the data do not reach.
    $newest = @('DPCERD3Q086SBEA', 'GDPC1') | ForEach-Object { Get-NewestQuarter $_ } |
              Sort-Object { Get-QuarterIndex $_ } | Select-Object -First 1

    if ((Get-QuarterIndex $newest) -le (Get-QuarterIndex $pub)) {
        Write-Host "no new quarter: data through $(Format-Quarter $newest), estimates through $published."
        exit 0
    }

    $Vintage = Format-Quarter $newest
    $marker = Join-Path $root "build\release_failed_$Vintage.txt"
    if (Test-Path $marker) {
        Write-Host "data through $Vintage, but a release of $Vintage was already refused." -ForegroundColor Yellow
        Write-Host "Not retrying. See $marker, fix the cause, then delete it."
        exit 0
    }
    Write-Host "new quarter: data through $Vintage, estimates through $published. Releasing $Vintage."
}

# ---- locate MATLAB --------------------------------------------------------
if (-not $MatlabExe) {
    $cmd = Get-Command matlab -ErrorAction SilentlyContinue
    if ($cmd) {
        $MatlabExe = $cmd.Source
    } else {
        $found = Get-ChildItem 'C:\Program Files\MATLAB' -Directory -ErrorAction SilentlyContinue |
                 Sort-Object Name -Descending |
                 ForEach-Object { Join-Path $_.FullName 'bin\matlab.exe' } |
                 Where-Object { Test-Path $_ } |
                 Select-Object -First 1
        if (-not $found) {
            throw "MATLAB was not found on the PATH or under C:\Program Files\MATLAB. Pass -MatlabExe."
        }
        $MatlabExe = $found
    }
}
Write-Host "matlab:     $MatlabExe"

# ---- refuse to run on a dirty tree ---------------------------------------
# A release commit should contain the release and nothing else. Uncommitted
# work in the tree would be swept into it by the `git add estimates` below.
$dirty = git status --porcelain -- estimates
if ($dirty) {
    Write-Host "`nestimates/ has uncommitted changes:" -ForegroundColor Yellow
    $dirty | ForEach-Object { Write-Host "  $_" }
    throw "Commit or stash them first: a release commit should hold the release and nothing else."
}

# ---- build the run_release call ------------------------------------------
# Not $args: that is an automatic variable in PowerShell, holding the arguments
# this script was called with.
$callArgs = @("'RunTests', true")
if ($Vintage)         { $callArgs += "'Vintage', '$Vintage'" }
if ($Models)          { $callArgs += "'Models', '$Models'" }
if ($DryRun)          { $callArgs += "'DryRun', true" }
if ($AllowUnmeasured) { $callArgs += "'AllowUnmeasured', true" }
$call = "run_release(" + ($callArgs -join ', ') + ")"

Write-Host "call:       $call"
Write-Host "started:    $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n"

& $MatlabExe -batch $call
if ($LASTEXITCODE -ne 0) {
    if ($IfNewData) {
        # Without this, a refused release would re-run the whole estimation
        # every Monday. The watchdog raises an issue once the data have been ahead
        # of the estimates for a week.
        New-Item -ItemType Directory -Force -Path (Join-Path $root 'build') | Out-Null
        @(
            "The Monday trigger's release of $Vintage failed on $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') (MATLAB exit $LASTEXITCODE)."
            "The staged output is under build\staging\$Vintage, and its current\guardrails.csv names each failure."
            "Delete this file to let the trigger try $Vintage again."
        ) | Set-Content -Path (Join-Path $root "build\release_failed_$Vintage.txt") -Encoding utf8
    }
    throw "run_release failed (exit $LASTEXITCODE). Nothing was committed. The staged output is under build\staging\ and its guardrails.csv names each failure."
}

if ($DryRun) {
    Write-Host "`nDry run: nothing promoted, nothing committed." -ForegroundColor Green
    exit 0
}

# ---- what did it promote? -------------------------------------------------
$changed = git status --porcelain -- estimates
if (-not $changed) {
    Write-Host "`nrun_release promoted nothing into estimates/. Nothing to commit." -ForegroundColor Yellow
    exit 0
}

# The vintage is read back out of what was promoted, never guessed here: the
# release names its own quarter and metadata.json is where it recorded it.
$metaPath = Join-Path $root 'estimates\current\metadata.json'
if (-not (Test-Path $metaPath)) { throw "estimates\current\metadata.json is missing after a promoted run." }
$meta = Get-Content $metaPath -Raw | ConvertFrom-Json
$v = $meta.vintage
Write-Host "`npromoted vintage $v, generated $($meta.generated_utc)"
Write-Host "files changed under estimates/:"
$changed | ForEach-Object { Write-Host "  $_" }

# ---- commit and tag -------------------------------------------------------
git add estimates
$msg = @"
Estimates for $v

Trend inflation, the output gap and trend output growth, re-estimated on data
through $v. Every guardrail in estimates/guardrails.m passed; metadata.json
records the seed, settings and source SHA-256 behind each series.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
"@
git commit -m $msg
if ($LASTEXITCODE -ne 0) { throw "git commit failed." }

# The run takes about forty minutes, long enough for the watchdog to have
# committed in the meantime. The release touches only estimates/ and the bots
# only .github/, so replaying the release commit on top cannot conflict. This
# happens before tagging, so the tag names the commit that is pushed.
if (-not $NoPush) {
    git pull --rebase --quiet
    if ($LASTEXITCODE -ne 0) { throw "git pull --rebase failed after the release commit. The commit is local and untagged." }
}

$tag = "v$v"
git tag -a $tag -m "Estimates for $v"
if ($LASTEXITCODE -ne 0) { throw "git tag $tag failed. It may already exist, which means this vintage was already released." }

if ($NoPush) {
    Write-Host "`nCommitted and tagged $tag locally. Not pushed (-NoPush)." -ForegroundColor Green
    exit 0
}

git push origin HEAD
if ($LASTEXITCODE -ne 0) { throw "git push failed. The commit and tag are local." }
git push origin $tag
if ($LASTEXITCODE -ne 0) { throw "pushing tag $tag failed. The commit is pushed; the tag is local." }

Write-Host "`nReleased $v and pushed $tag." -ForegroundColor Green
