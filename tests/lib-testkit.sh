#!/usr/bin/env bash
# lib-testkit.sh — the ONE way a test may obtain a kit copy it is allowed to destroy.
#
# Why this is a fail-closed guard and not a convenience wrapper:
#
# On 2026-09-03 this kit's own `.git` was deleted by its own test suite, and the suite
# printed ALL SUITES PASS while doing it. The mechanism:
#
#   1. the tests were invoked as `cd ~/claude-kit && bash tests/run-all.sh`, and
#      `~/claude-kit` is a SYMLINK to the real checkout;
#   2. `pwd` returns the LOGICAL path, so `SRC` came out as `/Users/me/claude-kit`
#      — a symlink, not a directory;
#   3. BSD `cp -R <symlink> <dest>` copies the symlink AS a symlink, so `$KIT` was a
#      second name for the real checkout, and `cp` exited 0;
#   4. the next line, `rm -rf "$KIT/.git"`, therefore deleted the REAL repository.
#      `rm -f "$KIT/kit.conf"` deleted the real config, and `"$KIT/install.sh"` then
#      recreated it — which is how the timestamps pinned the cause.
#
# Every assertion below is the negation of one step of that chain. They run BEFORE the
# caller is allowed to delete anything, and they exit nonzero rather than warn: a test
# that cannot get an independent copy must not proceed to the destructive part.
#
# `pwd -P` in the callers closes step 2; this closes steps 1, 3 and 4 as well, so the
# suite stays safe even if a future caller reintroduces a logical path.

# copy_kit_for_test <src> <dest>
#   Leaves <dest> as an independent, writable directory whose contents match <src>.
copy_kit_for_test() {
  local src="$1" dest="$2" rsrc rdest
  [ -n "$src" ] && [ -n "$dest" ] || { echo "FATAL: copy_kit_for_test needs <src> <dest>" >&2; exit 3; }
  [ -d "$src" ] || { echo "FATAL: copy_kit_for_test: source is not a directory: $src" >&2; exit 3; }
  [ -e "$src/install.sh" ] || { echo "FATAL: copy_kit_for_test: source is not a kit: $src" >&2; exit 3; }
  [ ! -e "$dest" ] || { echo "FATAL: copy_kit_for_test: destination exists: $dest" >&2; exit 3; }

  # mkdir first, then copy the CONTENTS in: this cannot produce a symlinked dest even
  # if <src> is itself reached through one.
  mkdir -p "$dest" || { echo "FATAL: copy_kit_for_test: cannot create $dest" >&2; exit 3; }
  cp -R "$src/." "$dest/" || { echo "FATAL: copy_kit_for_test: copy failed" >&2; exit 3; }

  [ ! -L "$dest" ] || { echo "FATAL: copy_kit_for_test: destination is a symlink: $dest" >&2; exit 3; }
  [ -d "$dest" ]   || { echo "FATAL: copy_kit_for_test: destination is not a directory" >&2; exit 3; }
  [ -e "$dest/install.sh" ] || { echo "FATAL: copy_kit_for_test: copy is empty" >&2; exit 3; }

  rsrc="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$src")"
  rdest="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$dest")"
  [ "$rsrc" != "$rdest" ] || {
    echo "FATAL: copy_kit_for_test: copy resolves to the SOURCE ($rdest) — refusing to continue" >&2
    exit 3
  }
}
