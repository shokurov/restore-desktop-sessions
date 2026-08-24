#!/usr/bin/env pwsh
# Test harness for restore.ps1 — dependency-free (no Pester).
#
# Builds a synthetic session store in a temp dir and runs restore.ps1 against it
# by overriding APPDATA (store root) and USERPROFILE/HOME (backup root), so the
# real Claude data dir is never touched.
#
# Usage:
#   pwsh tests/test-restore.ps1                 # test with pwsh
#   pwsh tests/test-restore.ps1 -Shell powershell   # test under Windows PowerShell 5.1

[CmdletBinding()]
param([string]$Shell = "pwsh")

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$Script = Join-Path $RepoRoot "restore.ps1"
$ShellPath = (Get-Command $Shell -ErrorAction SilentlyContinue).Source
if (-not $ShellPath) { Write-Error "shell '$Shell' not found on PATH" }

$script:Failures = 0
$script:Checks = 0

function Assert-Equal {
    param($Expected, $Actual, [string]$Label)
    $script:Checks++
    if ($Expected -eq $Actual) {
        Write-Host "  ok   $Label (= $Actual)" -ForegroundColor Green
    } else {
        Write-Host "  FAIL $Label : expected $Expected, got $Actual" -ForegroundColor Red
        $script:Failures++
    }
}

function Assert-Match {
    param([string]$Pattern, [string]$Text, [string]$Label)
    $script:Checks++
    if ($Text -match $Pattern) {
        Write-Host "  ok   $Label" -ForegroundColor Green
    } else {
        Write-Host "  FAIL $Label : /$Pattern/ not found in output" -ForegroundColor Red
        $script:Failures++
    }
}

