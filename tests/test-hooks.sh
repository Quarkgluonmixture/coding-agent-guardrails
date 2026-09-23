#!/usr/bin/env bash
# test-hooks.sh — the two python hooks' own negative-first self-tests, plus the
# invariants that tie them to the rest of the kit:
#   - wrap-up-trigger's word list is a subset of the checkpoint skill's declared triggers
#     (the hook is the authority for the natural-language path; the skill must not drift past it)
#   - a real invocation fires on an explicit short instruction and stays silent otherwise
#   - gotchas-contract never writes under ~/.claude during tests (state dir is overridden)
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
KIT="$(cd "$HERE/.." && pwd -P)"
fails=0

echo "--- wrap-up-trigger self-test"
if ! out="$(python3 "$KIT/hooks/wrap-up-trigger.py" --self-test 2>&1)"; then
  echo "FAIL: wrap-up-trigger self-test"; printf '%s\n' "$out" | sed 's/^/    /'; fails=1
fi

echo "--- gotchas-contract self-test"
if ! out="$(python3 "$KIT/hooks/gotchas-contract.py" --self-test 2>&1)"; then
  echo "FAIL: gotchas-contract self-test"; printf '%s\n' "$out" | sed 's/^/    /'; fails=1
fi

# Both hooks' entire vocabulary is Chinese, and their fixtures round-trip through
# files and pipes. Run the self-tests AGAIN with the locale forced to ASCII: this is
# what made CI red on ubuntu while macOS stayed green, and locally it surfaced as a
# hard UnicodeEncodeError inside the gate that enforces "explicit encoding at process
# edges". If a bare open()/text=True comes back, this catches it on any machine.
echo "--- self-tests under a forced ASCII locale (no UTF-8 anywhere)"
for h in wrap-up-trigger gotchas-contract; do
  if ! out="$(env -u LANG -u LC_CTYPE LC_ALL=C LANG=C PYTHONUTF8=0 PYTHONCOERCECLOCALE=0 \
              python3 "$KIT/hooks/$h.py" --self-test 2>&1)"; then
    echo "FAIL: $h self-test depends on a UTF-8 locale"; printf '%s\n' "$out" | tail -20 | sed 's/^/    /'; fails=1
  fi
done

# ── gotchas-contract runs on PostToolBatch now: one payload, many tool calls ──
# Payload shape measured on Claude Code 2.1.261 (2026-09-05) by registering a probe
# hook and dumping stdin — the docs do not specify it:
#   {cwd, session_id, prompt_id, permission_mode, transcript_path, hook_event_name,
#    tool_calls: [{tool_name, tool_input, tool_use_id, tool_response}, ...]}
# What these catch: a future edit reads payload["tool_input"] again (works under
# PostToolUse, silently sees NOTHING under a batch ⇒ the gate stops gating), or
# filters the batch on the FIRST tool name (one Write among nine reads gets skipped).
echo "--- PostToolBatch payload shape"
BT="$(mktemp -d)"
BR="$BT/repo"; mkdir -p "$BR/docs"; (cd "$BR" && git init -q)
printf '# G\n\n**1 · old**\n闸: 无 — 已有条目，理由写得够长了\n' > "$BR/docs/GOTCHAS.md"
(cd "$BR" && git add docs/GOTCHAS.md && git -c user.name=t -c user.email=t@t commit -q -m base)
printf '\n**2 · new**\nno declaration\n' >> "$BR/docs/GOTCHAS.md"

batch_payload() {   # $1 = json array of tool_calls
  printf '{"cwd":"%s","hook_event_name":"PostToolBatch","session_id":"b","tool_calls":%s}' "$BR" "$1"
}

# a Write hiding among reads must still be gated
batch_payload "[{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$BR/docs/GOTCHAS.md\"}},{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$BR/docs/GOTCHAS.md\"}}]" \
  | python3 "$KIT/hooks/gotchas-contract.py" --state-dir "$BT/s1" >/dev/null 2>"$BT/e1"
rc=$?
[ "$rc" -eq 2 ] || { echo "FAIL: a batch containing a Write was not gated (exit $rc)"; fails=1; }
grep -q "entry 2" "$BT/e1" || { echo "FAIL: the batch gate did not name the undeclared entry"; fails=1; }

# a batch of pure reads must cost nothing and say nothing
batch_payload "[{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$BR/docs/GOTCHAS.md\"}}]" \
  | python3 "$KIT/hooks/gotchas-contract.py" --state-dir "$BT/s2" >/dev/null 2>"$BT/e2"
rc=$?
[ "$rc" -eq 0 ] || { echo "FAIL: a read-only batch was gated (exit $rc)"; fails=1; }
# ⚠ `[ -s f ] && {...}` returns 1 when f is empty, and `set -e` then kills the suite
# with no message at all. Use if/then for a check whose expected answer is "false".
if [ -s "$BT/e2" ]; then echo "FAIL: a read-only batch produced output"; fails=1; fi

# the single-call PostToolUse shape must keep working — Codex has no batch event
printf '{"cwd":"%s","tool_name":"Edit","tool_input":{"file_path":"%s/docs/GOTCHAS.md"}}' "$BR" "$BR" \
  | python3 "$KIT/hooks/gotchas-contract.py" --state-dir "$BT/s3" >/dev/null 2>"$BT/e3"
rc=$?
[ "$rc" -eq 2 ] || { echo "FAIL: the single-call payload shape stopped working (exit $rc)"; fails=1; }
rm -rf "$BT"

echo "--- trigger words ⊆ checkpoint skill triggers"
desc="$(sed -n '3p' "$KIT/skills/checkpoint/SKILL.md" | tr '[:upper:]' '[:lower:]')"
while IFS= read -r w; do
  lw="$(printf '%s' "$w" | tr '[:upper:]' '[:lower:]')"
  case "$desc" in *"$lw"*) : ;; *) echo "FAIL: trigger '$w' not declared in skills/checkpoint/SKILL.md description"; fails=1 ;; esac
done < <(python3 "$KIT/hooks/wrap-up-trigger.py" --triggers)

echo "--- live invocation shape"
out="$(printf '{"prompt":"好，收尾 session"}' | python3 "$KIT/hooks/wrap-up-trigger.py")"
case "$out" in *checkpoint*) : ;; *) echo "FAIL: explicit 收尾 did not inject"; fails=1 ;; esac
out="$(printf '{"prompt":"把构建产物存档到 S3"}' | python3 "$KIT/hooks/wrap-up-trigger.py")"
[ -z "$out" ] || { echo "FAIL: archive-meaning sentence injected"; fails=1; }
printf '{not json' | python3 "$KIT/hooks/wrap-up-trigger.py" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] || { echo "FAIL: malformed input should exit 1 (got $rc) — exit 2 would erase the prompt"; fails=1; }

echo "--- gotchas-contract stays out of the real state dir under test"
tmp="$(mktemp -d)"
printf '{"cwd":"%s","tool_name":"Bash","tool_input":{}}' "$tmp" | python3 "$KIT/hooks/gotchas-contract.py" --state-dir "$tmp/state" >/dev/null 2>&1
[ -e "$tmp/state" ] && { echo "FAIL: no-GOTCHAS payload should not create state"; fails=1; }
rm -rf "$tmp"

[ "$fails" -eq 0 ] && echo "hooks: ALL PASS" || echo "hooks: FAILURES"
exit "$fails"
