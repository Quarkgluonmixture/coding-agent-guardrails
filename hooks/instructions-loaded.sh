#!/usr/bin/env bash
# kit-summary: 记录哪些指令文件**真的**加载了，`kit state claude` 的地面真相来源
# instructions-loaded.sh — InstructionsLoaded hook: record which instruction files
# ACTUALLY loaded, so `kit state` can report ground truth instead of "what install.sh
# believes it linked".
#
# The distinction is the whole point: the kit spent a year believing six rules were
# available to projects while zero projects had ever opted in. A manifest, a symlink
# and a doctor check all describe intent; only this event describes what reached the
# model's context.
#
# The event fires once per loaded file (session_start, nested_traversal, path_glob_match,
# include, compact) and carries: session_id, transcript_path, cwd, file_path,
# memory_type, load_reason. Notably file_path is already resolved THROUGH symlinks,
# so a kit-managed rule shows up as its path inside the kit checkout.
#
# Design: append-only single log, no parsing at write time. This fires several times
# during startup, so it must stay a few milliseconds — filtering by project happens
# later, in `kit state`. The hook cannot block or modify anything (exit code ignored).
#
# Registered globally by install.sh into ~/.claude/settings.json (hooks.InstructionsLoaded).

LOG="$HOME/.claude/kit-state/instructions.jsonl"
mkdir -p "$HOME/.claude/kit-state" 2>/dev/null || exit 0

payload="$(cat | tr -d '\n\r')"
[ -n "$payload" ] || exit 0
case "$payload" in '{'*) : ;; *) exit 0 ;; esac   # ignore anything that isn't a JSON object

printf '{"ts":"%s","event":%s}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$payload" >> "$LOG"

# Keep the log bounded. Appends are small enough to be atomic; the trim is best-effort
# and racy across concurrent sessions, which is acceptable for a diagnostic log.
lines="$(wc -l < "$LOG" 2>/dev/null || echo 0)"
if [ "${lines:-0}" -gt 4000 ]; then
  tail -n 2000 "$LOG" > "$LOG.tmp" 2>/dev/null && mv "$LOG.tmp" "$LOG"
fi
exit 0
