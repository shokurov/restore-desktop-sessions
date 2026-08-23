#!/usr/bin/env pwsh
# restore-desktop-sessions (Windows)
# Make ALL Claude Code desktop sessions ever created on this device appear under
# the CURRENTLY logged-in account (any new Claude id).
#
# Why needed: the Claude desktop "Code" Recents list is scoped per Anthropic
# account. Sessions are stored as thin pointer files:
#   %APPDATA%\Claude\claude-code-sessions\<accountUuid>\<workspaceUuid>\local_<uuid>.json
# each pointing at a CLI transcript in ~/.claude/projects/. Switching login hides
# sessions made under the old account. This script copies every account's pointer
# files into the current account's active workspace so they all list again.
#
# Non-destructive: originals under other accounts are untouched; the current
# account's dir is backed up first. Reversible via the printed backup path.
#
# Usage:
#   restore.ps1                        # dry-run: show what would be copied
#   restore.ps1 -Apply                 # perform the copy (after backup)
#   restore.ps1 -Apply -Account <uuid> # force target account (default = logged-in)
#
# After -Apply: FULLY QUIT Claude (it's a background app even after the window
# closes — see the printed instructions) and reopen it; the Recents list is
# cached in memory.
#
# Windows PowerShell 5.1 and PowerShell 7+ compatible. No external dependencies —
# JSON is parsed with the built-in ConvertFrom-Json (unlike the macOS script's jq).

[CmdletBinding()]
param(
    [switch]$Apply,
    [string]$Account
)

$ErrorActionPreference = "Stop"

$Sup = Join-Path $env:APPDATA "Claude"
$Store = Join-Path $Sup "claude-code-sessions"
$Cfg = Join-Path $Sup "config.json"

if (-not (Test-Path -LiteralPath $Store)) {
    Write-Error "desktop session store not found: $Store`nIs the Claude desktop app installed?"
}

# --- current logged-in account ---
if ($Account) {
    $Cur = $Account
} else {
    $Cur = ""
    if (Test-Path -LiteralPath $Cfg) {
        try {
            $configJson = Get-Content -LiteralPath $Cfg -Raw | ConvertFrom-Json
            if ($configJson.lastKnownAccountUuid) { $Cur = $configJson.lastKnownAccountUuid }
        } catch { }
    }
}
if ([string]::IsNullOrWhiteSpace($Cur)) {
    Write-Error "could not determine current account (lastKnownAccountUuid empty). Log into the desktop app first, or pass -Account <uuid>."
}

$CurDir = Join-Path $Store $Cur
if (-not (Test-Path -LiteralPath $CurDir)) {
    Write-Error "current account '$Cur' has no session dir yet.`nOpen the desktop app -> Code tab once (start any session), then rerun."
}

# --- pick active workspace under current account = dir with newest pointer file ---
$TargetWs = $null
$bestMtime = -1
foreach ($ws in Get-ChildItem -LiteralPath $CurDir -Directory -ErrorAction SilentlyContinue) {
    $m = 0
    foreach ($pf in Get-ChildItem -LiteralPath $ws.FullName -Filter "local_*.json" -File -ErrorAction SilentlyContinue) {
        $t = [DateTimeOffset]::new($pf.LastWriteTimeUtc, [TimeSpan]::Zero).ToUnixTimeSeconds()
        if ($t -gt $m) { $m = $t }
    }
    if ($m -gt $bestMtime) {
        $bestMtime = $m
        $TargetWs = $ws.FullName
    }
}

if (-not $TargetWs -or -not (Test-Path -LiteralPath $TargetWs)) {
    Write-Error "current account has no workspace dir.`nOpen the desktop app -> Code tab once, then rerun."
}

Write-Output "Current account : $Cur"
Write-Output "Active workspace: $(Split-Path $TargetWs -Leaf)"
Write-Output "Store           : $Store"
Write-Output ""

# --- build list of source pointer files from OTHER accounts, dedup by filename ---
$targetNames = @{}
foreach ($f in Get-ChildItem -LiteralPath $TargetWs -Filter "local_*.json" -File -ErrorAction SilentlyContinue) {
    $targetNames[$f.Name] = $true
}

$seen = @{}
$srcFiles = New-Object System.Collections.Generic.List[string]

$totalSrc = 0
$skipCount = 0

$otherAccountDirs = Get-ChildItem -LiteralPath $Store -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne $Cur }
foreach ($acctDir in $otherAccountDirs) {
    foreach ($wsDir in Get-ChildItem -LiteralPath $acctDir.FullName -Directory -ErrorAction SilentlyContinue) {
        foreach ($f in Get-ChildItem -LiteralPath $wsDir.FullName -Filter "local_*.json" -File -ErrorAction SilentlyContinue) {
            $totalSrc++
            $b = $f.Name
            if ($targetNames.ContainsKey($b) -or $seen.ContainsKey($b)) {
                $skipCount++
                continue
            }
            $seen[$b] = $true
            $srcFiles.Add($f.FullName)
        }
    }
}
$copyCount = $srcFiles.Count

Write-Output "Sessions in other accounts : $totalSrc"
Write-Output "Already present in target  : $skipCount"
Write-Output "New sessions to restore    : $copyCount"

if (-not $Apply) {
    Write-Output ""
    Write-Output "DRY-RUN. Re-run with -Apply to copy the $copyCount new session(s) into the current account."
    exit 0
}

# --- backup + apply ---
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$Bk = Join-Path $HOME ".claude\desktop-session-backup-$timestamp"
New-Item -ItemType Directory -Path $Bk -Force | Out-Null
try {
    Copy-Item -LiteralPath $CurDir -Destination (Join-Path $Bk "current-account-before") -Recurse -Force
} catch { }
Write-Output ""
Write-Output "Backup of current account dir -> $Bk"

$n = 0
foreach ($f in $srcFiles) {
    $dest = Join-Path $TargetWs (Split-Path $f -Leaf)
    if (-not (Test-Path -LiteralPath $dest)) {
        Copy-Item -LiteralPath $f -Destination $dest
        $n++
    }
}

Write-Output "Copied $n new session pointer(s)."
$finalCount = (Get-ChildItem -LiteralPath $TargetWs -Filter "local_*.json" -File -ErrorAction SilentlyContinue).Count
Write-Output "Target now holds: $finalCount sessions."
Write-Output ""
Write-Output "NEXT: FULLY QUIT Claude and reopen -> Code tab. Closing the window is not"
Write-Output "enough -- Claude Desktop keeps running in the background on Windows too:"
Write-Output "  1. Right-click the Claude icon in the system tray (near the clock) and"
Write-Output "     choose Quit/Exit, if it's there."
Write-Output "  2. Otherwise, open Task Manager and End Task on 'Claude' (the process"
Write-Output "     under ...\WindowsApps\Claude_*, not the Claude Code CLI)."
Write-Output "  3. Relaunch from the Start menu, or:"
Write-Output "     explorer.exe shell:AppsFolder\Claude_pzs8sxrjxfjjc!Claude"
Write-Output ""
Write-Output "Undo: restore `"$Bk\current-account-before`" over `"$CurDir`" (remove copied local_*.json first)."
