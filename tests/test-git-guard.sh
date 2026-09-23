#!/usr/bin/env bash
# test-git-guard.sh — regression matrix for hooks/git-guard.sh.
# Locks in the three outcomes: DENY (exit 2), ASK (exit 0 + permissionDecision json),
# and ALLOW (exit 0, no json). Plus: prose/heredoc mentions never trip it, quoted
# single tokens can't hide, --force-with-lease stays allowed, bypass marker works.
set -euo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

python3 - "$KIT/hooks/git-guard.sh" <<'EOF'
import json, subprocess, sys

hook = sys.argv[1]

DENY, ASK, ALLOW = "deny", "ask", "allow"

cases = {
    # --- DENY: sweeping stages (the two blood-lesson rules) ---
    'git add -A': DENY,
    'git add .': DENY,
    'git add ./': DENY,
    'cd x && git add --all && git commit': DENY,
    'git commit -am "x"': DENY,
    'git add -A && git commit -m "x"': DENY,
    'git add -u': DENY,
    'git add --update': DENY,
    'git add -Av': DENY,
    'git commit --all': DENY,
    'git commit -av': DENY,
    'git commit -qam "x"': DENY,
    'git add "."': DENY,
    "git add '-A'": DENY,
    'git add "-A"': DENY,
    'git -C /tmp/repo add -A': DENY,
    # --- DENY: bypassing checks / unrecoverable deletion / remote history ---
    'git commit --no-verify -m "x"': DENY,
    'git commit -n -m "x"': DENY,
    'git clean -fd': DENY,
    'git clean -f': DENY,
    'git clean -fdx': DENY,
    'git clean --force -d': DENY,
    'git push --force origin main': DENY,
    'git push -f': DENY,
    'git push origin main --force': DENY,

    # --- ASK: destroys uncommitted work, but is a real part of this user's workflow ---
    'git reset --hard': ASK,
    'git reset --hard HEAD~1': ASK,
    'git checkout .': ASK,
    'git checkout -- .': ASK,
    'git restore .': ASK,
    'git stash': ASK,
    'git stash push -u': ASK,
    'git stash save "wip"': ASK,
    'git stash clear': ASK,

    # --- ALLOW ---
    'git add src/a.ts docs/b.md': ALLOW,
    'git add ./src/file.ts': ALLOW,
    'git add .gitignore': ALLOW,
    'git commit --amend --no-edit': ALLOW,
    'git add -p': ALLOW,
    'git add -f vendored.bin': ALLOW,
    'git log --all': ALLOW,
    'git commit -s -m "x"': ALLOW,
    'git commit -m "docs: never git add -A"': ALLOW,
    'git commit -m "fix: handle the -a flag"': ALLOW,
    'echo "git add -A is banned"': ALLOW,
    'git add f.md && git commit -m "$(cat <<MSG\nhook blocks git add -A and git commit -a\nMSG\n)"': ALLOW,
    'CLAUDE_KIT_GIT_GUARD_BYPASS=1 git add -A': ALLOW,
    'CLAUDE_KIT_GIT_GUARD_BYPASS=1 git reset --hard': ALLOW,
    'echo hello': ALLOW,
    # the safe force-push form must stay usable, else people reach for --force
    'git push --force-with-lease origin main': ALLOW,
    'git push --force-with-lease': ALLOW,
    # ordinary navigation / partial restores must not be touched
    'git checkout main': ALLOW,
    'git checkout -b feature/x': ALLOW,
    'git checkout -- src/app.ts': ALLOW,
    'git restore --staged .': ALLOW,
    'git restore src/app.ts': ALLOW,
    'git stash pop': ALLOW,
    'git stash list': ALLOW,
    'git stash apply': ALLOW,
    'git stash push -- src/a.ts src/b.ts': ALLOW,
    'git reset HEAD~1': ALLOW,          # soft reset keeps the work
    'git clean -n': ALLOW,              # dry run
}


def classify(proc):
    if proc.returncode == 2:
        return DENY, proc.stderr.strip()
    if proc.returncode != 0:
        return f"exit{proc.returncode}", proc.stderr.strip()
    out = proc.stdout.strip()
    if not out:
        return ALLOW, ""
    try:
        payload = json.loads(out)
    except json.JSONDecodeError:
        return "badjson", out
    hso = payload.get("hookSpecificOutput", {})
    if hso.get("hookEventName") != "PreToolUse":
        return "badjson", out
    return hso.get("permissionDecision", "badjson"), hso.get("permissionDecisionReason", "")


fails = 0
for cmd, want in cases.items():
    r = subprocess.run([hook], input=json.dumps({"tool_input": {"command": cmd}}),
                       capture_output=True, text=True)
    got, detail = classify(r)
    ok = got == want
    fails += (not ok)
    print(f"{'ok  ' if ok else 'FAIL'} {got:>5} want={want:<5} :: {cmd[:66]!r}")
    if not ok and detail:
        print(f"      detail: {detail[:160]}")

# an ASK must always carry a human-readable reason, or the prompt is useless
r = subprocess.run([hook], input=json.dumps({"tool_input": {"command": "git reset --hard"}}),
                   capture_output=True, text=True)
reason = json.loads(r.stdout)["hookSpecificOutput"].get("permissionDecisionReason", "")
if "git-guard" not in reason or len(reason) < 20:
    print(f"FAIL: ask decision has no usable reason: {reason!r}")
    fails += 1
else:
    print("ok   ask carries a reason")

# malformed / empty payloads must not crash or block
for payload in ('{}', 'not json', '{"tool_input":{}}'):
    r = subprocess.run([hook], input=payload, capture_output=True, text=True)
    ok = r.returncode == 0 and not r.stdout.strip()
    fails += (not ok)
    print(f"{'ok  ' if ok else 'FAIL'} exit={r.returncode} want=0/no-json :: payload {payload!r}")

print("git-guard: ALL PASS" if not fails else f"git-guard: {fails} FAILURES")
sys.exit(1 if fails else 0)
EOF
