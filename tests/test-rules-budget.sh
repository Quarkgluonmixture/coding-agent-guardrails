#!/usr/bin/env bash
# test-rules-budget.sh — the resident instruction layer has a ceiling, and the
# non-resident tier must stay non-resident.
#
# Why a budget and not "keep it tidy": rules/global is loaded into EVERY Claude
# session and EVERY subagent, on both hosts. The kit got good at distilling
# incidents into rules, so the failure mode flipped — not instruction conflict
# but instruction SALIENCE DILUTION: 10 rules that must never be broken sitting
# at the same visual weight as 40 that are usually useful. A ceiling forces the
# trade to be explicit — to promote something you first compress or demote
# something else.
#
# ⛔ Raising CEILING because the suite went red is the whole thing this prevents.
# Raise it only with a reason in the commit message.
set -euo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
fails=0
fail() { echo "FAIL: $*"; fails=1; }

# ⚠️ This IS a frozen number, and that is deliberate — the one legitimate case for the
# shape another project measured as waste on 2026-09-01. There, `== 52` froze a global count
# to say "my slice moved nothing", so every later legitimate addition went red for no
# reason. Here the redness IS the deliverable: it forces the promote/demote trade at
# the moment someone adds a rule, and the message says which trade to make.
# ⛔ So do not "fix" this into a relationship — a budget that follows its own usage
# is not a budget.
CEILING=20000   # bytes, rules/global/*.md summed. 2026-09-04: 29,792 → 19,7xx after
                # the L0/L1 split; ~7,800 CJK-weighted tokens per session.

used=0
for f in "$KIT"/rules/global/*.md; do
  used=$((used + $(wc -c < "$f")))
done
echo "resident rules: $used / $CEILING bytes"
if [ "$used" -gt "$CEILING" ]; then
  fail "rules/global is $((used - CEILING)) bytes over budget — compress or demote a rule into references/ before adding one"
  for f in "$KIT"/rules/global/*.md; do printf '  %7d  %s\n' "$(wc -c < "$f")" "$(basename "$f")"; done
fi

# references/ is the paged-in tier: it must NOT be installed as a resident rule.
# install.sh globs rules/global + rules/optin only; assert that stays true, because
# moving a reference under rules/ would silently undo the whole split.
if grep -qE 'references/\*|references"/\*' "$KIT/install.sh" "$KIT/hooks/codex-rules.py" 2>/dev/null; then
  fail "install.sh or codex-rules.py globs references/ — the paged-in tier would become resident"
fi
[ -d "$KIT/references" ] || fail "references/ is missing"

# Every reference must be reachable: some resident rule has to name it, or nothing
# will ever page it in. A file nobody points at is a file nobody reads.
for f in "$KIT"/references/*.md; do
  base="$(basename "$f")"
  grep -rql "references/$base" "$KIT/rules/global" >/dev/null \
    || fail "references/$base is not pointed at by any resident rule — it can never be paged in"
done

# …and every pointer must resolve. A dangling `see references/foo.md` is worse than
# no pointer: it reads as though the detail exists.
grep -rhoE 'references/[a-z0-9-]+\.md' "$KIT/rules/global" "$KIT/rules/optin" 2>/dev/null | sort -u |
while read -r ref; do
  [ -f "$KIT/$ref" ] || { echo "FAIL: resident rules point at $ref, which does not exist"; exit 1; }
done || fails=1

[ "$fails" -eq 0 ] && echo "PASS: rules-budget" || echo "rules-budget: FAILURES"
exit "$fails"
