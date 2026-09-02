#!/usr/bin/env bash
# restore-desktop-sessions
# Make ALL Claude Code desktop sessions ever created on this device appear in the
# desktop app's Code -> Recents list as it is scoped right now.
#
# Why needed: the Recents list is built from exactly ONE directory - the current
# account's currently-selected workspace (there is one workspace dir per
# organization you belong to). Sessions are stored as thin pointer files:
#   ~/Library/Application Support/Claude/claude-code-sessions/<accountUuid>/<workspaceUuid>/local_<uuid>.json
# each pointing at a CLI transcript in ~/.claude/projects/. Sessions therefore
# disappear from the list both when you log in with a different Claude id AND when
# you switch organization/workspace under the same id. This script copies the
# pointer files from every OTHER account+workspace dir into the target one.
#
# Non-destructive: source dirs are never modified; the current account's dir is
# backed up first. Reversible via the printed backup path.
#
# Usage:
#   restore.sh            # dry-run: show what would be copied
#   restore.sh --apply    # perform the copy (after backup)
#   restore.sh --apply --account <uuid>     # force target account (default = logged-in)
#   restore.sh --apply --workspace <uuid>   # force target workspace (default = newest)
#
# The default target workspace is the one holding the newest pointer file. When the
# current account has more than one workspace they are ALL listed - check that the
# marked one is the workspace the app is actually showing you, and pass --workspace
# if it is not.
#
# After --apply: FULLY QUIT Claude (Cmd+Q) and reopen — the list is cached in memory.
# Bash 3.2 compatible (macOS default). No associative arrays. Space-safe paths.

set -euo pipefail

SUP="$HOME/Library/Application Support/Claude"
STORE="$SUP/claude-code-sessions"
CFG="$SUP/config.json"

APPLY=0
FORCE_ACCT=""
FORCE_WS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1 ;;
    --account) shift; FORCE_ACCT="${1:-}" ;;
    --workspace) shift; FORCE_WS="${1:-}" ;;
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

# --- workspaces under the current account (one dir per organization) ---
# space-safe: only numeric mtimes are compared; paths stay quoted.
# BSD stat (macOS) speaks -f '%m'; GNU stat speaks -c '%Y' and would happily answer
# -f with filesystem info, so validate the result instead of trusting the exit code.
mtime_of() {
  local t
  t="$(stat -f '%m' "$1" 2>/dev/null)"
  case "$t" in ''|*[!0-9]*) t="$(stat -c '%Y' "$1" 2>/dev/null)" ;; esac
  case "$t" in ''|*[!0-9]*) t=0 ;; esac
  printf '%s' "$t"
}
fmt_mtime() { date -r "$1" '+%Y-%m-%d %H:%M' 2>/dev/null || date -d "@$1" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "$1"; }

WS_LIST="$(mktemp)"       # "<newest mtime>\t<pointer count>\t<path>", newest first
TARGET_LIST="$(mktemp)"   # basenames already in target
SEEN_LIST="$(mktemp)"     # basenames queued this run
SRC_LIST="$(mktemp)"      # full source paths to copy
trap 'rm -f "$WS_LIST" "$TARGET_LIST" "$SEEN_LIST" "$SRC_LIST"' EXIT

while IFS= read -r ws; do
  [ -d "$ws" ] || continue
  # newest local_*.json mtime in this workspace (0 if none) + how many there are
  m=0; c=0
  while IFS= read -r pf; do
    [ -f "$pf" ] || continue
    c=$((c+1))
    t="$(mtime_of "$pf")"
    if [ "$t" -gt "$m" ]; then m="$t"; fi
  done < <(find "$ws" -maxdepth 1 -name 'local_*.json' 2>/dev/null)
  printf '%s\t%s\t%s\n' "$m" "$c" "$ws" >> "$WS_LIST"
done < <(find "$STORE/$CUR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)

[ -s "$WS_LIST" ] || { echo "ERROR: current account has no workspace dir."; echo "Open the desktop app -> Code tab once, then rerun."; exit 1; }
sort -rn -o "$WS_LIST" "$WS_LIST"

# --- pick the target workspace ---
TARGET_WS=""
if [ -n "$FORCE_WS" ]; then
  while IFS="$(printf '\t')" read -r m c ws; do
    if [ "$(basename "$ws")" = "$FORCE_WS" ]; then TARGET_WS="$ws"; fi
  done < "$WS_LIST"
  if [ -z "$TARGET_WS" ]; then
    echo "ERROR: workspace '$FORCE_WS' not found under account '$CUR'."
    echo "Known workspaces:"
    while IFS="$(printf '\t')" read -r m c ws; do echo "  $(basename "$ws")"; done < "$WS_LIST"
    exit 1
  fi
else
  # Default: the workspace holding the newest pointer file. Opening or focusing a
  # session rewrites its pointer, so this is normally the workspace the app shows.
  TARGET_WS="$(head -n 1 "$WS_LIST" | cut -f3-)"
fi

echo "Current account : $CUR"
echo "Target workspace: $(basename "$TARGET_WS")"
echo "Store           : $STORE"
echo

# --- list every workspace of this account so a wrong pick is obvious ---
echo "Workspaces under this account (one per organization):"
ws_count=0
while IFS="$(printf '\t')" read -r m c ws; do
  ws_count=$((ws_count+1))
  if [ "$ws" = "$TARGET_WS" ]; then mark="->"; else mark="  "; fi
  if [ "$m" -gt 0 ]; then when="newest $(fmt_mtime "$m")"; else when="(no sessions)"; fi
  printf '  %s %s  %4s session(s)  %s\n' "$mark" "$(basename "$ws")" "$c" "$when"
done < "$WS_LIST"
if [ "$ws_count" -gt 1 ]; then
  echo
  echo "If '->' is not the workspace the app is showing you, rerun with --workspace <uuid>."
fi
echo

# --- collect source pointers from every OTHER workspace, dedup by basename ---
# "Other" = every <account>/<workspace> dir except the target one, INCLUDING other
# workspaces of the current account: switching organization hides sessions exactly
# the way switching account does.

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
done < <(find "$STORE" -mindepth 3 -maxdepth 3 -name 'local_*.json' -not -path "$TARGET_WS/*" 2>/dev/null)

echo "Sessions in other workspaces : $total_src"
echo "Already present in target    : $skip_count"
echo "New sessions to restore      : $copy_count"

if [ "$APPLY" -ne 1 ]; then
  echo
  echo "DRY-RUN. Re-run with --apply to copy the $copy_count new session(s) into the target workspace."
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
