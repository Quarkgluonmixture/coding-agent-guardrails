#!/usr/bin/env bash
# test-install.sh — install.sh is repeatable and non-destructive, in a sandboxed HOME:
# links created, hook registered exactly once across two runs, pre-existing
# settings.json keys preserved, output valid JSON.
set -euo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
fails=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME/.claude"

# pre-existing settings must survive the merge
printf '{"model":"keep-me","permissions":{"defaultMode":"auto"}}\n' > "$HOME/.claude/settings.json"

# capture stderr too: a missing shell helper printed "command not found" here for a
# whole release while every assertion below still passed
err="$("$KIT/install.sh" 2>&1 >/dev/null)"
[ -z "$err" ] || { echo "FAIL: install.sh wrote to stderr: $err"; fails=1; }
"$KIT/install.sh" >/dev/null 2>&1   # idempotency: second run must not duplicate anything

[ -L "$HOME/.local/bin/kit" ] || { echo "FAIL: kit not linked"; fails=1; }
for d in "$KIT"/skills/*/; do
  n="$(basename "$d")"
  [ -L "$HOME/.claude/skills/$n" ] || { echo "FAIL: skill $n not linked"; fails=1; }
done
# global rules: the only channel that also reaches custom subagents
for f in "$KIT"/rules/global/*.md; do
  n="$(basename "$f")"
  [ -L "$HOME/.claude/rules/$n" ] || { echo "FAIL: global rule $n not linked"; fails=1; }
  [ -e "$HOME/.claude/rules/$n" ] || { echo "FAIL: global rule $n dangling"; fails=1; }
done
for f in "$KIT"/agents/*.md; do
  n="$(basename "$f")"
  [ -L "$HOME/.claude/agents/$n" ] || { echo "FAIL: agent $n not linked"; fails=1; }
  [ -e "$HOME/.claude/agents/$n" ] || { echo "FAIL: agent $n dangling"; fails=1; }
done
# opt-in rules must NOT be installed globally — that's the whole point of the tier split
for f in "$KIT"/rules/optin/*.md; do
  n="$(basename "$f")"
  [ -e "$HOME/.claude/rules/$n" ] && { echo "FAIL: opt-in rule $n leaked into global rules"; fails=1; }
done
# a real file in the way must be backed up OUTSIDE the live dir, not left as a duplicate
printf 'stale\n' > "$HOME/.claude/rules/decoy.md"
"$KIT/install.sh" >/dev/null
[ -f "$HOME/.claude/rules/decoy.md" ] || { echo "FAIL: install.sh clobbered an unrelated user rule"; fails=1; }
if [ "$KIT" != "$HOME/claude-kit" ]; then
  [ -L "$HOME/claude-kit" ] || { echo "FAIL: ~/claude-kit alias missing"; fails=1; }
fi

python3 - "$HOME/.claude/settings.json" <<'PY' || fails=1
import json, sys
d = json.load(open(sys.argv[1]))          # must be valid JSON
assert d.get("model") == "keep-me", "pre-existing key clobbered"
n = sum(1 for m in d.get("hooks", {}).get("PreToolUse", [])
        for h in m.get("hooks", []) if "git-guard.sh" in h.get("command", ""))
assert n == 1, f"git-guard registered {n} times (want exactly 1)"
il = d.get("hooks", {}).get("InstructionsLoaded", [])
# the matcher filters on load reason; session_start is the one that must be covered
assert any("session_start" in m.get("matcher", "") for m in il), "InstructionsLoaded matcher misses session_start"
print("install settings merge: ok")
PY

# Which event each hook belongs on is answered by lib/assets.sh (hook_events), and
# hook_verdict already means "registered on exactly those events, exactly once". So
# assert THAT, rather than restating four event names here — the restatement is what
# just went stale when gotchas-contract moved to PostToolBatch.
export KIT_ROOT="$KIT"
. "$KIT/lib/assets.sh"
checked=0
for h in git-guard instructions-loaded wrap-up-trigger gotchas-contract; do
  v="$(hook_verdict claude "$h")"
  [ "$v" = "n/a" ] && continue
  checked=$((checked + 1))
  [ "$v" = "on-ok" ] || { echo "FAIL: hook $h after install: $v (want on-ok)"; fails=1; }
done
[ "$checked" -eq 4 ] || { echo "FAIL: only $checked of 4 Claude hooks were checked"; fails=1; }

"$HOME/.local/bin/kit" list >/dev/null || { echo "FAIL: linked kit not runnable"; fails=1; }

[ "$fails" -eq 0 ] && echo "install: ALL PASS" || echo "install: FAILURES"
exit "$fails"
