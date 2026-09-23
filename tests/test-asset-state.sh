#!/usr/bin/env bash
# test-asset-state.sh — declared vs installed, all four cells, both hosts.
#
# Why: `kit status` and `kit doctor` used to walk skills/, rules/global/ and agents/
# and assume every asset must be present. That produced two errors pointing in
# OPPOSITE directions:
#
#   `kit config off report-dashboard` unlinks correctly ⇒ doctor called the CORRECT
#   state a FAILURE;
#   `kit config on cross-ai-review` (an OPT-IN rule made machine-wide) was never
#   enumerated by the global-rule loop ⇒ a MISSING link reported GREEN.
#
# So the matrix is the test, not one happy path:
#
#   default-on  + linked            → on-ok        doctor green
#   default-on  + absent            → on-missing   doctor RED
#   configured-off + absent         → off-ok       doctor green   (the switch worked)
#   configured-off + our link left  → off-stale    doctor RED     (the switch did not)
#   configured-off + foreign entry  → off-foreign  doctor warn, and we must NOT delete it
#   default-off configured-on + linked/absent → on-ok / on-missing
#
# Same vocabulary on both hosts: one state model, two adapters.
set -euo pipefail
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
. "$(dirname "${BASH_SOURCE[0]}")/lib-testkit.sh"
fails=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*"; fails=1; }

copy_kit_for_test "$SRC" "$TMP/kit"
KIT="$TMP/kit"
export HOME="$TMP/home"
mkdir -p "$HOME"

verdict() { KIT_ROOT="$KIT" bash -c '. "$1/lib/assets.sh"; asset_verdict "$2" "$3" "$4"' _ "$KIT" "$1" "$2" "$3"; }

"$KIT/install.sh" >/dev/null 2>&1 || fail "install failed"

# ── cell 1: default-on, linked ───────────────────────────────────────────────
[ "$(verdict claude skill report-dashboard)" = on-ok ] || fail "cell1 claude: $(verdict claude skill report-dashboard)"
[ "$(verdict claude rule work-discipline)" = on-ok ]   || fail "cell1 rule: $(verdict claude rule work-discipline)"
[ "$(verdict codex agent executor)" = on-ok ]          || fail "cell1 codex: $(verdict codex agent executor)"
# a rule that is only injected on Codex has no destination there — n/a, not a failure
[ "$(verdict codex rule work-discipline)" = n/a ]      || fail "codex rules must be n/a (injected, not linked)"
# a skill deliberately not shipped to Codex is also n/a
[ "$(verdict codex skill memory-audit)" = n/a ]        || fail "memory-audit must be n/a on Codex"

# ── cell 2: default-on but the link is gone ──────────────────────────────────
rm -f "$HOME/.claude/skills/report-dashboard"
[ "$(verdict claude skill report-dashboard)" = on-missing ] || fail "cell2: $(verdict claude skill report-dashboard)"
out="$("$KIT/bin/kit" doctor claude 2>&1 || true)"
grep -q "skill report-dashboard is ON but NOT installed" <<<"$out" || fail "doctor did not flag an on-but-missing asset"
grep -qE 'doctor \[claude\]: .* [1-9][0-9]* fail' <<<"$out" || fail "doctor did not FAIL on an on-but-missing asset"

# ── cell 3: configured off, correctly unlinked ───────────────────────────────
"$KIT/bin/kit" config off report-dashboard >/dev/null 2>&1 || fail "kit config off failed"
[ ! -e "$HOME/.claude/skills/report-dashboard" ] || fail "config off left the Claude link behind"
[ ! -e "$HOME/.agents/skills/report-dashboard" ] || fail "config off left the Codex link behind"
[ "$(verdict claude skill report-dashboard)" = off-ok ] || fail "cell3 claude: $(verdict claude skill report-dashboard)"
[ "$(verdict codex skill report-dashboard)" = off-ok ]  || fail "cell3 codex: $(verdict codex skill report-dashboard)"
out="$("$KIT/bin/kit" doctor 2>&1 || true)"
grep -q "skill report-dashboard off and removed" <<<"$out" || fail "doctor did not report a correctly-off asset as OK"
grep -qE 'doctor \[claude\]: .* 0 fail' <<<"$out" || fail "doctor FAILED on a correctly-off asset (the old bug)"
grep -qE 'doctor \[codex\]: .* 0 fail' <<<"$out"  || fail "codex doctor FAILED on a correctly-off asset"

