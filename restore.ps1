#!/usr/bin/env pwsh
# restore-desktop-sessions (Windows)
# Make ALL Claude Code desktop sessions ever created on this device appear in the
# desktop app's Code -> Recents list as it is scoped right now.
#
# Why needed: the Recents list is built from exactly ONE directory - the current
# account's currently-selected workspace (there is one workspace dir per
# organization you belong to). Sessions are stored as thin pointer files:
#   %APPDATA%\Claude\claude-code-sessions\<accountUuid>\<workspaceUuid>\local_<uuid>.json
# each pointing at a CLI transcript in ~/.claude/projects/. Sessions therefore
# disappear from the list both when you log in with a different Claude id AND when
# you switch organization/workspace under the same id. This script copies the
# pointer files from every OTHER account+workspace dir into the target one.
#
# Non-destructive: source dirs are never modified; the current account's dir is
# backed up first. Reversible via the printed backup path.
#
# Usage:
#   restore.ps1                          # dry-run: show what would be copied
#   restore.ps1 -Apply                   # perform the copy (after backup)
#   restore.ps1 -Apply -Account <uuid>   # force target account (default = logged-in)
#   restore.ps1 -Apply -Workspace <uuid> # force target workspace (default = newest)
#
# The default target workspace is the one holding the newest pointer file. When the
# current account has more than one workspace they are ALL listed - check that the
# marked one is the workspace the app is actually showing you, and pass -Workspace
# if it is not.
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
    [string]$Account,
    [string]$Workspace
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

# --- workspaces under the current account (one dir per organization) ---
$candidates = New-Object System.Collections.Generic.List[object]
foreach ($ws in Get-ChildItem -LiteralPath $CurDir -Directory -ErrorAction SilentlyContinue) {
    $pointers = @(Get-ChildItem -LiteralPath $ws.FullName -Filter "local_*.json" -File -ErrorAction SilentlyContinue)
    $newest = [datetime]::MinValue
    foreach ($pf in $pointers) {
        if ($pf.LastWriteTimeUtc -gt $newest) { $newest = $pf.LastWriteTimeUtc }
    }
    $candidates.Add([PSCustomObject]@{
        Name   = $ws.Name
        Path   = $ws.FullName
        Count  = $pointers.Count
        Newest = $newest
    })
}

if ($candidates.Count -eq 0) {
    Write-Error "current account has no workspace dir.`nOpen the desktop app -> Code tab once, then rerun."
}

$ranked = @($candidates | Sort-Object -Property Newest -Descending)

# --- pick the target workspace ---
if ($Workspace) {
    $target = $ranked | Where-Object { $_.Name -eq $Workspace } | Select-Object -First 1
    if (-not $target) {
        $known = ($ranked | ForEach-Object { $_.Name }) -join ", "
        Write-Error "workspace '$Workspace' not found under account '$Cur'.`nKnown workspaces: $known"
    }
} else {
    # Default: the workspace holding the newest pointer file. Opening or focusing a
    # session rewrites its pointer, so this is normally the workspace the app shows.
    $target = $ranked[0]
}
$TargetWs = $target.Path

Write-Output "Current account : $Cur"
Write-Output "Target workspace: $($target.Name)"
Write-Output "Store           : $Store"
Write-Output ""

# --- list every workspace of this account so a wrong pick is obvious ---
Write-Output "Workspaces under this account (one per organization):"
foreach ($c in $ranked) {
    if ($c.Path -eq $TargetWs) { $mark = "->" } else { $mark = "  " }
    if ($c.Newest -eq [datetime]::MinValue) {
        $when = "(no sessions)"
    } else {
        $when = "newest " + $c.Newest.ToLocalTime().ToString("yyyy-MM-dd HH:mm")
    }
    Write-Output ("  {0} {1}  {2,4} session(s)  {3}" -f $mark, $c.Name, $c.Count, $when)
}
if ($ranked.Count -gt 1) {
    Write-Output ""
    Write-Output "If '->' is not the workspace the app is showing you, rerun with -Workspace <uuid>."
}
Write-Output ""

# --- collect source pointers from every OTHER workspace, dedup by filename ---
# "Other" = every <account>\<workspace> dir except the target one, INCLUDING other
# workspaces of the current account: switching organization hides sessions exactly
# the way switching account does.
$targetNames = @{}
foreach ($f in Get-ChildItem -LiteralPath $TargetWs -Filter "local_*.json" -File -ErrorAction SilentlyContinue) {
    $targetNames[$f.Name] = $true
}

$seen = @{}
$srcFiles = New-Object System.Collections.Generic.List[string]

$totalSrc = 0
$skipCount = 0

foreach ($acctDir in Get-ChildItem -LiteralPath $Store -Directory -ErrorAction SilentlyContinue) {
    foreach ($wsDir in Get-ChildItem -LiteralPath $acctDir.FullName -Directory -ErrorAction SilentlyContinue) {
        if ($wsDir.FullName -eq $TargetWs) { continue }
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

Write-Output "Sessions in other workspaces : $totalSrc"
Write-Output "Already present in target    : $skipCount"
Write-Output "New sessions to restore      : $copyCount"

if (-not $Apply) {
    Write-Output ""
    Write-Output "DRY-RUN. Re-run with -Apply to copy the $copyCount new session(s) into the target workspace."
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
$finalCount = @(Get-ChildItem -LiteralPath $TargetWs -Filter "local_*.json" -File -ErrorAction SilentlyContinue).Count
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
