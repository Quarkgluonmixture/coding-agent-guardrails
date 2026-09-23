#!/usr/bin/env bash
# test-memory-link.sh — locks in the conflict semantics: same filename with
# DIFFERENT content on both sides must ABORT (no symlink, both sides untouched);
# the hazard is silently LOADING a stale memory, not losing bytes.
set -euo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
fails=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"

# Claude Code slugs the RESOLVED project path (its own transcript paths show /private/var
# on macOS, not /var), and so does `kit`. Slugging the unresolved string here would build
# the fixtures under a directory kit never looks at.
slug_of() { (cd "$1" && pwd -P) | sed 's#/#-#g'; }

# case 1 — clean migration: local memory exists, project side absent
P1="$TMP/p1"; mkdir -p "$P1"
M1="$HOME/.claude/projects/$(slug_of "$P1")/memory"
mkdir -p "$M1"; echo "v-new" > "$M1/a.md"
(cd "$P1" && "$KIT/bin/kit" memory-link >/dev/null)
[ -L "$M1" ] || { echo "FAIL(1): dest not a symlink"; fails=1; }
[ "$(cat "$P1/.claude-memory/a.md" 2>/dev/null)" = "v-new" ] || { echo "FAIL(1): content not migrated"; fails=1; }
[ "$(cat "$M1/a.md" 2>/dev/null)" = "v-new" ] || { echo "FAIL(1): not readable through link"; fails=1; }

# case 2 — CONFLICT: same file, different content → abort, no link, both untouched
P2="$TMP/p2"; mkdir -p "$P2/.claude-memory"
M2="$HOME/.claude/projects/$(slug_of "$P2")/memory"
mkdir -p "$M2"
echo "local-NEW" > "$M2/a.md"
echo "proj-OLD"  > "$P2/.claude-memory/a.md"
if (cd "$P2" && "$KIT/bin/kit" memory-link >/dev/null 2>&1); then
  echo "FAIL(2): conflict not detected (exit 0)"; fails=1
fi
[ ! -L "$M2" ] || { echo "FAIL(2): symlinked despite conflict"; fails=1; }
[ "$(cat "$M2/a.md")" = "local-NEW" ] || { echo "FAIL(2): local side modified"; fails=1; }
[ "$(cat "$P2/.claude-memory/a.md")" = "proj-OLD" ] || { echo "FAIL(2): project side modified"; fails=1; }

# case 3 — identical content on both sides is NOT a conflict
P3="$TMP/p3"; mkdir -p "$P3/.claude-memory"
M3="$HOME/.claude/projects/$(slug_of "$P3")/memory"
mkdir -p "$M3"
echo "same" > "$M3/a.md"; echo "same" > "$P3/.claude-memory/a.md"; echo "only-local" > "$M3/b.md"
(cd "$P3" && "$KIT/bin/kit" memory-link >/dev/null)
[ -L "$M3" ] || { echo "FAIL(3): identical files wrongly treated as conflict"; fails=1; }
[ "$(cat "$P3/.claude-memory/b.md" 2>/dev/null)" = "only-local" ] || { echo "FAIL(3): local-only file not migrated"; fails=1; }

# case 4 — re-run on an existing link is idempotent
(cd "$P1" && "$KIT/bin/kit" memory-link >/dev/null)
[ -L "$M1" ] || { echo "FAIL(4): re-run broke the link"; fails=1; }

# case 5 — ⭐ the slug follows the GIT REPO, not the directory you stand in.
# Claude Code keys auto memory by repository, so running from a subdirectory used to
# link a directory it never reads, and report success while doing it.
P5="$TMP/p5"; mkdir -p "$P5/deep/nested"
git -C "$P5" init -q 2>/dev/null || true
M5="$HOME/.claude/projects/$(slug_of "$P5")/memory"
mkdir -p "$M5"; echo "repo-level" > "$M5/a.md"
(cd "$P5/deep/nested" && "$KIT/bin/kit" memory-link >/dev/null)
[ -L "$M5" ] || { echo "FAIL(5): running from a subdirectory did not link the repo-level memory"; fails=1; }
[ -d "$P5/.claude-memory" ] || { echo "FAIL(5): .claude-memory not created at the repo root"; fails=1; }
[ -e "$P5/deep/nested/.claude-memory" ] && { echo "FAIL(5): created .claude-memory in the subdirectory"; fails=1; }
[ "$(cat "$P5/.claude-memory/a.md" 2>/dev/null)" = "repo-level" ] || { echo "FAIL(5): repo-level memory not migrated"; fails=1; }

# case 6 — a slug that no session ever used, while a look-alike exists, must NOT be
# linked silently: that is the failure mode where you believe memory is portable and it isn't.
P6="$TMP/lookalike-proj"; mkdir -p "$P6"
mkdir -p "$HOME/.claude/projects/some-other-path-lookalike-proj-extra/memory"
if (cd "$P6" && "$KIT/bin/kit" memory-link >/dev/null 2>&1); then
  echo "FAIL(6): linked a never-used slug despite a look-alike directory existing"; fails=1
fi
[ -L "$HOME/.claude/projects/$(slug_of "$P6")/memory" ] && { echo "FAIL(6): symlink created anyway"; fails=1; }

# case 7 — autoMemoryDirectory: probed 2026-08-07, a relative or $CLAUDE_PROJECT_DIR value is
# ignored SILENTLY (memory lands in the default dir while the session says it saved). Only an
# absolute / ~/ value takes effect. `kit` must call both cases out rather than let them pass.
P7="$TMP/p7"; mkdir -p "$P7/.claude"
printf '{"autoMemoryDirectory": "./.claude-memory"}\n' > "$P7/.claude/settings.json"
out="$(cd "$P7" && "$KIT/bin/kit" status)"
grep -q "被静默忽略" <<<"$out" || { echo "FAIL(7): status did not flag an ignored autoMemoryDirectory"; fails=1; }

# an effective one must instead block memory-link: two mechanisms for one thing
P8="$TMP/p8"; mkdir -p "$P8/.claude"
printf '{"autoMemoryDirectory": "%s/.claude-memory"}\n' "$(cd "$P8" && pwd -P)" > "$P8/.claude/settings.json"
if (cd "$P8" && "$KIT/bin/kit" memory-link >/dev/null 2>&1); then
  echo "FAIL(8): memory-link ran despite an effective autoMemoryDirectory"; fails=1
fi
out="$(cd "$P8" && "$KIT/bin/kit" status)"
grep -q "memory 已被重定向" <<<"$out" || { echo "FAIL(8): status did not report the active redirect"; fails=1; }

[ "$fails" -eq 0 ] && echo "memory-link: ALL PASS" || echo "memory-link: FAILURES"
exit "$fails"