# ── cell 4: configured off, but our link survives ────────────────────────────
ln -sfn "$KIT/skills/report-dashboard" "$HOME/.claude/skills/report-dashboard"
[ "$(verdict claude skill report-dashboard)" = off-stale ] || fail "cell4: $(verdict claude skill report-dashboard)"
out="$("$KIT/bin/kit" doctor claude 2>&1 || true)"
grep -q "is OFF but its installation survives" <<<"$out" || fail "doctor did not flag a stale owned link"
grep -qE 'doctor \[claude\]: .* [1-9][0-9]* fail' <<<"$out" || fail "a stale owned link must be a FAILURE, not a warning"

# ── cell 5: configured off, and something that is NOT ours sits there ────────
rm -f "$HOME/.claude/skills/report-dashboard"
mkdir -p "$HOME/.claude/skills/report-dashboard"
printf 'mine\n' > "$HOME/.claude/skills/report-dashboard/SKILL.md"
[ "$(verdict claude skill report-dashboard)" = off-foreign ] || fail "cell5: $(verdict claude skill report-dashboard)"
out="$("$KIT/bin/kit" doctor claude 2>&1 || true)"
grep -q "a non-kit entry occupies" <<<"$out" || fail "doctor did not warn about a foreign entry"
grep -qE 'doctor \[claude\]: .* 0 fail' <<<"$out" || fail "a foreign entry must warn, not fail"
"$KIT/install.sh" >/dev/null 2>&1 || true
[ -f "$HOME/.claude/skills/report-dashboard/SKILL.md" ] || fail "install.sh DELETED a user's own file at an off asset's path"
rm -rf "$HOME/.claude/skills/report-dashboard"
"$KIT/bin/kit" config on report-dashboard >/dev/null 2>&1

# ── cell 6: default-OFF made machine-wide ON ─────────────────────────────────
# This is the one the old doctor could not see at all: cross-ai-review lives in
# rules/optin, and the global-rule loop only ever walked rules/global.
[ "$(verdict claude rule cross-ai-review)" = off-ok ] || fail "cross-ai-review should start off: $(verdict claude rule cross-ai-review)"
"$KIT/bin/kit" config on cross-ai-review >/dev/null 2>&1 || fail "kit config on cross-ai-review failed"
[ "$(verdict claude rule cross-ai-review)" = on-ok ] || fail "cell6 on: $(verdict claude rule cross-ai-review)"
out="$("$KIT/bin/kit" doctor claude 2>&1 || true)"
grep -q "rule cross-ai-review installed" <<<"$out" || fail "doctor does not enumerate an opt-in rule turned on machine-wide"
rm -f "$HOME/.claude/rules/cross-ai-review.md"
[ "$(verdict claude rule cross-ai-review)" = on-missing ] || fail "cell6 missing: $(verdict claude rule cross-ai-review)"
out="$("$KIT/bin/kit" doctor claude 2>&1 || true)"
grep -qE 'doctor \[claude\]: .* [1-9][0-9]* fail' <<<"$out" \
  || fail "⛔ THE OLD BUG: an on-machine-wide opt-in rule is missing and doctor still reported green"

# ── cells 7-10: hooks. A hook is a REGISTRATION, not a symlink, so it sat outside
#    the state model entirely and doctor counted it with bespoke logic. Same verdict
#    vocabulary now, but asserted per EVENT: a count called codex-rules.py's
#    deliberate SessionStart+SubagentStart pair "duplicated", and a count cannot see
#    a hook bound to the WRONG event at all.
hverdict() { KIT_ROOT="$KIT" bash -c '. "$1/lib/assets.sh"; hook_verdict "$2" "$3"' _ "$KIT" "$1" "$2"; }

"$KIT/install.sh" >/dev/null 2>&1 || true
[ "$(hverdict claude git-guard)" = on-ok ]            || fail "hook cell1: $(hverdict claude git-guard)"
[ "$(hverdict codex instructions-loaded)" = on-ok ]   || fail "the two-event Codex injector must be on-ok, got $(hverdict codex instructions-loaded)"
[ "$(hverdict codex wrap-up-trigger)" = n/a ]         || fail "a Claude-only hook must be n/a on Codex"

