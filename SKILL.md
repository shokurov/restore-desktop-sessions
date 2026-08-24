---
name: restore-desktop-sessions
description: Restore ALL Claude Code desktop sessions on this machine into the workspace the desktop app is currently showing. The desktop "Code" Recents list is scoped per Anthropic account AND per organization, so logging in with a new id — or just switching org — hides the sessions made under the previous one. This copies every other account+workspace's session pointer files into the current one so the full history lists again. Works on macOS and Windows. Trigger when the user says "restore sessions", "my old sessions are missing after login", "sessions disappeared after switching organization", "sessions not showing in Claude desktop", "bring back my sessions", "restore every session to new id", or types /restore-desktop-sessions.
metadata:
  type: reference
---

# restore-desktop-sessions

Makes every Claude Code desktop session ever created on this machine appear in the
**workspace the desktop app is currently showing**.

## When to use
The user's Claude Code sessions vanished from the **Code → Recents** list after they
logged in with a different Claude id **or switched organization** under the same id.
Use this to merge every account+workspace's sessions into the one on screen.

Note both causes: an org switch empties the list exactly like an account switch, and
users usually describe either one as "another account".

## How it works (mechanism)
Claude desktop stores each Code session as a thin **pointer file**:

- **macOS:** `~/Library/Application Support/Claude/claude-code-sessions/<accountUuid>/<workspaceUuid>/local_<uuid>.json`
- **Windows:** `%APPDATA%\Claude\claude-code-sessions\<accountUuid>\<workspaceUuid>\local_<uuid>.json`

`<workspaceUuid>` is **one dir per organization** the account belongs to. Each pointer
holds `cliSessionId`, `cwd`, `title`, `model`, timestamps — and references the real
transcript in `~/.claude/projects/`. The Recents list is built by enumerating pointer
files in **exactly one dir** — the current account's currently-selected workspace (it is
NOT stored in the `claude.ai` IndexedDB/LevelDB — that scan comes up empty).

So a session is invisible whenever its pointer sits in a different account dir **or a
different workspace dir**. The fix is to copy those pointers into the dir the app is
showing. The transcripts themselves are account-agnostic on disk, so resume still works.

Current account = `lastKnownAccountUuid` in the app's `config.json`
(macOS: `~/Library/Application Support/Claude/config.json`;
Windows: `%APPDATA%\Claude\config.json`).
Target workspace = the workspace dir under that account holding the newest pointer
(opening or focusing a session rewrites its pointer, so this normally *is* the one on
screen). Only `local_*.json` is copied — `deleted_*` tombstones stay put.

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

   The dry-run also lists **every workspace of the current account** with its session
   count and marks (`->`) the one it will copy into. If the user says the app is showing
   a different org, or the marked workspace holds far fewer sessions than they expect,
   rerun with `--workspace` / `-Workspace` for the right uuid.

3. **Apply** (backs up the current account dir first, then copies):
   - **macOS:**
     ```bash
     bash ~/.claude/skills/restore-desktop-sessions/restore.sh --apply
     ```
     Optional `--account <uuid>` / `--workspace <uuid>` force the target account /
     workspace instead of the logged-in + newest-pointer defaults.
   - **Windows:**
     ```powershell
     pwsh ~/.claude/skills/restore-desktop-sessions/restore.ps1 -Apply
     ```
     Optional `-Account <uuid>` / `-Workspace <uuid>` force the target account /
     workspace instead of the logged-in + newest-pointer defaults.

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
- Non-destructive: the source dirs are never modified; copies use
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
- Merging is one-way into the target workspace — switching org afterwards shows that
  org's own list again; rerun the tool there if the merge should follow.
- Tests: `bash tests/test-restore.sh` / `pwsh tests/test-restore.ps1` build a synthetic
  store in a temp dir (APPDATA/HOME overridden), so real data is never touched.
