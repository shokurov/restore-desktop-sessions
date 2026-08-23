---
name: restore-desktop-sessions
description: Restore ALL Claude Code desktop sessions on this machine into the currently logged-in Claude account. The desktop "Code" Recents list is scoped per Anthropic account, so logging in with a new id hides sessions made under an old id. This copies every account's session pointer files into the current account's active workspace so the full history lists again. Works on macOS and Windows. Trigger when the user says "restore sessions", "my old sessions are missing after login", "sessions not showing in Claude desktop", "bring back my sessions", "restore every session to new id", or types /restore-desktop-sessions.
metadata:
  type: reference
---

# restore-desktop-sessions

Makes every Claude Code desktop session ever created on this machine appear under
the **currently logged-in** account.

## When to use
User logged into the Claude desktop app with a different Claude id and their old
Claude Code sessions vanished from the **Code → Recents** list. Use this to merge
all accounts' sessions into the current one.

## How it works (mechanism)
Claude desktop stores each Code session as a thin **pointer file**:

- **macOS:** `~/Library/Application Support/Claude/claude-code-sessions/<accountUuid>/<workspaceUuid>/local_<uuid>.json`
- **Windows:** `%APPDATA%\Claude\claude-code-sessions\<accountUuid>\<workspaceUuid>\local_<uuid>.json`

Each pointer holds `cliSessionId`, `cwd`, `title`, `model`, timestamps — and
references the real transcript in `~/.claude/projects/`. The Recents list is built
by enumerating pointer files under **the current account's active workspace only**
(it is NOT stored in the `claude.ai` IndexedDB/LevelDB — that scan comes up empty).

So: sessions made under account A are invisible while logged in as account B,
because their pointer files sit in `.../A/...` not `.../B/...`. The fix is to copy
the pointer files into the current account's active workspace dir. The transcripts
themselves are account-agnostic on disk, so resume still works.

Current account = `lastKnownAccountUuid` in the app's `config.json`
(macOS: `~/Library/Application Support/Claude/config.json`;
Windows: `%APPDATA%\Claude\config.json`).
Active workspace = the workspace dir under that account holding the newest pointer.

## Steps
1. **Prereq:** user is logged into the desktop app as the target id, and has opened
   the **Code** tab at least once (creates the account + active workspace dir). If
   the current account has no workspace yet, the script says so — tell them to open
   Code once and rerun.

2. **Dry-run first** (always) to show the count. Pick the script for the platform
   you're running on:
   - **macOS:**
     ```bash
     bash ~/.claude/skills/restore-desktop-sessions/restore.sh
     ```
   - **Windows:**
     ```powershell
     pwsh ~/.claude/skills/restore-desktop-sessions/restore.ps1
     ```
   Report "N new sessions to restore" to the user.

3. **Apply** (backs up the current account dir first, then copies):
   - **macOS:**
     ```bash
     bash ~/.claude/skills/restore-desktop-sessions/restore.sh --apply
     ```
     Optional `--account <uuid>` forces a target account instead of the logged-in one.
   - **Windows:**
     ```powershell
     pwsh ~/.claude/skills/restore-desktop-sessions/restore.ps1 -Apply
     ```
     Optional `-Account <uuid>` forces a target account instead of the logged-in one.

4. **Tell the user to fully quit + reopen** the app — the list is cached in memory:
   - **macOS:** **Cmd+Q** (not just closing the window; the red dot only hides it).
     Reopen → **Code** tab → sessions appear in Recents.
   - **Windows:** Closing the window is not enough — Claude Desktop is a packaged
     app (MSIX, family name `Claude_pzs8sxrjxfjjc`) that keeps running in the
     background. Right-click its icon in the system tray and choose Quit/Exit if
     present; otherwise use Task Manager to End Task on `Claude` (the process
     under `...\WindowsApps\Claude_*` — not the Claude Code CLI's `claude.exe`).
     Reopen from the Start menu, or run
     `explorer.exe shell:AppsFolder\Claude_pzs8sxrjxfjjc!Claude` → **Code** tab.

   You cannot quit the app yourself (controlling Claude's own window is blocked).

## Safety / reversibility
- Non-destructive: other accounts' originals are never modified; copies use
  `cp -n` (macOS) / a copy that skips existing filenames (Windows) — never overwrite.
- The current account's dir is backed up to
  `~/.claude/desktop-session-backup-<timestamp>/current-account-before` before any copy.
- Undo = remove the copied `local_*.json` from the active workspace and restore the
  backup over the current account's directory under `claude-code-sessions/`.
- A few entries may be cloud-only sessions (no local transcript) — they list but
  won't resume locally; harmless.

## Notes
- **macOS:** `restore.sh`, bash 3.2 compatible; handles the space in "Application
  Support"; requires `jq`.
- **Windows:** `restore.ps1`, PowerShell 5.1+ / PowerShell 7+ compatible; no
  external dependencies (uses the built-in `ConvertFrom-Json`).
- Dedups by pointer filename, so re-running is idempotent (only new sessions copied).
