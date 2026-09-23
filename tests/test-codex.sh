#!/usr/bin/env bash
# test-codex.sh — Codex adapter: non-destructive install, host-specific assets,
# SessionStart rule injection + observation, guard semantics, and idempotency.
set -euo pipefail
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
fails=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*"; fails=1; }
. "$(dirname "${BASH_SOURCE[0]}")/lib-testkit.sh"

export HOME="$TMP/home"
mkdir -p "$HOME/.codex" "$HOME/.agents/skills/cross-ai"
printf '# keep this personal AGENTS file\n' > "$HOME/.codex/AGENTS.md"
printf 'old cross-ai\n' > "$HOME/.agents/skills/cross-ai/SKILL.md"
printf '{"description":"keep-me","hooks":{"Stop":[{"hooks":[{"type":"command","command":"true"}]}]}}\n' \
  > "$HOME/.codex/hooks.json"

KIT="$TMP/kit"
copy_kit_for_test "$SRC" "$KIT"
rm -rf "$KIT/.git"

# 0. A real ~/claude-kit collision aborts before any HOME mutation.
COLLISION_HOME="$TMP/collision-home"
mkdir -p "$COLLISION_HOME/claude-kit"
if HOME="$COLLISION_HOME" "$KIT/install.sh" --target codex >/dev/null 2>&1; then
  fail "real ~/claude-kit collision did not abort"
fi
[ ! -e "$COLLISION_HOME/.local/bin/kit" ] || fail "collision abort mutated ~/.local/bin/kit"
[ ! -e "$COLLISION_HOME/.codex/hooks.json" ] || fail "collision abort registered Codex hooks"

# An unrelated same-name symlink is recoverable: back it up before replacing it.
mkdir -p "$TMP/other-checkpoint"
ln -s "$TMP/other-checkpoint" "$HOME/.agents/skills/checkpoint"

# 1. Codex-only install must not touch Claude settings or overwrite AGENTS.md.
"$KIT/install.sh" --target codex >/dev/null
"$KIT/install.sh" --target codex >/dev/null
[ "$(cat "$HOME/.codex/AGENTS.md")" = "# keep this personal AGENTS file" ] || fail "Codex AGENTS.md was modified"
[ ! -e "$HOME/.claude/settings.json" ] || fail "--target codex wrote Claude settings"

# 2. Supported shared assets use Codex discovery paths; Claude-only assets stay out.
for name in checkpoint refine-propose report-dashboard cross-ai; do
  [ -L "$HOME/.agents/skills/$name" ] || fail "Codex skill $name not linked"
done
[ -e "$HOME/.agents/skills/memory-audit" ] && fail "Claude-only memory-audit leaked into Codex"
[ -e "$HOME/.agents/skills/skill-creator" ] && fail "kit skill-creator shadowed Codex built-in"
[ -L "$HOME/.codex/agents/executor.toml" ] || fail "Codex executor agent not linked"
grep -q 'second opinion from Claude' "$HOME/.agents/skills/cross-ai/SKILL.md" \
  || fail "Codex cross-ai did not use the Codex-specific implementation"
[ -n "$(find "$HOME/.codex/backups" -maxdepth 1 -name 'skill-cross-ai.*' -print -quit)" ] \
  || fail "pre-existing Codex cross-ai was not backed up"
[ -n "$(find "$HOME/.codex/backups" -maxdepth 1 -name 'skill-checkpoint.*' -print -quit)" ] \
  || fail "pre-existing unrelated checkpoint symlink was not backed up"

# 3. Hook merge preserves unrelated entries and registers each kit handler once.
python3 - "$HOME/.codex/hooks.json" <<'PY' || fails=1
import json, sys
d = json.load(open(sys.argv[1]))
assert d["description"] == "keep-me"
assert any(h.get("command") == "true" for g in d["hooks"]["Stop"] for h in g["hooks"])
checks = {
    "PreToolUse": "codex-git-guard.sh",
    "SessionStart": "codex-rules.py",
    "SubagentStart": "codex-rules.py",
}
for event, needle in checks.items():
    count = sum(needle in h.get("command", "") for g in d["hooks"].get(event, []) for h in g["hooks"])
    assert count == 1, (event, count)
