#!/usr/bin/env pwsh
# Install restore-desktop-sessions as a Claude Code skill (Windows).
# Links this repo into ~/.claude/skills/restore-desktop-sessions so updates via
# `git pull` take effect immediately. Uses a directory junction, which -- unlike
# a symlink -- needs neither admin rights nor Developer Mode on Windows.

$ErrorActionPreference = "Stop"

$Src = Split-Path -Parent $MyInvocation.MyCommand.Path
$SkillsDir = Join-Path $HOME ".claude\skills"
$Dest = Join-Path $SkillsDir "restore-desktop-sessions"

New-Item -ItemType Directory -Path $SkillsDir -Force | Out-Null

if (Test-Path -LiteralPath $Dest) {
    $item = Get-Item -LiteralPath $Dest -Force
    if ($item.LinkType -notin @("Junction", "SymbolicLink")) {
        Write-Error "$Dest already exists and is not a junction/symlink. Remove/rename it first."
    }
    Remove-Item -LiteralPath $Dest -Force -Recurse
}

try {
    New-Item -ItemType Junction -Path $Dest -Target $Src -ErrorAction Stop | Out-Null
    Write-Output "Installed (junction): $Dest -> $Src"
} catch {
    Write-Output "Junction creation failed ($($_.Exception.Message)); falling back to a plain copy."
    Write-Output "(Updates via 'git pull' won't apply automatically -- rerun this script after pulling.)"
    Copy-Item -Path $Src -Destination $Dest -Recurse -Force
    Write-Output "Installed (copy): $Dest"
}

Write-Output ""
Write-Output "Use it in Claude Code: say `"restore sessions`" or type /restore-desktop-sessions"
Write-Output "Or run directly:       pwsh `"$Src\restore.ps1`""
