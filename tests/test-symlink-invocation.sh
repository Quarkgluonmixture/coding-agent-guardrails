#!/usr/bin/env bash
# test-symlink-invocation.sh — the suite must not destroy the checkout it is testing.
#
# 2026-09-03: it did. `cd ~/claude-kit && bash tests/run-all.sh` deleted this
# repository's own `.git` and printed ALL SUITES PASS. `~/claude-kit` is a symlink,
# `pwd` returns the logical path, BSD `cp -R <symlink> <dest>` copies the symlink
# itself, and `rm -rf "$KIT/.git"` then resolved to the real repository. Recovery was
# only possible because the remote happened to be at the same commit.
#
# So this file asserts the property, not the implementation: a kit reached THROUGH A
# SYMLINK must survive its own destructive tests. Case 3 is the one that reproduces
# the original failure end to end; cases 1-2 pin the mechanism and case 4 keeps a
# future test from bypassing the guard.
set -uo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
fails=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*"; fails=1; }
. "$(dirname "${BASH_SOURCE[0]}")/lib-testkit.sh"

# An expendable stand-in for the real checkout, plus the symlink that caused the bug.
ORIGIN="$TMP/origin"
mkdir -p "$ORIGIN"
cp -R "$KIT/." "$ORIGIN/"
rm -rf "$ORIGIN/.git"
mkdir -p "$ORIGIN/.git"; printf 'do-not-delete\n' > "$ORIGIN/.git/SENTINEL"
printf 'sentinel kit.conf\n' > "$ORIGIN/kit.conf"
LINK="$TMP/link"; ln -s "$ORIGIN" "$LINK"

origin_intact() {  # <label>
  [ -f "$ORIGIN/.git/SENTINEL" ] || fail "$1: the origin's .git was deleted"
  grep -qx 'sentinel kit.conf' "$ORIGIN/kit.conf" 2>/dev/null \
    || fail "$1: the origin's kit.conf was overwritten"
}

# 1. the guard, handed a symlink, still yields an independent directory
copy_kit_for_test "$LINK" "$TMP/c1" || fail "guard rejected a symlinked source outright"
[ ! -L "$TMP/c1" ] || fail "guard produced a symlinked copy"
[ -f "$TMP/c1/.git/SENTINEL" ] || fail "guard did not copy contents"
rm -rf "$TMP/c1/.git"
origin_intact "case 1"

# 2. the guard fails CLOSED rather than warning — the caller must never reach its
#    own `rm -rf` on a copy that was not made.
( copy_kit_for_test "$TMP/nonexistent" "$TMP/c2" ) >/dev/null 2>&1
[ "$?" -ne 0 ] || fail "guard accepted a nonexistent source"
( copy_kit_for_test "$LINK" "$ORIGIN" ) >/dev/null 2>&1
[ "$?" -ne 0 ] || fail "guard accepted a destination that already exists"
origin_intact "case 2"

# 3. ⭐ the original failure, end to end: run the destructive suites THROUGH the
#    symlink. Their own pass/fail is not the assertion here (they get a sandboxed
#    HOME and may legitimately fail for unrelated reasons) — the assertion is that
#    the thing on the other side of the symlink is still there afterwards.
for t in test-codex.sh test-config.sh test-fresh-machine.sh; do
  ( cd "$LINK" && bash "tests/$t" ) >/dev/null 2>&1
  echo "    (via symlink) $t exited $?"
  origin_intact "case 3 / $t"
done

# 4. no test may reintroduce a raw copy: anything that deletes inside a kit copy has
#    to have obtained that copy through the guard.
for t in "$KIT"/tests/test-*.sh; do
  grep -qE 'rm -(rf|f) "\$(KIT|CLONE|SRC)' "$t" || continue
  grep -q 'copy_kit_for_test' "$t" \
    || fail "$(basename "$t") deletes inside a kit copy without copy_kit_for_test"
  grep -qE '^cp -R "\$(SRC|KIT)" "\$(KIT|CLONE)"' "$t" \
    && fail "$(basename "$t") copies a kit root with a raw cp -R"
done

[ "$fails" -eq 0 ] && echo "symlink-invocation: ALL PASS" || echo "symlink-invocation: FAILURES"
exit "$fails"
