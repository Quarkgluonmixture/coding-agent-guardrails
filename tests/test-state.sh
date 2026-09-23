#!/usr/bin/env bash
# test-state.sh — the observability path: hooks/instructions-loaded.sh records what
# actually loaded, and `kit state` reports it (and, crucially, reports the gap when a
# rule is DECLARED in the manifest but never observed loading).
set -euo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
fails=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*"; fails=1; }

export HOME="$TMP/home"; mkdir -p "$HOME"
ln -s "$KIT" "$HOME/claude-kit"
PROJ="$TMP/proj"; mkdir -p "$PROJ"
# realpath: on macOS $TMPDIR lives under /var → /private/var, and the hook payload
# reports the resolved cwd while the shell keeps the symlinked one.
REAL_PROJ="$(cd "$PROJ" && pwd -P)"

HOOK="$KIT/hooks/instructions-loaded.sh"
LOG="$HOME/.claude/kit-state/instructions.jsonl"

emit() {   # emit <session> <file_path> <memory_type>
  printf '{"session_id":"%s","cwd":"%s","hook_event_name":"InstructionsLoaded","file_path":"%s","memory_type":"%s","load_reason":"session_start"}' \
    "$1" "$REAL_PROJ" "$2" "$3" | "$HOOK"
}

# Same, but the caller picks the cwd and the load reason. The hook's cwd follows
# `cd`, so one session legitimately produces records under several directories.
emit_at() {   # emit_at <session> <cwd> <file_path> <memory_type> <load_reason>
  printf '{"session_id":"%s","cwd":"%s","hook_event_name":"InstructionsLoaded","file_path":"%s","memory_type":"%s","load_reason":"%s"}' \
    "$1" "$2" "$3" "$4" "$5" | "$HOOK"
}

# 1. the hook writes one JSON line per event and never blocks
emit s1 "$KIT/rules/global/git-and-style.md" User
[ -f "$LOG" ] || fail "hook wrote no log"
[ "$(wc -l < "$LOG")" -eq 1 ] || fail "hook did not write exactly one line"
python3 -c "import json,sys; d=json.load(open('$LOG')); assert d['event']['session_id']=='s1'; assert d['ts']" \
  2>/dev/null || fail "log line is not the expected {ts, event} shape"

# 2. garbage in must not produce garbage out, and must not fail
printf 'not json' | "$HOOK" || fail "hook errored on non-JSON input"
printf '' | "$HOOK" || fail "hook errored on empty input"
[ "$(wc -l < "$LOG")" -eq 1 ] || fail "hook logged a non-JSON payload"

# 3. kit state reports the observed load, classified by kit tier
emit s1 "$KIT/rules/global/work-discipline.md" User
emit s1 "$HOME/.claude/CLAUDE.md" User
out="$(cd "$PROJ" && "$KIT/bin/kit" state)"
grep -q "kit/global" <<<"$out" || fail "state did not classify a global kit rule"
grep -q "git-and-style" <<<"$out" || fail "state did not list the loaded rule"

# 4. ⭐ the failure this command exists for: declared in the manifest, never observed.
(cd "$PROJ" && "$KIT/bin/kit" add remote-compute >/dev/null)
out="$(cd "$PROJ" && "$KIT/bin/kit" state)"
grep -q "declared but NOT observed" <<<"$out" || fail "state did not flag declared-but-not-loaded"
json="$(cd "$PROJ" && "$KIT/bin/kit" state --json)"
echo "$json" | python3 -c "
import json,sys
d = json.load(sys.stdin)
assert d['manifest_not_loaded'] == ['remote-compute'], d['manifest_not_loaded']
assert d['session'] == 's1', d['session']
tiers = {i['name']: i.get('tier') for i in d['loaded']}
assert tiers.get('git-and-style') == 'global', tiers
assert d['links']['agents'] == [] or isinstance(d['links']['agents'], list)
" 2>/dev/null || fail "state --json shape/contents wrong"

# 5. once it actually loads, the gap closes
emit s2 "$KIT/rules/optin/remote-compute.md" Project
out="$(cd "$PROJ" && "$KIT/bin/kit" state)"
grep -q "declared but NOT observed" <<<"$out" && fail "state still flags a rule that did load"
grep -q "kit/optin" <<<"$out" || fail "state did not classify the opt-in tier"

