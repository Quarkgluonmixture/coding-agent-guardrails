#!/usr/bin/env bash
# test-kit.sh — bin/kit is executable on this platform (portable resolve_path,
# no GNU readlink -f), including through a symlink chain, plus the opt-in
# round-trip: manifest is the portable record, symlinks are the machine-local
# materialisation, and `kit sync` rebuilds one from the other.
set -euo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
fails=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*"; fails=1; }

# 1. direct invocation — both rule tiers and both global asset kinds are listed
out="$("$KIT/bin/kit" list)"
grep -q "cross-ai" <<<"$out"        || fail "kit list missing skills"
grep -q "memory-hygiene" <<<"$out"  || fail "kit list missing global rules"
grep -q "remote-compute" <<<"$out"           || fail "kit list missing opt-in rules"
grep -q "executor" <<<"$out"        || fail "kit list missing agents"

# 2. through a 2-level symlink chain (what ~/.local/bin/kit is)
ln -s "$KIT/bin/kit" "$TMP/kit1"
ln -s "$TMP/kit1" "$TMP/kit2"
"$TMP/kit2" list >/dev/null || fail "kit via symlink chain"

# 3. add / sync / remove round-trip in a sandbox project + HOME
export HOME="$TMP/home"; mkdir -p "$HOME"
ln -s "$KIT" "$HOME/claude-kit"          # the stable alias project symlinks point through
PROJ="$TMP/proj"; mkdir -p "$PROJ"
cd "$PROJ"

"$KIT/bin/kit" add remote-compute >/dev/null
grep -qx "remote-compute" "$PROJ/.claude/kit-rules" || fail "kit add did not record the manifest entry"
[ -L "$PROJ/.claude/rules/kit/remote-compute.md" ]  || fail "kit add did not create the symlink"
[ -e "$PROJ/.claude/rules/kit/remote-compute.md" ]  || fail "kit add created a dangling symlink"
grep -qx "rules/kit/" "$PROJ/.claude/.gitignore" || fail "kit add did not gitignore generated links"

# the symlink must go through ~/claude-kit, not this checkout's path, or it dangles
# for anyone whose clone lives somewhere else
grep -q "^$HOME/claude-kit/" <<<"$(readlink "$PROJ/.claude/rules/kit/remote-compute.md")" \
  || fail "symlink does not point through the ~/claude-kit alias"

# NB: capture, don't pipe into `grep -q` — it closes the pipe on first match and
# SIGPIPEs kit, which `set -o pipefail` then reports as a failure of the whole test.
out="$("$KIT/bin/kit" add remote-compute)"
grep -q "already present" <<<"$out" || fail "kit add not idempotent"
"$KIT/bin/kit" add no-such-rule >/dev/null 2>&1 && fail "kit add accepted an unknown rule"

# a fresh clone on another machine has the manifest but no links — sync rebuilds them
rm -rf "$PROJ/.claude/rules"
out="$("$KIT/bin/kit" status)"
grep -q "symlink missing" <<<"$out" || fail "status did not flag the missing link"
"$KIT/bin/kit" sync >/dev/null
[ -e "$PROJ/.claude/rules/kit/remote-compute.md" ] || fail "kit sync did not rebuild the symlink"

# a hand-written project rule alongside kit's must survive sync untouched
mkdir -p "$PROJ/.claude/rules"
echo "# my own rule" > "$PROJ/.claude/rules/mine.md"
"$KIT/bin/kit" sync >/dev/null
[ -f "$PROJ/.claude/rules/mine.md" ] || fail "kit sync deleted a hand-written project rule"

"$KIT/bin/kit" status >/dev/null || fail "kit status errored"

"$KIT/bin/kit" remove remote-compute >/dev/null
grep -qx "remote-compute" "$PROJ/.claude/kit-rules" 2>/dev/null && fail "kit remove left the manifest entry"
[ -e "$PROJ/.claude/rules/kit/remote-compute.md" ] && fail "kit remove left the symlink"

# stale manifest entry (rule deleted from kit) must be reported, not crash sync
printf 'ghost-rule\n' >> "$PROJ/.claude/kit-rules"
out="$("$KIT/bin/kit" sync 2>&1)"
grep -q "ghost-rule" <<<"$out" || fail "kit sync did not report a stale manifest entry"

