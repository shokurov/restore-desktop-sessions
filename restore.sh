#!/usr/bin/env bash
# restore-desktop-sessions
# Make ALL Claude Code desktop sessions ever created on this device appear under
# the CURRENTLY logged-in account (any new Claude id).
#
# Why needed: the Claude desktop "Code" Recents list is scoped per Anthropic
# account. Sessions are stored as thin pointer files:
#   ~/Library/Application Support/Claude/claude-code-sessions/<accountUuid>/<workspaceUuid>/local_<uuid>.json
# each pointing at a CLI transcript in ~/.claude/projects/. Switching login hides
# sessions made under the old account. This script copies every account's pointer
# files into the current account's active workspace so they all list again.
#
# Non-destructive: originals under other accounts are untouched; the current
# account's dir is backed up first. Reversible via the printed backup path.
#
# Usage:
#   restore.sh            # dry-run: show what would be copied
#   restore.sh --apply    # perform the copy (after backup)
#   restore.sh --apply --account <uuid>   # force target account (default = logged-in)
#
# After --apply: FULLY QUIT Claude (Cmd+Q) and reopen — the list is cached in memory.
# Bash 3.2 compatible (macOS default). No associative arrays. Space-safe paths.

set -euo pipefail

SUP="$HOME/Library/Application Support/Claude"
STORE="$SUP/claude-code-sessions"
CFG="$SUP/config.json"

APPLY=0
FORCE_ACCT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1 ;;
    --account) shift; FORCE_ACCT="${1:-}" ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

[ -d "$STORE" ] || { echo "ERROR: desktop session store not found: $STORE"; echo "Is the Claude desktop app installed?"; exit 1; }
command -v jq >/dev/null || { echo "ERROR: jq required."; exit 1; }

# --- current logged-in account ---
if [ -n "$FORCE_ACCT" ]; then
  CUR="$FORCE_ACCT"
else
  CUR="$(jq -r '.lastKnownAccountUuid // empty' "$CFG" 2>/dev/null || true)"
fi
[ -n "$CUR" ] || { echo "ERROR: could not determine current account (lastKnownAccountUuid empty). Log into the desktop app first, or pass --account <uuid>."; exit 1; }
[ -d "$STORE/$CUR" ] || { echo "ERROR: current account '$CUR' has no session dir yet."; echo "Open the desktop app -> Code tab once (start any session), then rerun."; exit 1; }

# --- pick active workspace under current account = dir with newest pointer file ---
# space-safe: only numeric mtimes are compared; paths stay quoted.
TARGET_WS=""
best_mtime=-1
while IFS= read -r ws; do
  [ -d "$ws" ] || continue
  # newest local_*.json mtime in this workspace (0 if none)
  m=0
  while IFS= read -r pf; do
    [ -f "$pf" ] || continue
    t="$(stat -f '%m' "$pf" 2>/dev/null || echo 0)"
    [ "$t" -gt "$m" ] && m="$t"
  done < <(find "$ws" -maxdepth 1 -name 'local_*.json' 2>/dev/null)
  # prefer the workspace with newest pointer; if all empty, still remember one
  if [ "$m" -gt "$best_mtime" ]; then best_mtime="$m"; TARGET_WS="$ws"; fi
done < <(find "$STORE/$CUR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)

[ -n "$TARGET_WS" ] && [ -d "$TARGET_WS" ] || { echo "ERROR: current account has no workspace dir."; echo "Open the desktop app -> Code tab once, then rerun."; exit 1; }

echo "Current account : $CUR"
echo "Active workspace: $(basename "$TARGET_WS")"
echo "Store           : $STORE"
echo

# --- build list of source pointer files from OTHER accounts, dedup by basename ---
TARGET_LIST="$(mktemp)"   # basenames already in target
SEEN_LIST="$(mktemp)"     # basenames queued this run
SRC_LIST="$(mktemp)"      # full source paths to copy
trap 'rm -f "$TARGET_LIST" "$SEEN_LIST" "$SRC_LIST"' EXIT

find "$TARGET_WS" -maxdepth 1 -name 'local_*.json' -exec basename {} \; 2>/dev/null | sort -u > "$TARGET_LIST"

total_src=0; copy_count=0; skip_count=0
while IFS= read -r f; do
  [ -f "$f" ] || continue
  total_src=$((total_src+1))
  b="$(basename "$f")"
  if grep -Fxq "$b" "$TARGET_LIST" || grep -Fxq "$b" "$SEEN_LIST"; then
    skip_count=$((skip_count+1)); continue
  fi
  echo "$b" >> "$SEEN_LIST"
  echo "$f" >> "$SRC_LIST"
  copy_count=$((copy_count+1))
done < <(find "$STORE" -mindepth 3 -maxdepth 3 -name 'local_*.json' -not -path "$STORE/$CUR/*" 2>/dev/null)

echo "Sessions in other accounts : $total_src"
echo "Already present in target  : $skip_count"
echo "New sessions to restore    : $copy_count"

if [ "$APPLY" -ne 1 ]; then
  echo
  echo "DRY-RUN. Re-run with --apply to copy the $copy_count new session(s) into the current account."
  exit 0
fi

# --- backup + apply ---
BK="$HOME/.claude/desktop-session-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BK"
cp -R "$STORE/$CUR" "$BK/current-account-before" 2>/dev/null || true
echo
echo "Backup of current account dir -> $BK"

n=0
while IFS= read -r f; do
  [ -f "$f" ] || continue
  cp -n "$f" "$TARGET_WS/" && n=$((n+1))
done < "$SRC_LIST"

echo "Copied $n new session pointer(s)."
echo "Target now holds: $(find "$TARGET_WS" -maxdepth 1 -name 'local_*.json' | wc -l | tr -d ' ') sessions."
echo
echo "NEXT: FULLY QUIT Claude (Cmd+Q, not just close window) and reopen -> Code tab."
echo "Undo: restore \"$BK/current-account-before\" over \"$STORE/$CUR\" (remove copied local_*.json first)."