print("codex hook merge: ok")
PY

# 4. The startup hook reads canonical global + project opt-in rules and logs hashes.
PROJ="$TMP/project"
mkdir -p "$PROJ/.claude"
printf 'remote-compute\n' > "$PROJ/.claude/kit-rules"
REAL_PROJ="$(cd "$PROJ" && pwd -P)"
out="$(printf '{"session_id":"cx1","cwd":"%s","hook_event_name":"SessionStart","source":"startup"}' \
  "$REAL_PROJ" | "$KIT/hooks/codex-rules.py")"
grep -q 'kit/global: git-and-style.md' <<<"$out" || fail "global rule not injected"
grep -q 'kit/optin: remote-compute.md' <<<"$out" || fail "project opt-in rule not injected"
python3 - "$HOME/.codex/kit-state/instructions.jsonl" <<'PY' || fails=1
import json, sys
d = json.loads(open(sys.argv[1]).read().splitlines()[-1])
assert d["session_id"] == "cx1"
assert d["event"] == "SessionStart"
assert {r["name"] for r in d["rules"]} >= {"git-and-style", "remote-compute"}
assert all(len(r["sha256"]) == 64 for r in d["rules"])
PY

# Observation must be best-effort: an unusable HOME cannot suppress rule stdout.
printf 'not a directory\n' > "$TMP/home-is-a-file"
out="$(printf '{"session_id":"cx-log-fail","cwd":"%s","hook_event_name":"SubagentStart"}' "$REAL_PROJ" \
  | HOME="$TMP/home-is-a-file" "$KIT/hooks/codex-rules.py")"
grep -q 'kit/global: git-and-style.md' <<<"$out" || fail "log failure suppressed Codex rule injection"

# 4b. ⭐ RED-BEFORE-GREEN on the injection failure contract. The hook used to end in
#     `except Exception: raise SystemExit(0)`, justified as "observability must never
#     stop a session" — which swallowed the INJECTION half too. And because the
#     per-rule sha256 ran BEFORE anything was printed, ONE unreadable rule produced
#     zero injected rules, exit 0, and a Codex session that looked perfectly normal.
#     That is the exact shape of silent degradation the kit's coding-practice rule
#     exists to forbid, sitting in the kit's own control plane.
copy_kit_for_test "$SRC" "$TMP/kitbroken"
BROKEN="$TMP/kitbroken"
# make one SELECTED rule unreadable as a rule: a directory where a file must be
rm -f "$BROKEN/rules/global/work-discipline.md"
mkdir -p "$BROKEN/rules/global/work-discipline.md"
set +e
out="$(printf '{"session_id":"cx-broken","cwd":"%s","hook_event_name":"SessionStart"}' "$REAL_PROJ" \
  | "$BROKEN/hooks/codex-rules.py" 2>"$TMP/broken.err")"
rc=$?
set -e
[ "$rc" -ne 0 ] || fail "an unreadable selected rule still exited 0 — a silent zero-rule session"
grep -q "RULE INJECTION FAILED" "$TMP/broken.err" \
  || fail "injection failure was not reported on stderr"
grep -q "RULE INJECTION FAILED" <<<"$out" \
  || fail "injection failure was not reported on stdout — the model would not know"
grep -q "work-discipline" "$TMP/broken.err" \
  || fail "the failure did not name which rule could not be read"
grep -q "kit/global: git-and-style.md" <<<"$out" \
  && fail "printed a PARTIAL rule set alongside the failure — must be all-or-loud"

# an unusable HOME is the OTHER side of the contract: observation may fail silently,
# injection may not. (Asserted just above at step 4; re-stated here as the pair.)

