#!/usr/bin/env bash
# test-fresh-machine.sh — the reason this kit exists: it must come back intact on a
# new machine or in a new workspace. Simulates that literally — a fresh HOME, a clone
# at a path that is NOT this checkout, install.sh, then a project that carries only its
# manifest across.
#
# The assertion that matters most: nothing may bake in the clone's absolute path.
# Every link goes through the ~/claude-kit alias, so relocating the checkout (a new
# workspace layout) does not dangle every project's rules.
set -euo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
fails=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*"; fails=1; }
. "$(dirname "${BASH_SOURCE[0]}")/lib-testkit.sh"

export HOME="$TMP/home"; mkdir -p "$HOME"
export PATH="$HOME/.local/bin:$PATH"

# 1. clone to a path deliberately different from this checkout, and bootstrap
CLONE="$TMP/somewhere/else/claude-kit"
mkdir -p "$(dirname "$CLONE")"
git clone -q "$KIT" "$CLONE" 2>/dev/null || copy_kit_for_test "$KIT" "$CLONE"
"$CLONE/install.sh" >/dev/null || fail "install.sh failed on a fresh HOME"

# 2. every global asset resolves, and resolves INTO THE CLONE rather than the original
resolve() { python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$1"; }
for f in "$CLONE"/rules/global/*.md; do
  n="$(basename "$f")"
  [ -e "$HOME/.claude/rules/$n" ] || fail "global rule $n missing after fresh install"
  [ "$(resolve "$HOME/.claude/rules/$n")" = "$(resolve "$f")" ] || fail "global rule $n resolves outside the clone"
done
for f in "$CLONE"/agents/*.md; do
  n="$(basename "$f")"
  [ -e "$HOME/.claude/agents/$n" ] || fail "agent $n missing after fresh install"
done
for d in "$CLONE"/skills/*/; do
  n="$(basename "$d")"
  [ -e "$HOME/.claude/skills/$n" ] || fail "skill $n missing after fresh install"
done
[ "$(resolve "$HOME/claude-kit")" = "$(resolve "$CLONE")" ] || fail "~/claude-kit alias does not point at the clone"

# 3. the machine is healthy by its own account
"$HOME/.local/bin/kit" doctor >/dev/null 2>&1 || fail "kit doctor reports failures on a fresh machine"

# 4. a project carries only its manifest across; links are rebuilt locally
PROJ="$TMP/proj"; mkdir -p "$PROJ"
(cd "$PROJ" && kit add remote-compute >/dev/null) || fail "kit add failed on a fresh machine"
link="$PROJ/.claude/rules/kit/remote-compute.md"
[ -e "$link" ] || fail "opt-in link missing"
case "$(readlink "$link")" in
  "$HOME/claude-kit"/*) : ;;
  *) fail "opt-in link bakes in a path other than the ~/claude-kit alias: $(readlink "$link")" ;;
esac
# ⭐ the portability invariant: no link may hardcode the checkout location
grep -q "$CLONE" <<<"$(readlink "$link")" && fail "opt-in link hardcodes the clone path — would dangle elsewhere"

# 5. "another machine": the manifest travelled in git, the generated links did not
rm -rf "$PROJ/.claude/rules"
(cd "$PROJ" && kit sync >/dev/null) || fail "kit sync failed"
[ -e "$link" ] || fail "kit sync did not restore the link from the manifest"

# 6. "new workspace": relocate the checkout, re-run install.sh, everything still resolves
MOVED="$TMP/new-workspace/claude-kit"
mkdir -p "$(dirname "$MOVED")"
mv "$CLONE" "$MOVED"
rm -f "$HOME/claude-kit"          # the alias is machine-local state, not repo content
"$MOVED/install.sh" >/dev/null || fail "install.sh failed after relocating the checkout"
[ "$(resolve "$HOME/claude-kit")" = "$(resolve "$MOVED")" ] || fail "alias not re-pointed after a move"
[ -e "$link" ] || fail "project opt-in link broke after the checkout moved"
[ -e "$HOME/.claude/rules/git-and-style.md" ] || fail "global rule broke after the checkout moved"
"$HOME/.local/bin/kit" doctor >/dev/null 2>&1 || fail "kit doctor fails after relocating the checkout"

[ "$fails" -eq 0 ] && echo "fresh-machine: ALL PASS" || echo "fresh-machine: FAILURES"
exit "$fails"
