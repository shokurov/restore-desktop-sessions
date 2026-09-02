# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Nothing is tagged yet, so everything below is unreleased.

## [Unreleased]

### Fixed

- **Sessions living in another organization of the *same* account are now restored.**
  The store is laid out as `<accountUuid>/<workspaceUuid>`, where the second level is
  one directory per organization, and the Recents list enumerates exactly one of them.
  Both scripts collected pointer files only from *other account* directories and skipped
  everything under the current account, so switching organization — which empties the
  Recents list just like switching account — restored nothing. Sources are now every
  `<account>/<workspace>` directory except the target one.
- `restore.sh`: `mtime_of` no longer trusts `stat -f '%m'`'s exit code. GNU `stat`
  answers `-f` with filesystem info and exits 0 instead of failing, so the fallback to
  `stat -c '%Y'` never fired off macOS. The result is validated instead.

### Added

- `--workspace <uuid>` (macOS) / `-Workspace <uuid>` (Windows) to force the target
  workspace when the default "workspace holding the newest pointer file" heuristic picks
  the wrong organization.
- The dry-run now lists every workspace of the current account with its session count and
  marks the one it will copy into, so a wrong pick is visible before `--apply`.
- `tests/test-restore.sh` and `tests/test-restore.ps1`: dependency-free harnesses that
  build a synthetic session store in a temp directory (overriding `APPDATA` / `HOME`), so
  real Claude data is never touched. 12 checks each; the PowerShell suite runs under both
  PowerShell 7+ and Windows PowerShell 5.1 (`-Shell powershell`).

### Changed

- Output wording follows the workspace model: "Target workspace" instead of "Active
  workspace", "Sessions in other workspaces" instead of "Sessions in other accounts".
- README and SKILL.md describe the per-organization scoping, the new flag, and the fact
  that `deleted_*` tombstones are never copied back.