# 4c. ⭐ THE SELECTION FAILURE CONTRACT: absent is legitimate, unreadable is not.
#     Measured 2026-09-05, before this: an unreadable project manifest ⇒ exit 0, ZERO
#     bytes of stderr, and the opt-in rule simply gone; an unreadable kit.conf holding
#     `off rule:work-discipline` ⇒ exit 0 and that DISABLED rule injected anyway. Two
#     directions, both silent. A selection input we cannot read means we do not know
#     the answer, and "we do not know" must never render as a confident default.
copy_kit_for_test "$SRC" "$TMP/kitsel"
SEL="$TMP/kitsel"
selrun() { printf '{"session_id":"cx-sel","cwd":"%s","hook_event_name":"SessionStart"}' "$REAL_PROJ" \
             | HOME="$TMP/selhome" "$SEL/hooks/codex-rules.py" 2>"$TMP/sel.err"; }

chmod 000 "$PROJ/.claude/kit-rules"
set +e; out="$(selrun)"; rc=$?; set -e
chmod 644 "$PROJ/.claude/kit-rules"
[ "$rc" -eq 3 ] || fail "unreadable project manifest exited $rc — a silent wrong selection"
grep -q "RULE INJECTION FAILED" "$TMP/sel.err" || fail "unreadable manifest was not reported"
grep -q "kit-rules" "$TMP/sel.err" || fail "the failure did not name the unreadable file"

printf 'off rule:work-discipline\n' >> "$SEL/kit.conf"
chmod 000 "$SEL/kit.conf"
set +e; out="$(selrun)"; rc=$?; set -e
chmod 644 "$SEL/kit.conf"
[ "$rc" -eq 3 ] || fail "unreadable kit.conf exited $rc"
grep -q "kit/global: work-discipline.md" <<<"$out" \
  && fail "⛔ injected a rule that kit.conf had switched OFF, because kit.conf was unreadable"
grep -v 'off rule:work-discipline' "$SEL/kit.conf" > "$SEL/kit.conf.t" && mv "$SEL/kit.conf.t" "$SEL/kit.conf"

# absent stays legitimate — this contract must not turn "no opt-in" into an error
mv "$PROJ/.claude/kit-rules" "$TMP/manifest.bak"
set +e; out="$(selrun)"; rc=$?; set -e
mv "$TMP/manifest.bak" "$PROJ/.claude/kit-rules"
[ "$rc" -eq 0 ] || fail "an ABSENT manifest must be legitimate, got exit $rc"
grep -q "kit/global: git-and-style.md" <<<"$out" || fail "absent manifest suppressed the global rules"

# 4d. ⭐ THE INJECTION BOUNDARY: once the rules are on stdout, nothing may deny it.
#     Measured 2026-09-05: a stray byte in the kit-state log made trim_log raise past
#     `except OSError`, and a session whose six rules HAD been printed reported
#     "RULE INJECTION FAILED" — with those six rules sitting right above the banner.
set +e
out="$(printf '{"cwd":"%s","hook_event_name":"SessionStart"}' "$REAL_PROJ" \
       | CODEX_RULES_FAULT=pre-injection HOME="$TMP/selhome" "$SEL/hooks/codex-rules.py" 2>"$TMP/sel.err")"
rc=$?
set -e
[ "$rc" -eq 3 ] || fail "a pre-injection fault must exit 3, got $rc"
grep -q "RULE INJECTION FAILED" "$TMP/sel.err" || fail "a pre-injection fault must raise the banner"
grep -q "kit/global" <<<"$out" && fail "a pre-injection fault printed rules anyway"

set +e
out="$(printf '{"cwd":"%s","hook_event_name":"SessionStart"}' "$REAL_PROJ" \
       | CODEX_RULES_FAULT=post-injection HOME="$TMP/selhome" "$SEL/hooks/codex-rules.py" 2>"$TMP/sel.err")"
rc=$?
set -e
[ "$rc" -eq 0 ] || fail "a POST-injection fault must not fail the session, got $rc"
grep -q "kit/global" <<<"$out" || fail "post-injection fault lost the already-printed rules"
grep -q "RULE INJECTION FAILED" "$TMP/sel.err" \
  && fail "⛔ claimed the injection failed while the rules were on stdout"