# AGENTS.md without CLAUDE.md: Claude Code reads CLAUDE.md only, so such a project's
# instructions never arrive. Measured 2026-09-03: four projects on this machine were in
# that state, one with 332 sessions and 0 observed AGENTS.md loads.
#
# NB the same trap as line 43 — CAPTURE the output, never pipe kit into `grep -q`. On a
# match grep closes the pipe, kit takes SIGPIPE, and `set -o pipefail` makes the pipeline
# nonzero. For a `|| fail` assertion that is a false failure; for a `&& fail` assertion it
# is a false PASS, which is worse. (Written, then violated immediately, 2026-09-03.)
HINT='AGENTS.md but no CLAUDE.md'
status_in() { out="$(cd "$1" && "$KIT/bin/kit" status 2>&1)"; }

A="$TMP/agents-only"; mkdir -p "$A"; printf '# guide\n' > "$A/AGENTS.md"
status_in "$A"; case "$out" in *"$HINT"*) ;; *) fail "status did not hint on AGENTS.md-only";; esac

B="$TMP/both"; mkdir -p "$B"; printf '# g\n' > "$B/AGENTS.md"; printf '@AGENTS.md\n' > "$B/CLAUDE.md"
status_in "$B"; case "$out" in *"$HINT"*) fail "status hinted when CLAUDE.md exists";; esac

C="$TMP/nested"; mkdir -p "$C/.claude"; printf '# g\n' > "$C/AGENTS.md"; printf 'x\n' > "$C/.claude/CLAUDE.md"
status_in "$C"; case "$out" in *"$HINT"*) fail "status hinted when .claude/CLAUDE.md exists";; esac

D="$TMP/neither"; mkdir -p "$D"
status_in "$D"; case "$out" in *"$HINT"*) fail "status hinted on a project with no AGENTS.md";; esac

# ⭐ the suggested fix must be copy-pasteable AND must actually silence the hint. A hint
# whose command does not work is worse than no hint: it spends the reader's attention and
# leaves them believing it is handled.
E="$TMP/applied"; mkdir -p "$E"; printf '# g\n' > "$E/AGENTS.md"
status_in "$E"
suggested="$(printf '%s\n' "$out" | sed -n "s/^ *\(echo '@AGENTS.md' > CLAUDE.md\) *$/\1/p")"
[ -n "$suggested" ] || fail "status did not print a copy-pasteable fix"
(cd "$E" && eval "$suggested")
[ -f "$E/CLAUDE.md" ]                || fail "the suggested fix did not create CLAUDE.md"
[ ! -L "$E/CLAUDE.md" ]              || fail "the suggested fix made a symlink (breaks on Windows)"
grep -qx '@AGENTS.md' "$E/CLAUDE.md" || fail "the suggested fix wrote the wrong content"
status_in "$E"; case "$out" in *"$HINT"*) fail "the hint survived its own fix";; esac

# every shipped skill must stay routable: a description the model can select on, and
# description + when_to_use under the 1,536-char listing cap (beyond that it is truncated).
python3 - "$KIT" <<'PYEOF' || fail "skill frontmatter check failed"
import pathlib, re, sys
kit = pathlib.Path(sys.argv[1])
bad = 0
files = list((kit / "skills").glob("*/SKILL.md")) + list((kit / "codex" / "skills").glob("*/SKILL.md"))
for f in sorted(files):
    m = re.match(r"---\n(.*?)\n---\n", f.read_text(), re.S)
    fm = m.group(1) if m else ""
    desc = (re.search(r"^description:\s*(.*)$", fm, re.M) or [None, ""])[1]
    wtu = (re.search(r"^when_to_use:\s*(.*)$", fm, re.M) or [None, ""])[1]
    if not desc.strip():
        print(f"  {f.parent.name}: empty description — routing falls back to the first paragraph"); bad += 1
    if len(desc) + len(wtu) > 1536:
        print(f"  {f.parent.name}: description+when_to_use = {len(desc)+len(wtu)} > 1536, truncated in the listing"); bad += 1
sys.exit(1 if bad else 0)
PYEOF

[ "$fails" -eq 0 ] && echo "kit: ALL PASS" || echo "kit: FAILURES"
exit "$fails"
