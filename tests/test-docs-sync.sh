#!/usr/bin/env bash
# test-docs-sync.sh — the README asset inventory is DERIVED, and stays derived.
#
# Why this suite exists: the inventory used to be hand-typed. A new global rule
# was added 2026-08-26 and first appeared in the README on 2026-08-31; the
# "跑完就有 …" line still claimed 4 global rules / 2 hooks when the registry held
# 6 and 4, and "8 套回归" when there were 10. The kit's own rule names the
# mechanism — a second copy of a fact, and the copy the reader sees is the one
# that rots. ⛔ The fix is not "remember to update the README".
#
# 1. the committed block must equal what the generator produces (the gate);
# 2. adding an asset must change the block (the gate can actually fail);
# 3. an asset with no summary must be an error, not a blank line;
# 4. the generator's Codex projection must agree with lib/assets.sh.
set -euo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
. "$(dirname "${BASH_SOURCE[0]}")/lib-testkit.sh"
fails=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*"; fails=1; }

# 1. the committed README is in sync with its own assets
"$KIT/bin/kit" docs-sync --check >/dev/null 2>"$TMP/check.err" \
  || { echo "--- docs-sync --check said:"; cat "$TMP/check.err"; fail "README inventory is stale — run 'kit docs-sync'"; }

# 2..4 operate on a throwaway copy (copy_kit_for_test refuses to hand back an alias)
copy_kit_for_test "$KIT" "$TMP/kit"

# 2. a new asset must move the block — otherwise the gate is decorative
printf '<!-- claude-kit rule · zz-probe — probe -->\n## probe\n' > "$TMP/kit/rules/global/zz-probe.md"
if "$TMP/kit/bin/kit" docs-sync --check >/dev/null 2>&1; then
  fail "adding a global rule did not make --check fail"
fi
"$TMP/kit/bin/kit" docs-sync >/dev/null
grep -q 'zz-probe' "$TMP/kit/README.zh.md" || fail "regenerated block does not list the new rule"
# ⛔ NOT `grep -q '7 条常驻规则'`. That is the frozen-global-count shape measured in
# another project on 2026-09-01: 14 of 17 test files that day were copies of `== 52`-style
# snapshots, they caught zero bugs, and every later LEGITIMATE addition turned them
# red. Assert the RELATIONSHIP — the printed count equals what the directory holds —
# so adding a real 7th rule tomorrow changes nothing here.
want_rules=$(ls "$TMP/kit"/rules/global/*.md | wc -l | tr -d ' ')
grep -q "$want_rules 条常驻规则" "$TMP/kit/README.zh.md" \
  || fail "the counts line says something other than the $want_rules rules on disk"

# 3. a summary-less asset is an error, not a blank cell
printf '## no header\n' > "$TMP/kit/rules/global/zz-probe.md"
if "$TMP/kit/bin/kit" docs-sync >/dev/null 2>"$TMP/err"; then
  fail "a rule with no 'claude-kit rule · …' header was accepted"
fi
grep -q 'line 1 must be' "$TMP/err" || fail "the error did not say what is missing"
rm -f "$TMP/kit/rules/global/zz-probe.md"

# 4. the generator's "which skills also ship to Codex" must agree with lib/assets.sh,
#    which is the real installer's source. Two opinions here = a lying README.
KIT_ROOT="$KIT" . "$KIT/lib/assets.sh"
for d in "$KIT"/skills/*/; do
  name="$(basename "$d")"
  if KIT_ROOT="$KIT" codex_skill_source "$name" >/dev/null 2>&1; then want=yes; else want=no; fi
  if python3 - "$KIT" "$name" <<'PY'
import sys
sys.path.insert(0, sys.argv[1] + "/lib")
import docs_sync
sys.exit(0 if sys.argv[2] not in docs_sync.CODEX_SKILL_SKIP else 1)
PY
  then got=yes; else got=no; fi
  [ "$want" = "$got" ] || fail "codex mapping disagrees for skill '$name': assets.sh=$want docs_sync=$got"
done

# 4b. summary truncation must hold for CJK. `rfind(" ")` returns -1 when there is no
#     space inside the limit — which is every long Chinese summary — and the old
#     `text[:-1]` then dropped ONE character instead of truncating. Measured: a
#     130-char space-less summary came back at 130 chars, i.e. not truncated at all.
python3 - "$KIT" <<'CJKPROBE' || fail "first_sentence does not truncate a space-less CJK summary"
import sys
sys.path.insert(0, sys.argv[1] + "/lib")
import docs_sync
probe = "这是一段刻意超过九十个字符的中文摘要里面完全没有空格" * 5
assert len(probe) > 90, "probe too short to reach the truncation branch"
out = docs_sync.first_sentence(probe)
assert len(out) <= 91, f"not truncated: {len(out)}"
CJKPROBE

# 5. no suite may pipe INTO `grep -q`. `grep -q` exits on its first match, the writer
#    gets SIGPIPE (141), and `set -o pipefail` then fails the pipeline — a FALSE FAIL
#    that fires precisely when the assertion SUCCEEDED. CI reported "global rule not
#    injected" that way from 2026-09-03 to 2026-09-04 while the rule was injected; it
#    passed on macOS, so it looked like a Linux problem rather than a broken assertion.
#    Use a herestring (`grep -q P <<<"$out"`) or `[ -n "$(...)" ]`.
# ⚠️ `[^|]` matters: without it this also matched the second bar of `|| grep -q`,
# which is a boolean fallback, not a pipe. A gate that cries wolf gets ignored, so
# the predicate is narrowed rather than exempted case by case.
if grep -rnE '[^|]\| *grep -q' "$KIT"/tests/*.sh; then
  fail "a suite pipes into 'grep -q' — SIGPIPE + pipefail makes a SUCCESSFUL match report FAIL; use <<<\"\$out\""
fi

[ "$fails" -eq 0 ] && echo "PASS: docs-sync" || echo "docs-sync: FAILURES"
exit "$fails"