# 6. only the newest session is reported, and a sibling project never leaks in
emit s3 "$KIT/rules/global/memory-hygiene.md" User
printf '{"session_id":"other","cwd":"%s","hook_event_name":"InstructionsLoaded","file_path":"%s","memory_type":"User","load_reason":"session_start"}' \
  "$TMP/elsewhere" "$KIT/rules/global/work-discipline.md" | "$HOOK"
json="$(cd "$PROJ" && "$KIT/bin/kit" state --json)"
echo "$json" | python3 -c "
import json,sys
d = json.load(sys.stdin)
assert d['session'] == 's3', d['session']
assert len(d['loaded']) == 1, d['loaded']
" 2>/dev/null || fail "state did not isolate the newest session / leaked another project"

# 7. a project with no records says so instead of pretending everything is fine
mkdir -p "$TMP/fresh"
out="$(cd "$TMP/fresh" && "$KIT/bin/kit" state)"
grep -q "no InstructionsLoaded records" <<<"$out" || fail "state did not report the empty case"

# 8. ⭐ the hook's cwd follows `cd`: a session launched in the parent directory keeps its
#    session_start batch under the parent cwd, while later records carry the subdirectory.
#    Filtering records by cwd BEFORE grouping by session drops exactly the batch that lists
#    the rules. Measured on a real session 2026-09-03: 2 records under the subdirectory vs 8
#    for the same session across cwds — `kit state` reported zero rules while five were
#    demonstrably loaded, and that reading sent a diagnosis down the wrong path for hours.
mkdir -p "$PROJ/sub"
emit_at s9 "$REAL_PROJ"     "$KIT/rules/global/long-task-monitor.md" User    session_start
emit_at s9 "$REAL_PROJ/sub" "$REAL_PROJ/sub/CLAUDE.md"               Project nested_traversal
out="$(cd "$PROJ/sub" && "$KIT/bin/kit" state)"
grep -q "long-task-monitor" <<<"$out" \
  || fail "state dropped the launch-cwd records of the session it selected"


# ── the EXPECTED set comes from the asset authority, not from whichever links exist ──
# Before: `kit state` listed rules/global entries that happened to be symlinked. Two
# holes, opposite directions: an opt-in rule switched ON machine-wide was never in the
# expected set (so its absence could never be reported — the exact blind spot this
# command was built for), and a MISSING link silently dropped a rule OUT of the
# expected set instead of being reported.
CONF_BAK="$TMP/kit.conf.bak"
cp "$KIT/kit.conf" "$CONF_BAK"
restore_conf() { cp "$CONF_BAK" "$KIT/kit.conf"; }
trap 'restore_conf; rm -rf "$TMP"' EXIT

printf 'on  rule:cross-ai-review\n' >> "$KIT/kit.conf"
out="$(cd "$PROJ" && "$KIT/bin/kit" state claude)"
grep -q "cross-ai-review" <<<"$out" \
  || fail "an opt-in rule switched ON machine-wide is missing from the expected set"
grep -q "EXPECTED by kit.conf/manifest but NOT observed" <<<"$out" \
  || fail "state did not report the expected-but-unobserved gap"
restore_conf

# a rule whose LINK is missing must stay expected (and be reported), not vanish
rm -f "$HOME/.claude/rules/work-discipline.md" 2>/dev/null || true
out="$(cd "$PROJ" && "$KIT/bin/kit" state claude)"
grep -q "work-discipline" <<<"$out" \
  || fail "a rule with no link dropped OUT of the expected set instead of being reported"

# ── "your context is stale": the file changed after this session loaded it ──
emit s-stale "$KIT/rules/global/long-task-monitor.md" User
out="$(cd "$PROJ" && "$KIT/bin/kit" state claude)"
grep -q "edited AFTER this session loaded" <<<"$out" \
  && fail "nothing was edited yet, but state claims the context is stale"
sleep 2
touch "$KIT/rules/global/long-task-monitor.md"
# ⚠ two stdin redirections on one python3 call: the herestring wins and the script
# never arrives. Write the JSON out and pass the PATH.
(cd "$PROJ" && "$KIT/bin/kit" state claude --json) > "$TMP/state.json"
python3 - "$TMP/state.json" <<'PYEOF' || fails=1
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
assert "long-task-monitor" in d["changed_since_load"], \
    f"a rule edited after load was not flagged: {d['changed_since_load']}"
PYEOF

[ "$fails" -eq 0 ] && echo "state: ALL PASS" || echo "state: FAILURES"
exit "$fails"