grep -q "rules WERE injected" "$TMP/sel.err" || fail "post-injection failure was not reported honestly"

# an unusable HOME is the observation layer's own version of the same contract
printf 'not a directory\n' > "$TMP/home-is-a-file2"
set +e
out="$(printf '{"cwd":"%s","hook_event_name":"SessionStart"}' "$REAL_PROJ" \
       | HOME="$TMP/home-is-a-file2" "$SEL/hooks/codex-rules.py" 2>"$TMP/sel.err")"
rc=$?
set -e
[ "$rc" -eq 0 ] || fail "an unusable HOME must not fail the session, got $rc"
grep -q "kit/global" <<<"$out" || fail "an unusable HOME suppressed rule injection"
grep -q "only the kit-state log failed" "$TMP/sel.err" || fail "log failure was not named as such"

# 4e. ⭐ PARITY: the Python selector and lib/assets.sh must agree on every rule.
#     asset-state authority lives in bash; Codex re-derives selection in python. They
#     agree today; this is the gate that keeps them agreeing. (Cheaper than merging
#     them, and it fails the moment either side drifts.)
# export, not a `VAR=x .` prefix — assets.sh runs under `set -u`, so the prefix form
# leaves KIT_ROOT unbound, every asset_state call errors to empty, and the comparison
# below becomes empty-vs-empty: a PASS that compared nothing. (Caught here, 2026-09-05.)
export KIT_ROOT="$SEL"
. "$SEL/lib/assets.sh"
py_selected="$(printf '{"cwd":"%s","hook_event_name":"SessionStart"}' "$REAL_PROJ" \
  | HOME="$TMP/selhome" "$SEL/hooks/codex-rules.py" 2>/dev/null \
  | sed -n 's/^<!-- kit\/[a-z]*: \(.*\)\.md -->$/\1/p' | sort)"
# ⭐ the bash side is `selected_rules` itself, not a re-implementation of it. Writing
# the expected set out by hand here would have made the TEST a third authority — the
# exact shape it is meant to catch.
sh_selected="$(selected_rules "$PROJ" | awk '{print $1}' | sort)"
# both sides must be NON-EMPTY before comparing them, or equality proves nothing
[ "$(wc -l <<<"$sh_selected")" -ge 6 ] || fail "the bash side selected $(wc -l <<<"$sh_selected") rules — it did not run"
[ "$(wc -l <<<"$py_selected")" -ge 6 ] || fail "the python side selected $(wc -l <<<"$py_selected") rules — it did not run"
[ "$py_selected" = "$sh_selected" ] || {
  fail "codex-rules.py and lib/assets.sh disagree on rule selection"
  diff <(echo "$sh_selected") <(echo "$py_selected") | sed 's/^/    /'
}

# 5. `kit state codex` reports observed context and content-version agreement.
json="$(cd "$PROJ" && "$KIT/bin/kit" state codex --json)"
echo "$json" | python3 -c '
import json, sys
d=json.load(sys.stdin)
assert d["host"] == "codex"
assert d["session"] == "cx1"
assert not d["manifest_not_loaded"], d["manifest_not_loaded"]
assert all(x["matches_current"] for x in d["loaded"])
assert "executor" in d["links"]["agents"]
' || fail "kit state codex JSON is wrong"

# 6. Codex cannot express ASK: the adapter blocks until the explicit bypass is present.
if printf '{"tool_input":{"command":"git reset --hard"}}' | "$KIT/hooks/codex-git-guard.sh" >/dev/null 2>&1; then
  fail "Codex ASK-tier command was allowed"
fi
printf '{"tool_input":{"command":"CLAUDE_KIT_GIT_GUARD_BYPASS=1 git reset --hard"}}' \
  | "$KIT/hooks/codex-git-guard.sh" >/dev/null 2>&1 || fail "explicit Codex guard bypass was blocked"

"$KIT/bin/kit" doctor codex >/dev/null 2>&1 || fail "kit doctor codex reports failures"

[ "$fails" -eq 0 ] && echo "codex: ALL PASS" || echo "codex: FAILURES"
exit "$fails"
