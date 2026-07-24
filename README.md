# restore-desktop-sessions

**Bring back your Claude Code sessions after switching Claude accounts on the desktop app.**

The Claude desktop app's **Code → Recents** list is scoped **per Anthropic account**.
Log in with a different Claude id and every Claude Code session you made under the old
id disappears from the list — even though the conversations are still on your disk.

This tool copies your session entries into the currently logged-in account so your
**full history shows up again**, no matter which id you're signed in as.

> macOS only (that's where the Claude desktop app stores sessions the way this tool
> reads). Non-destructive and reversible. It never uploads anything.

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
~/Library/Application Support/Claude/claude-code-sessions/<accountUuid>/<workspaceUuid>/local_<uuid>.json
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

```bash
git clone https://github.com/arunmauryaaa/restore-desktop-sessions.git
cd restore-desktop-sessions
./install.sh          # symlinks the skill into ~/.claude/skills/
```

Then in Claude Code just say **"restore sessions"** or type `/restore-desktop-sessions`.

### As a standalone script

```bash
curl -fsSL https://raw.githubusercontent.com/arunmauryaaa/restore-desktop-sessions/main/restore.sh -o restore.sh
chmod +x restore.sh
./restore.sh           # dry-run
```

Requires [`jq`](https://jqlang.github.io/jq/) (`brew install jq`).

## Usage

```bash
./restore.sh                       # dry-run: show how many sessions would be restored
./restore.sh --apply               # back up, then copy sessions into current account
./restore.sh --apply --account <uuid>   # force a specific target account
```

Then **fully quit Claude (⌘Q — not just closing the window) and reopen it.** The
Recents list is cached in memory, so it only refreshes on a real relaunch. Open the
**Code** tab and your sessions are back.

### Prerequisites
- You're logged into the desktop app as the id you want the sessions under.
- You've opened the **Code** tab at least once under that id (this creates the
  account + workspace directory the tool copies into). If not, the script tells you.

## Safety

- **Non-destructive.** Other accounts' original files are never modified; copies use
  `cp -n` (no overwrite).
- **Backed up.** Before copying, the current account's directory is saved to
  `~/.claude/desktop-session-backup-<timestamp>/current-account-before`.
- **Local only.** Nothing is uploaded. It only moves files between folders on your Mac.
- **Idempotent.** Dedups by filename, so re-running only copies genuinely new sessions.

### Undo
```bash
# remove the copied pointers from the active workspace, then restore the backup:
rm -f "~/Library/Application Support/Claude/claude-code-sessions/<current-account>/<ws>/local_*.json"
cp -R "~/.claude/desktop-session-backup-<timestamp>/current-account-before/." \
      "~/Library/Application Support/Claude/claude-code-sessions/<current-account>/"
```
(The `--apply` run prints the exact paths for your machine.)

## Notes & limitations

- **macOS only.** Paths and `stat -f` are BSD/macOS. The Windows desktop app stores
  data under `%APPDATA%\Claude` with a different layout — not yet supported.
  PRs welcome.
- A few entries may be cloud-only sessions (no local transcript). They'll list but
  won't resume locally — harmless.
- CLI sessions are always reachable regardless of account via
  `cd <project> && claude --resume`. This tool is specifically about the **desktop
  app's** account-scoped Recents list.
- Written for macOS's default `bash` 3.2; handles the space in "Application Support".

## Why trust it

The script is ~120 lines of plain `bash`, does only file reads + `cp`, and prints a
dry-run of exactly what it will do before you pass `--apply`. Read it first — it's the
whole tool.

## Disclaimer

Unofficial. Not affiliated with Anthropic. It relies on the desktop app's on-disk
session layout, which Anthropic may change in a future release. Always keep the printed
backup until you've confirmed your sessions are back.

## License

[MIT](LICENSE)