# --- fixture -----------------------------------------------------------------
# accountCUR (logged in)
#   orgTARGET : 2 pointers, newest mtime  -> the active workspace
#   orgSIBLING: 3 pointers, older         -> same account, DIFFERENT org
# accountOLD
#   orgOLD    : 2 pointers, oldest
function New-Fixture {
    $rootDir = Join-Path ([System.IO.Path]::GetTempPath()) ("rds-test-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
    $appData = Join-Path $rootDir "AppData"
    $home_ = Join-Path $rootDir "home"
    $store = Join-Path $appData "Claude\claude-code-sessions"

    $fx = [ordered]@{
        Root     = $rootDir
        AppData  = $appData
        Home     = $home_
        Store    = $store
        AcctCur  = "aaaaaaaa-0000-0000-0000-000000000001"
        AcctOld  = "bbbbbbbb-0000-0000-0000-000000000002"
        OrgTarget  = "11111111-0000-0000-0000-00000000000a"
        OrgSibling = "22222222-0000-0000-0000-00000000000b"
        OrgOld     = "33333333-0000-0000-0000-00000000000c"
    }

    New-Item -ItemType Directory -Path (Join-Path $appData "Claude") -Force | Out-Null
    New-Item -ItemType Directory -Path $home_ -Force | Out-Null

    '{"lastKnownAccountUuid":"' + $fx.AcctCur + '"}' |
        Set-Content -LiteralPath (Join-Path $appData "Claude\config.json") -Encoding ASCII

    $now = Get-Date
    $plan = @(
        @{ Acct = $fx.AcctCur; Org = $fx.OrgTarget;  Names = @("local_t1.json", "local_t2.json");                  Age = 1 }
        @{ Acct = $fx.AcctCur; Org = $fx.OrgSibling; Names = @("local_s1.json", "local_s2.json", "local_s3.json"); Age = 30 }
        @{ Acct = $fx.AcctOld; Org = $fx.OrgOld;     Names = @("local_o1.json", "local_o2.json");                  Age = 90 }
    )
    foreach ($p in $plan) {
        $dir = Join-Path $store (Join-Path $p.Acct $p.Org)
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        foreach ($n in $p.Names) {
            $f = Join-Path $dir $n
            ('{"sessionId":"' + $n + '"}') | Set-Content -LiteralPath $f -Encoding ASCII
            (Get-Item -LiteralPath $f).LastWriteTime = $now.AddMinutes(-$p.Age)
        }
        # a non-pointer file the tool must ignore
        "{}" | Set-Content -LiteralPath (Join-Path $dir "scheduled-tasks.json") -Encoding ASCII
    }
    return $fx
}

function Invoke-Restore {
    param($Fx, [string[]]$Arguments = @())
    $saved = @{
        APPDATA     = $env:APPDATA
        USERPROFILE = $env:USERPROFILE
        HOME        = $env:HOME
        HOMEDRIVE   = $env:HOMEDRIVE
        HOMEPATH    = $env:HOMEPATH
    }
    try {
        $env:APPDATA = $Fx.AppData
        $env:USERPROFILE = $Fx.Home
        $env:HOME = $Fx.Home
        $env:HOMEDRIVE = (Split-Path -Qualifier $Fx.Home)
        $env:HOMEPATH = (Split-Path -NoQualifier $Fx.Home)
        $out = & $ShellPath -NoProfile -File $Script @Arguments 2>&1
        return ($out | Out-String)
    } finally {
        foreach ($k in $saved.Keys) { Set-Item -Path ("env:" + $k) -Value $saved[$k] -ErrorAction SilentlyContinue }
    }
}

function Count-Pointers {
    param([string]$Dir)
    return (Get-ChildItem -LiteralPath $Dir -Filter "local_*.json" -File -ErrorAction SilentlyContinue).Count
}

# --- tests -------------------------------------------------------------------
Write-Host "restore.ps1 tests ($Shell)" -ForegroundColor Cyan
Write-Host ""

Write-Host "TEST 1: merges every other workspace, including sibling orgs of the current account"
$fx = New-Fixture
$targetDir = Join-Path $fx.Store (Join-Path $fx.AcctCur $fx.OrgTarget)
$siblingDir = Join-Path $fx.Store (Join-Path $fx.AcctCur $fx.OrgSibling)
$oldDir = Join-Path $fx.Store (Join-Path $fx.AcctOld $fx.OrgOld)

$dry = Invoke-Restore -Fx $fx
Assert-Match ([regex]::Escape($fx.OrgTarget)) $dry "dry-run picks the newest workspace as target"
Assert-Match "New sessions to restore\s*:\s*5" $dry "dry-run counts 3 sibling-org + 2 other-account sessions"
Assert-Equal 2 (Count-Pointers $targetDir) "dry-run copies nothing"

$apply = Invoke-Restore -Fx $fx -Arguments @("-Apply")
Assert-Equal 7 (Count-Pointers $targetDir) "target holds its own 2 + 5 restored"
Assert-Equal 3 (Count-Pointers $siblingDir) "sibling org untouched"
Assert-Equal 2 (Count-Pointers $oldDir) "other account untouched"
Assert-Equal 0 (Get-ChildItem -LiteralPath $targetDir -Filter "scheduled-tasks*" -File | Where-Object { $_.Name -ne "scheduled-tasks.json" } | Measure-Object).Count "no stray non-pointer copies"
Assert-Equal $true (Test-Path (Join-Path $fx.Home ".claude")) "backup written under the overridden HOME"

Write-Host ""
Write-Host "TEST 2: re-running is idempotent"
$again = Invoke-Restore -Fx $fx
Assert-Match "New sessions to restore\s*:\s*0" $again "second dry-run finds nothing new"
Remove-Item -LiteralPath $fx.Root -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "TEST 3: -Workspace forces the target workspace"
$fx2 = New-Fixture
$sib2 = Join-Path $fx2.Store (Join-Path $fx2.AcctCur $fx2.OrgSibling)
$tgt2 = Join-Path $fx2.Store (Join-Path $fx2.AcctCur $fx2.OrgTarget)
$out2 = Invoke-Restore -Fx $fx2 -Arguments @("-Apply", "-Workspace", $fx2.OrgSibling)
Assert-Equal 7 (Count-Pointers $sib2) "forced workspace holds its own 3 + 4 restored"
Assert-Equal 2 (Count-Pointers $tgt2) "default target untouched when overridden"
Remove-Item -LiteralPath $fx2.Root -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "TEST 4: multiple workspaces are listed so the user can spot a wrong pick"
$fx3 = New-Fixture
$out3 = Invoke-Restore -Fx $fx3
Assert-Match ([regex]::Escape($fx3.OrgSibling)) $out3 "candidate workspaces are printed"
Remove-Item -LiteralPath $fx3.Root -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ""
if ($script:Failures -gt 0) {
    Write-Host "$($script:Failures)/$($script:Checks) checks FAILED" -ForegroundColor Red
    exit 1
}
Write-Host "all $($script:Checks) checks passed" -ForegroundColor Green
exit 0
