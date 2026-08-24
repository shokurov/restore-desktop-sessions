# restore-desktop-sessions

**Bring back your Claude Code sessions after switching Claude accounts — or organizations — on the desktop app.**

The Claude desktop app's **Code → Recents** list is scoped **per Anthropic account _and_
per organization**. Log in with a different Claude id, or switch to another organization
under the same id, and every Claude Code session from the previous one disappears from
the list — even though the conversations are still on your disk.

This tool copies your session entries into the workspace the app is currently showing, so
your **full history shows up again**, no matter which id or org you're signed in as.

> Works on **macOS and Windows**. Non-destructive and reversible. It never uploads
> anything.

---

## The problem

```
Logged in as  A  ─▶  Recents shows A's sessions
Switch to     B  ─▶  Recents shows (almost) nothing — A's sessions are hidden
```

The same thing happens without changing account at all: switch **organization** in the
app and the Recents list empties out, because each org gets its own workspace directory.

Your transcripts are safe on disk the whole time. They're just filed under the *other*
account/org directory, so the list the app is showing doesn't enumerate them.

## How it works

Claude desktop stores each Code session as a small **pointer file**:

```
macOS:   ~/Library/Application Support/Claude/claude-code-sessions/<accountUuid>/<workspaceUuid>/local_<uuid>.json
Windows: %APPDATA%\Claude\claude-code-sessions\<accountUuid>\<workspaceUuid>\local_<uuid>.json
```

`<workspaceUuid>` is **one directory per organization** you belong to. Each pointer holds
the session's `title`, `cwd`, `model`, timestamps, and a `cliSessionId` that references
the real transcript in `~/.claude/projects/`.

The Recents list is built by enumerating the pointer files in **exactly one directory** —
the current account's currently-selected workspace. It is *not* stored in the `claude.ai`
IndexedDB / LevelDB (a scan of that store comes up empty). So a session is invisible
whenever it was created under a *different* account **or** a different organization,
simply because its pointer file lives in another directory.

**The fix:** copy the pointer files from every other account+workspace directory into the
one the app is showing. The transcripts themselves are account-agnostic on disk, so
**resume still works** afterward.

```
claude-code-sessions/
├── A-account/org-1/local_*.json   ──┐
├── A-account/org-2/local_*.json   ──┤ copy (never overwrites)
├── B-account/org-3/local_*.json   ◀─┘ the workspace the app shows gets them all
└── C-account/org-4/local_*.json   ──┘
```

The script prints every workspace of the current account and marks the one it picked
(the one holding the newest pointer file — normally the one on screen, since opening or
focusing a session rewrites its pointer). If it guessed wrong, pass
`--workspace <uuid>` / `-Workspace <uuid>`.

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
./restore.sh --apply               # back up, then copy sessions into the target workspace
./restore.sh --apply --account <uuid>     # force a specific target account
./restore.sh --apply --workspace <uuid>   # force a specific target workspace (org)
```

**Windows:**
```powershell
.\restore.ps1                            # dry-run: show how many sessions would be restored
.\restore.ps1 -Apply                     # back up, then copy sessions into the target workspace
.\restore.ps1 -Apply -Account <uuid>     # force a specific target account
.\restore.ps1 -Apply -Workspace <uuid>   # force a specific target workspace (org)
```

The dry-run lists every workspace of the current account with its session count and
marks the one it will copy into. If that's not the workspace the app is showing you,
rerun with `--workspace` / `-Workspace`.

Then **fully quit Claude and reopen it.** Closing the window is not enough — the
Recents list is cached in memory, and on both platforms the app keeps running in the
background:
- **macOS:** ⌘Q (not just closing the window).
- **Windows:** right-click the tray icon → Quit/Exit, or End Task on `Claude` in Task
  Manager (the process under `...\WindowsApps\Claude_*`, not the CLI's `claude.exe`).

Reopen and open the **Code** tab — your sessions are back.

### Prerequisites
- You're logged into the desktop app as the id (and switched to the org) you want the
  sessions under.
- You've opened the **Code** tab at least once there (this creates the account +
  workspace directory the tool copies into). If not, the script tells you.

## Safety

- **Non-destructive.** The source directories are never modified; copies never
  overwrite an existing file (`cp -n` on macOS; a skip-if-exists copy on Windows).
  Deleted sessions (`deleted_*` tombstones) are not resurrected — only `local_*.json`
  pointers are copied.
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
  app's** account- and org-scoped Recents list.
- Merging is one-way: the sessions are copied into the target workspace, so switching
  org afterwards shows that org's own list again (rerun the tool if you want the merge
  there too).
- **macOS:** `restore.sh` targets macOS's default `bash` 3.2 and handles the space in
  "Application Support"; requires `jq`.
- **Windows:** `restore.ps1` targets Windows PowerShell 5.1+ / PowerShell 7+ and has
  no external dependencies. Linux is not covered — the Claude desktop app doesn't
  currently ship there.

## Tests

Both scripts have a dependency-free test harness that builds a synthetic session store
in a temp dir (overriding `APPDATA` / `HOME`), so your real Claude data is never touched:

```bash
bash tests/test-restore.sh
```

```powershell
pwsh tests/test-restore.ps1                    # also: -Shell powershell for 5.1
```

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
