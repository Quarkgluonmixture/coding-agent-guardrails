#!/usr/bin/env bash
# canary-page-in.sh — does a resident pointer actually cause the model to READ the
# reference? ⛔ NOT part of run-all.sh: it spends real sessions (tokens, network,
# minutes). Run it by hand after changing a pointer, or when a reference is added.
#
# Why it exists: rules/global was split into a resident kernel plus paged-in
# references on 2026-09-04, and tests/test-rules-budget.sh only proves the FILE GRAPH
# is sound — the reference exists, some rule points at it, the path resolves. It
# cannot prove the only thing that matters:
#
#     trigger situation → model recognises it → model actually reads the file
#
# That was the biggest unverified assumption in the whole kernel/reference design,
# and "the pointer is there" is exactly the kind of evidence this kit refuses
# elsewhere. Positive AND negative, because a model that reads every reference every
# time is not passing — it is just noisy, and it would put the bytes back.
#
# Method (measured 2026-09-05, Claude Code 2.1.261):
#   claude -p '<prompt>' --output-format=stream-json --verbose < /dev/null
# and look for a tool_use whose input names the reference. ⚠️ Three traps:
#   · macOS has no `timeout` — a wrapped command exits 127 and the empty output reads
#     like a clean negative result;
#   · the prompt must be `-p '<...>'`; placed after --allowedTools it is swallowed as
#     another value for that flag;
#   · assert on the TOOL CALL, never on the prose. A model can describe a reference's
#     content from the one-line summary in the rule and look like it read the file.
set -uo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
fails=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

HOST="${1:-claude}"
case "$HOST" in claude|codex) : ;; *) echo "usage: $0 [claude|codex]" >&2; exit 2 ;; esac
command -v "$HOST" >/dev/null || { echo "SKIP: no $HOST CLI"; exit 0; }

# ⛔⛔ `< /dev/null` on BOTH hosts, and it is not optional. `codex exec` reads stdin
# even when a prompt argument is given ("If stdin is piped and a prompt is also
# provided, stdin is appended as a <stdin> block") — without it, it prints "Reading
# additional input from stdin..." and blocks. Measured: one probe hung for 3h51m
# having produced zero lines, i.e. it never started. `claude -p` has the same trap.
# ⇒ A canary that hangs looks exactly like a canary that is slow.

# Did any tool call in this run name the given reference?
read_it() {   # read_it <stream.jsonl> <reference-basename>
  python3 - "$1" "$2" <<'PY'
import json, sys
needle = sys.argv[2]
hit = False
for line in open(sys.argv[1], encoding="utf-8", errors="replace"):
    line = line.strip()
    if not line:
        continue
    try:
        d = json.loads(line)
    except ValueError:
        continue
    msg = d.get("message") or {}
    for block in (msg.get("content") or []):
        if isinstance(block, dict) and block.get("type") == "tool_use":
            if needle in json.dumps(block.get("input") or {}, ensure_ascii=False):
                hit = True
    # Codex emits its own event shape; look at the command/arguments it executed,
    # ⛔ never at the assistant text (that is the "sounds like it read it" failure).
    ev = d.get("msg") if isinstance(d.get("msg"), dict) else d
    if isinstance(ev, dict) and ev.get("type") in {
            "exec_command_begin", "exec_command_end", "patch_apply_begin",
            "mcp_tool_call_begin", "function_call"}:
        if needle in json.dumps(ev, ensure_ascii=False):
            hit = True
print("yes" if hit else "no")
PY
}

run_case() {   # run_case <label> <expect yes|no> <reference-basename> <prompt>
  local label="$1" expect="$2" ref="$3" prompt="$4" got
  local work="$TMP/$label"; mkdir -p "$work"
  if [ "$HOST" = codex ]; then
    ( cd "$work" && codex exec --json --skip-git-repo-check "$prompt" \
        < /dev/null > "$TMP/$label.jsonl" 2>"$TMP/$label.err" )
  else
    ( cd "$work" && claude -p "$prompt" \
        --output-format=stream-json --verbose \
        --allowedTools Read Grep Glob \
        < /dev/null > "$TMP/$label.jsonl" 2>"$TMP/$label.err" )
  fi
  if [ ! -s "$TMP/$label.jsonl" ]; then
    echo "  ✗ $label: the probe produced NO output — it did not run (see $TMP/$label.err)"
    fails=1
    return
  fi
  got="$(read_it "$TMP/$label.jsonl" "$ref")"
  if [ "$got" = "$expect" ]; then
    echo "  ✓ $label: read=$got (want $expect)"
  else
    echo "  ✗ $label: read=$got (want $expect) — $ref"
    fails=1
  fi
}

# ⭐⭐ MEASURED 2026-09-05 — the two hosts do NOT behave the same here:
#   claude : 4/4. Pointers fire on their trigger, stay quiet otherwise.
#   codex  : 0/2 positives. It never reads the reference.
# Both confounders were ruled out before blaming the model: the rules WERE injected
# (~/.codex/kit-state showed a SessionStart record with 6 rules for those very runs)
# and the sandbox CAN read the path (`head -1 ~/claude-kit/references/...` succeeded
# in a codex session). So the pointer is in context, the file is reachable, and Codex
# simply does not go and look.
# ⇒ ARCHITECTURAL CONSEQUENCE: demoting content to references/ is a CLAUDE-side
#   optimisation. On Codex, whatever is demoted is effectively gone, and only the
#   one-line version in the rule survives. That one line must therefore be a complete
#   instruction on its own — which is the criterion the split already used, but it is
#   now a requirement rather than good practice. ⛔ Do not demote anything whose
#   one-liner is only a teaser.
echo "page-in canary [$HOST] — 2 references, positive + negative"

# ── ui-render-verification ───────────────────────────────────────────────────
# The rule's trigger is "about to say a UI/style/layout change took effect, or to use
# headless to prove something". The prompt states exactly that situation and NOTHING
# about references, so a hit means the pointer fired, not that it was told to.
run_case ui-pos yes ui-render-verification.md \
'I edited a CSS rule so a button should now be white, I rebuilt, and I grepped the
built chunk — the hex is there. I want to tell my colleague the fix is confirmed.
Before I do: what exactly should I check? Do not change any files.'

# Negative: a plain question with no verification claim in it. A model that reads
# references anyway has not "passed" — it has put the bytes back into every session.
run_case ui-neg no ui-render-verification.md \
'In one sentence, what does the CSS `inherit` keyword do?'

# ── concurrency-and-worktrees ────────────────────────────────────────────────
run_case wt-pos yes concurrency-and-worktrees.md \
'Another session is working in this repo at the same time and I need my own worktree
to avoid stepping on it. Tell me the exact commands you would run and why. Do not run
them.'

run_case wt-neg no concurrency-and-worktrees.md \
'In one sentence, what does `git rev-parse HEAD` print?'

echo
if [ "$fails" -eq 0 ]; then
  echo "page-in canary: ALL PASS — the pointers fire on their trigger and stay quiet otherwise"
else
  echo "page-in canary: FAILURES"
  echo "  A missed POSITIVE means the one-line version in the rule is not enough to make"
  echo "  the model go look — rewrite the trigger condition, or move that content back"
  echo "  into the resident kernel (and pay for it there)."
  echo "  A tripped NEGATIVE means the pointer is too broad and is costing every session."
fi
exit "$fails"
