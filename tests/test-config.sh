#!/usr/bin/env bash
# test-config.sh — the switch layer: kit.conf decides what install.sh links, and
# flipping a switch must actually take effect in BOTH directions. A switch that only
# ever adds is not a switch.
#
# Runs against a COPY of the kit so the real kit.conf is never touched.
set -euo pipefail
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
fails=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*"; fails=1; }
. "$(dirname "${BASH_SOURCE[0]}")/lib-testkit.sh"

export HOME="$TMP/home"; mkdir -p "$HOME"
KIT="$TMP/kit"
copy_kit_for_test "$SRC" "$KIT"
rm -f "$KIT/kit.conf"            # start from pure defaults
rm -rf "$KIT/.git"
"$KIT/install.sh" >/dev/null

hook_count() {  # <needle> → how many times it is registered anywhere in settings.json
  python3 - "$HOME/.claude/settings.json" "$1" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    print(0); raise SystemExit
print(sum(1 for ms in d.get("hooks", {}).values() for m in ms
          for h in m.get("hooks", []) if sys.argv[2] in h.get("command", "")))
PY
}
codex_hook_count() {
  python3 - "$HOME/.codex/hooks.json" "$1" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    print(0); raise SystemExit
print(sum(1 for ms in d.get("hooks", {}).values() for m in ms
          for h in m.get("hooks", []) if sys.argv[2] in h.get("command", "")))
PY
}

# 1. defaults — global rules / skills / agents / hooks on, opt-in rules off
[ -e "$HOME/.claude/rules/work-discipline.md" ]  || fail "default: global rule not linked"
[ -e "$HOME/.claude/skills/cross-ai" ]           || fail "default: skill not linked"
[ -e "$HOME/.claude/agents/executor.md" ]        || fail "default: agent not linked"
[ -e "$HOME/.claude/rules/cross-ai-review.md" ]  && fail "default: opt-in rule linked globally"
[ "$(hook_count git-guard)" = 1 ]                || fail "default: git-guard not registered exactly once"
[ -e "$HOME/.agents/skills/report-dashboard" ]  || fail "default: Codex shared skill not linked"
[ "$(codex_hook_count codex-rules.py)" = 2 ]     || fail "default: Codex rule hooks not registered twice (root + subagent)"

# 2. an opt-in rule can be switched on machine-wide
"$KIT/bin/kit" config on cross-ai-review >/dev/null
[ -e "$HOME/.claude/rules/cross-ai-review.md" ] || fail "config on: opt-in rule not linked"

# 3. ⭐ off must UNLINK, not just stop linking
"$KIT/bin/kit" config off report-dashboard >/dev/null
[ -e "$HOME/.claude/skills/report-dashboard" ] && fail "config off: skill link survived"
[ -e "$HOME/.agents/skills/report-dashboard" ] && fail "config off: Codex skill link survived"
"$KIT/bin/kit" config on report-dashboard >/dev/null
[ -e "$HOME/.claude/skills/report-dashboard" ] || fail "config on: skill not restored"
[ -e "$HOME/.agents/skills/report-dashboard" ] || fail "config on: Codex skill not restored"

# 4. hooks deregister and re-register cleanly, without duplicating
"$KIT/bin/kit" config off instructions-loaded >/dev/null
[ "$(hook_count instructions-loaded)" = 0 ] || fail "config off: hook still registered"
[ "$(codex_hook_count codex-rules.py)" = 0 ] || fail "config off: Codex rule hooks still registered"
"$KIT/bin/kit" config on instructions-loaded >/dev/null
[ "$(hook_count instructions-loaded)" = 1 ] || fail "config on: hook not restored exactly once"
[ "$(codex_hook_count codex-rules.py)" = 2 ] || fail "config on: Codex rule hooks not restored"
[ "$(hook_count git-guard)" = 1 ] || fail "toggling one hook disturbed the other"

# 5. kit.conf holds EXCEPTIONS only — setting a value back to its default drops the line.
# If it grew into a full inventory, a newly added asset would be absent and read as off.
"$KIT/bin/kit" config off cross-ai-review >/dev/null
grep -q '^\(on\|off\) ' "$KIT/kit.conf" && fail "kit.conf kept a line that matches the default"

# 6. we only remove links we own; a hand-made file at that path is not ours to delete
"$KIT/bin/kit" config off memory-audit >/dev/null
echo "my own skill" > "$HOME/.claude/skills/memory-audit"
"$KIT/bin/kit" config off memory-audit >/dev/null
[ -f "$HOME/.claude/skills/memory-audit" ] || fail "install.sh deleted a user's own file"
rm -f "$HOME/.claude/skills/memory-audit"
"$KIT/bin/kit" config on memory-audit >/dev/null

# 7. the table lists every kind, so the switches are discoverable at all
out="$("$KIT/bin/kit" config)"
for kind in rule skill agent hook; do
  grep -q "^$kind " <<<"$out" || fail "config show is missing the $kind rows"
done

[ "$fails" -eq 0 ] && echo "config: ALL PASS" || echo "config: FAILURES"
exit "$fails"
