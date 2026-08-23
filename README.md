# restore-desktop-sessions

**Bring back your Claude Code sessions after switching Claude accounts on the desktop app.**

The Claude desktop app's **Code → Recents** list is scoped **per Anthropic account**.
Log in with a different Claude id and every Claude Code session you made under the old
id disappears from the list — even though the conversations are still on your disk.

This tool copies your session entries into the currently logged-in account so your
**full history shows up again**, no matter which id you're signed in as.

> Works on **macOS and Windows**. Non-destructive and reversible. It never uploads
> anything.

---

## The problem

```
Logged in as  A  ─▶  Recents shows A's sessions
Switch to     B  ─▶  Recents shows (almost) nothing — A's sessions are hidden
```

Your transcripts are safe on disk the whole time. They're just filed under the *other*
account, so the current account's Recents list doesn't enumerate them.

## How it works

Claude desktop stores each Code session as a small **pointer file**:

```
macOS:   ~/Library/Application Support/Claude/claude-code-sessions/<accountUuid>/<workspaceUuid>/local_<uuid>.json
Windows: %APPDATA%\Claude\claude-code-sessions\<accountUuid>\<workspaceUuid>\local_<uuid>.json
```

Each pointer holds the session's `title`, `cwd`, `model`, timestamps, and a
`cliSessionId` that references the real transcript in `~/.claude/projects/`.

The Recents list is built by enumerating the pointer files under **the current
account's active workspace** — it is *not* stored in the `claude.ai` IndexedDB /
LevelDB (a scan of that store comes up empty). So sessions created under account **A**
are invisible while you're logged in as **B**, simply because their pointer files live
under `.../A/...` instead of `.../B/...`.

**The fix:** copy the pointer files from every other account into the current account's
active workspace. The transcripts themselves are account-agnostic on disk, so
**resume still works** afterward.

```
claude-code-sessions/
├── A-account/ws/local_*.json   ──┐ copy (cp -n, non-destructive)
├── B-account/ws/local_*.json   ◀─┘ current account gets them all
└── C-account/ws/local_*.json   ──┘
```

## Install

### As a Claude Code skill (recommended)

**macOS:**
```bash
git clone https://github.com/arunmauryaaa/restore-desktop-sessions.git
cd restore-desktop-sessions
./install.sh          # symlinks the skill into ~/.claude/skills/
```

**Windows (PowerShell):**
```powershell
git clone https://github.com/arunmauryaaa/restore-desktop-sessions.git
cd restore-desktop-sessions
.\install.ps1          # links the skill into ~/.claude/skills/ (directory junction)
```

Then in Claude Code just say **"restore sessions"** or type `/restore-desktop-sessions`.

### As a standalone script

**macOS:**
```bash
curl -fsSL https://raw.githubusercontent.com/arunmauryaaa/restore-desktop-sessions/main/restore.sh -o restore.sh
chmod +x restore.sh
./restore.sh           # dry-run
```
Requires [`jq`](https://jqlang.github.io/jq/) (`brew install jq`).

**Windows (PowerShell):**
```powershell
curl.exe -fsSL https://raw.githubusercontent.com/arunmauryaaa/restore-desktop-sessions/main/restore.ps1 -o restore.ps1
.\restore.ps1           # dry-run
```
No extra dependencies — uses PowerShell's built-in JSON support.

## Usage

**macOS:**
```bash
./restore.sh                       # dry-run: show how many sessions would be restored
./restore.sh --apply               # back up, then copy sessions into current account
./restore.sh --apply --account <uuid>   # force a specific target account
```

**Windows:**
```powershell
.\restore.ps1                            # dry-run: show how many sessions would be restored
.\restore.ps1 -Apply                     # back up, then copy sessions into current account
.\restore.ps1 -Apply -Account <uuid>     # force a specific target account
```

Then **fully quit Claude and reopen it.** Closing the window is not enough — the
Recents list is cached in memory, and on both platforms the app keeps running in the
background:
- **macOS:** ⌘Q (not just closing the window).
- **Windows:** right-click the tray icon → Quit/Exit, or End Task on `Claude` in Task
  Manager (the process under `...\WindowsApps\Claude_*`, not the CLI's `claude.exe`).

Reopen and open the **Code** tab — your sessions are back.

### Prerequisites
- You're logged into the desktop app as the id you want the sessions under.
- You've opened the **Code** tab at least once under that id (this creates the
  account + workspace directory the tool copies into). If not, the script tells you.

## Safety

- **Non-destructive.** Other accounts' original files are never modified; copies never
  overwrite an existing file (`cp -n` on macOS; a skip-if-exists copy on Windows).
- **Backed up.** Before copying, the current account's directory is saved to
  `~/.claude/desktop-session-backup-<timestamp>/current-account-before`.
- **Local only.** Nothing is uploaded. It only moves files between folders on your machine.
- **Idempotent.** Dedups by filename, so re-running only copies genuinely new sessions.

### Undo

**macOS:**
```bash
# remove the copied pointers from the active workspace, then restore the backup:
rm -f "~/Library/Application Support/Claude/claude-code-sessions/<current-account>/<ws>/local_*.json"
cp -R "~/.claude/desktop-session-backup-<timestamp>/current-account-before/." \
      "~/Library/Application Support/Claude/claude-code-sessions/<current-account>/"
```

**Windows (PowerShell):**
```powershell
# remove the copied pointers from the active workspace, then restore the backup:
Remove-Item "$env:APPDATA\Claude\claude-code-sessions\<current-account>\<ws>\local_*.json"
Copy-Item "$HOME\.claude\desktop-session-backup-<timestamp>\current-account-before\*" `
          "$env:APPDATA\Claude\claude-code-sessions\<current-account>\" -Recurse -Force
```

(The `--apply` / `-Apply` run prints the exact paths for your machine.)

## Notes & limitations

- A few entries may be cloud-only sessions (no local transcript). They'll list but
  won't resume locally — harmless.
- CLI sessions are always reachable regardless of account via
  `cd <project> && claude --resume`. This tool is specifically about the **desktop
  app's** account-scoped Recents list.
- **macOS:** `restore.sh` targets macOS's default `bash` 3.2 and handles the space in
  "Application Support"; requires `jq`.
- **Windows:** `restore.ps1` targets Windows PowerShell 5.1+ / PowerShell 7+ and has
  no external dependencies. Linux is not covered — the Claude desktop app doesn't
  currently ship there.

## Why trust it

Each script is a couple hundred lines of plain shell (`bash` / PowerShell), does only
file reads + copies, and prints a dry-run of exactly what it will do before you pass
`--apply` / `-Apply`. Read it first — it's the whole tool.

## Disclaimer

Unofficial. Not affiliated with Anthropic. It relies on the desktop app's on-disk
session layout, which Anthropic may change in a future release. Always keep the printed
backup until you've confirmed your sessions are back.

## License

[MIT](LICENSE)
