<#
.SYNOPSIS
  Produce one quarterly release: estimate, check, promote, commit, tag, push.

.DESCRIPTION
  The scheduled entry point. It runs run_release.m under `matlab -batch`, and
  commits only what that run promoted into estimates/.

  Everything that decides whether a release is fit to publish lives in MATLAB,
  in estimates/guardrails.m. This script decides nothing. It runs the release,
  reads its exit status, and stops on a non-zero one - because `matlab -batch`
  exits 0 on a NaN posterior, and the only thing that separates a refused
  release from a published one is run_release erroring and this script noticing.

  Nothing is committed when the guardrails fail. The staging tree under build/
  is git-ignored, so a refused release leaves the tracked tree exactly as it
  was, and the numbers are still there to look at.

.PARAMETER Vintage
  'YYYYQq'. Default: whatever run_release picks, which is the quarter that ended
  before today.

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
  .\tools\run_update.ps1 -DryRun
  .\tools\run_update.ps1 -Vintage 2026Q3 -NoPush
#>

[CmdletBinding()]
param(
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
