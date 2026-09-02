#!/usr/bin/env bash
# Test harness for restore.sh — mirrors tests/test-restore.ps1.
#
# Builds a synthetic session store in a temp dir and runs restore.sh against it by
# overriding HOME (which roots both the store and the backup dir), so the real
# Claude data dir is never touched.
#
# Usage: bash tests/test-restore.sh
# Requires jq (same as restore.sh itself).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO_ROOT/restore.sh"
REAL_HOME="$HOME"

checks=0
failures=0

ok()   { checks=$((checks+1)); echo "  ok   $1"; }
fail() { checks=$((checks+1)); failures=$((failures+1)); echo "  FAIL $1"; }

assert_eq() { # expected actual label
  if [ "$1" = "$2" ]; then ok "$3 (= $2)"; else fail "$3 : expected $1, got $2"; fi
}
assert_match() { # pattern text label
  if printf '%s' "$2" | grep -Eq "$1"; then ok "$3"; else fail "$3 : /$1/ not found in output"; fi
}

ACCT_CUR="aaaaaaaa-0000-0000-0000-000000000001"
ACCT_OLD="bbbbbbbb-0000-0000-0000-000000000002"
ORG_TARGET="11111111-0000-0000-0000-00000000000a"
ORG_SIBLING="22222222-0000-0000-0000-00000000000b"
ORG_OLD="33333333-0000-0000-0000-00000000000c"

FIXTURE=""
new_fixture() {
  FIXTURE="$(mktemp -d)"
  local sup="$FIXTURE/Library/Application Support/Claude"
  local store="$sup/claude-code-sessions"
  mkdir -p "$sup"
  printf '{"lastKnownAccountUuid":"%s"}\n' "$ACCT_CUR" > "$sup/config.json"

  # <acct>|<org>|<names>|<minutes old>   (target org newest -> default pick)
  local rows="$ACCT_CUR|$ORG_TARGET|local_t1.json local_t2.json|1
$ACCT_CUR|$ORG_SIBLING|local_s1.json local_s2.json local_s3.json|30
$ACCT_OLD|$ORG_OLD|local_o1.json local_o2.json|90"

  local row acct org names age dir n
  while IFS='|' read -r acct org names age; do
    dir="$store/$acct/$org"
    mkdir -p "$dir"
    for n in $names; do
      printf '{"sessionId":"%s"}\n' "$n" > "$dir/$n"
      touch -d "$age minutes ago" "$dir/$n" 2>/dev/null || touch -A "-00${age}00" "$dir/$n" 2>/dev/null || true
    done
    # a non-pointer file the tool must ignore
    printf '{}\n' > "$dir/scheduled-tasks.json"
  done <<< "$rows"
}

count_pointers() { find "$1" -maxdepth 1 -name 'local_*.json' 2>/dev/null | wc -l | tr -d ' '; }

run_restore() { # extra args...
  HOME="$FIXTURE" bash "$SCRIPT" "$@" 2>&1
}

store_of() { echo "$FIXTURE/Library/Application Support/Claude/claude-code-sessions"; }

echo "restore.sh tests"
echo

echo "TEST 1: merges every other workspace, including sibling orgs of the current account"
new_fixture
STORE="$(store_of)"
TARGET_DIR="$STORE/$ACCT_CUR/$ORG_TARGET"
SIBLING_DIR="$STORE/$ACCT_CUR/$ORG_SIBLING"
OLD_DIR="$STORE/$ACCT_OLD/$ORG_OLD"

DRY="$(run_restore)"
assert_match "Target workspace: $ORG_TARGET" "$DRY" "dry-run picks the newest workspace as target"
assert_match "New sessions to restore +: 5" "$DRY" "dry-run counts 3 sibling-org + 2 other-account sessions"
assert_eq 2 "$(count_pointers "$TARGET_DIR")" "dry-run copies nothing"

run_restore --apply > /dev/null
assert_eq 7 "$(count_pointers "$TARGET_DIR")" "target holds its own 2 + 5 restored"
assert_eq 3 "$(count_pointers "$SIBLING_DIR")" "sibling org untouched"
assert_eq 2 "$(count_pointers "$OLD_DIR")" "other account untouched"
assert_eq 1 "$(ls "$TARGET_DIR" | grep -c '^scheduled-tasks.json$')" "no stray non-pointer copies"
if [ -d "$FIXTURE/.claude" ]; then ok "backup written under the overridden HOME"; else fail "backup written under the overridden HOME"; fi

echo
echo "TEST 2: re-running is idempotent"
AGAIN="$(run_restore)"
assert_match "New sessions to restore +: 0" "$AGAIN" "second dry-run finds nothing new"
rm -rf "$FIXTURE"

echo
echo "TEST 3: --workspace forces the target workspace"
new_fixture
STORE="$(store_of)"
run_restore --apply --workspace "$ORG_SIBLING" > /dev/null
assert_eq 7 "$(count_pointers "$STORE/$ACCT_CUR/$ORG_SIBLING")" "forced workspace holds its own 3 + 4 restored"
assert_eq 2 "$(count_pointers "$STORE/$ACCT_CUR/$ORG_TARGET")" "default target untouched when overridden"
rm -rf "$FIXTURE"

echo
echo "TEST 4: multiple workspaces are listed so the user can spot a wrong pick"
new_fixture
OUT="$(run_restore)"
assert_match "$ORG_SIBLING" "$OUT" "candidate workspaces are printed"
rm -rf "$FIXTURE"

export HOME="$REAL_HOME"
echo
if [ "$failures" -gt 0 ]; then
  echo "$failures/$checks checks FAILED"
  exit 1
fi
echo "all $checks checks passed"
