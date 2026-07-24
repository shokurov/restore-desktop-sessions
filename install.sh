#!/usr/bin/env bash
# Install restore-desktop-sessions as a Claude Code skill.
# Symlinks this repo into ~/.claude/skills/restore-desktop-sessions so updates
# via `git pull` take effect immediately.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="$HOME/.claude/skills/restore-desktop-sessions"

command -v jq >/dev/null || echo "WARNING: 'jq' not found — install it: brew install jq"

mkdir -p "$HOME/.claude/skills"
if [ -e "$DEST" ] && [ ! -L "$DEST" ]; then
  echo "ERROR: $DEST already exists and is not a symlink. Remove/rename it first."
  exit 1
fi
ln -sfn "$SRC" "$DEST"
chmod +x "$SRC/restore.sh"

echo "Installed: $DEST -> $SRC"
echo
echo "Use it in Claude Code: say \"restore sessions\" or type /restore-desktop-sessions"
echo "Or run directly:       $SRC/restore.sh"