# wrong event: registered, but not where it fires
python3 - "$HOME/.claude/settings.json" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
groups = d["hooks"].pop("PreToolUse")
d["hooks"].setdefault("PostToolUse", []).extend(groups)   # same command, wrong event
json.dump(d, open(sys.argv[1], "w", encoding="utf-8"), indent=2, ensure_ascii=False)
PYEOF
[ "$(hverdict claude git-guard)" = on-wrong-events ] \
  || fail "a hook moved to the wrong event must not read as installed: $(hverdict claude git-guard)"
out="$("$KIT/bin/kit" doctor claude 2>&1 || true)"
grep -qE 'doctor \[claude\]: .* [1-9][0-9]* fail' <<<"$out" || fail "a wrong-event hook must FAIL doctor"
"$KIT/install.sh" >/dev/null 2>&1 || true
[ "$(hverdict claude git-guard)" = on-ok ] || fail "install.sh did not restore the hook registration"

# config off must actually deregister; a surviving registration is RED
"$KIT/bin/kit" config off gotchas-contract >/dev/null 2>&1 || fail "kit config off <hook> failed"
[ "$(hverdict claude gotchas-contract)" = off-ok ] || fail "hook cell3: $(hverdict claude gotchas-contract)"
python3 - "$HOME/.claude/settings.json" "$KIT" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
d["hooks"].setdefault("PostToolUse", []).append(
    {"matcher": "Write", "hooks": [{"type": "command",
     "command": sys.argv[2] + "/hooks/gotchas-contract.py"}]})
json.dump(d, open(sys.argv[1], "w", encoding="utf-8"), indent=2, ensure_ascii=False)
PYEOF
[ "$(hverdict claude gotchas-contract)" = off-stale ] || fail "hook cell4: $(hverdict claude gotchas-contract)"
out="$("$KIT/bin/kit" doctor claude 2>&1 || true)"
grep -qE 'doctor \[claude\]: .* [1-9][0-9]* fail' <<<"$out" \
  || fail "⛔ a hook switched OFF whose registration survives must be RED"
"$KIT/bin/kit" config on gotchas-contract >/dev/null 2>&1
"$KIT/install.sh" >/dev/null 2>&1 || true

# unreadable settings is "state unknown", ⛔ not "nothing is registered"
cp "$HOME/.claude/settings.json" "$TMP/settings.bak"
printf '{ this is not json\n' > "$HOME/.claude/settings.json"
[ "$(hverdict claude git-guard)" = settings-unreadable ] \
  || fail "unreadable settings must not read as absent: $(hverdict claude git-guard)"
cp "$TMP/settings.bak" "$HOME/.claude/settings.json"

# ── every asset the registry declares must be reachable by the state model ───
# export, not a `VAR=x .` prefix: assets.sh runs under `set -u`, so the prefix form
# left KIT_ROOT unbound, asset_registry printed nothing, and this sweep silently
# iterated ZERO assets while the suite still printed ALL PASS. Empty is not green.
export KIT_ROOT="$KIT"
. "$KIT/lib/assets.sh"
swept=0
while IFS="$(printf '\t')" read -r kind name _; do
  [ "$kind" = hook ] && continue
  swept=$((swept + 1))
  for host in claude codex; do
    v="$(verdict "$host" "$kind" "$name")"
    case "$v" in
      on-ok|on-missing|off-ok|off-stale|off-foreign|n/a) : ;;
      *) fail "asset_verdict $host $kind $name returned an unknown verdict: '$v'" ;;
    esac
  done
done <<EOF
$(asset_registry)
EOF
# Prove the sweep reached its assertions — as a RELATIONSHIP, not a magic number.
# `-ge 10` was a frozen snapshot of today's inventory; this stays correct when the
# kit grows or shrinks, and still catches the empty-loop false pass it was added for.
want=$(asset_registry | awk -F'\t' '$1 != "hook"' | wc -l | tr -d ' ')
[ "$swept" -eq "$want" ] \
  || fail "the sweep saw $swept of $want non-hook assets — it did not cover the registry"
echo "  (swept $swept assets × 2 hosts through the state model)"

[ "$fails" -eq 0 ] && echo "asset-state: ALL PASS" || echo "asset-state: FAILURES"
exit "$fails"
