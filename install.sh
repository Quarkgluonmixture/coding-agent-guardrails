#!/usr/bin/env bash
# install.sh — machine-level setup for claude-kit. Safe to re-run after `git pull`.
#
#   ./install.sh                         # install adapters for Claude + Codex
#   ./install.sh --target claude         # Claude only
#   ./install.sh --target codex          # Codex only
#
# Canonical rules and shared skills stay in this repo. Each host gets only the thin
# representation it understands: Claude links rules directly; Codex injects the same
# rule files from SessionStart/SubagentStart hooks.

set -euo pipefail
KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/assets.sh
. "$KIT_ROOT/lib/assets.sh"
say() { printf '%s\n' "$*"; }

TARGET=all
while [ $# -gt 0 ]; do
  case "$1" in
    --target)
      [ $# -ge 2 ] || { echo "install.sh: --target requires claude, codex, or all" >&2; exit 2; }
      TARGET="$2"; shift 2 ;;
    --target=*) TARGET="${1#*=}"; shift ;;
    -h|--help)
      sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "install.sh: unknown argument: $1" >&2; exit 2 ;;
  esac
done
case "$TARGET" in claude|codex|all) : ;; *) echo "install.sh: bad target: $TARGET" >&2; exit 2 ;; esac
wants() { [ "$TARGET" = all ] || [ "$TARGET" = "$1" ]; }

# Every installed hook/project link executes through this stable path. Refuse a real
# collision before making any HOME changes; "warn and continue" could wire untrusted code.
if [ "$KIT_ROOT" != "$HOME/claude-kit" ] && [ -e "$HOME/claude-kit" ] && [ ! -L "$HOME/claude-kit" ]; then
  echo "claude-kit: ~/claude-kit is occupied by a real directory/file; no changes made." >&2
  echo "Confirm and move it manually, then rerun install.sh." >&2
  exit 1
fi

# Back up anything at the exact destination that is not already the desired link. This
# includes unrelated/dangling symlinks: replacing one silently is still data loss.
link_into() {
  local src="$1" dest="$2" kind="$3" name="$4" backup_root="$5"
  local current="" wanted
  wanted="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$src")"
  if [ -L "$dest" ]; then
    current="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$dest")"
  fi
  if { [ -e "$dest" ] || [ -L "$dest" ]; } && [ "$current" != "$wanted" ]; then
    mkdir -p "$backup_root"
    local bak
    bak="$backup_root/$kind-$name.$(date +%s)"
    mv "$dest" "$bak"
    say "      (existing $name backed up → $bak)"
  fi
  ln -sfn "$src" "$dest"
}

apply_asset() {
  local kind="$1" name="$2" src="$3" dest="$4" backup_root="$5"
  if [ "$(asset_state "$kind" "$name")" = on ]; then
    link_into "$src" "$dest" "$kind" "$name" "$backup_root"
    say "      ✓ $dest"
  elif unlink_if_ours "$dest"; then
    say "      · $name off — existing link removed"
  elif [ "$(asset_default "$kind" "$name")" = on ]; then
    say "      · $name off (kit.conf)"
  fi
}

say "claude-kit setup — target: $TARGET · repo: $KIT_ROOT"

# Shared entrypoint and stable alias.
chmod +x "$KIT_ROOT/bin/kit" "$KIT_ROOT"/skills/*/*.sh "$KIT_ROOT"/hooks/*.sh \
  "$KIT_ROOT"/hooks/*.py 2>/dev/null || true
mkdir -p "$HOME/.local/bin"
link_into "$KIT_ROOT/bin/kit" "$HOME/.local/bin/kit" command kit "$HOME/.local/backups"
say "[shared] linked ~/.local/bin/kit → $KIT_ROOT/bin/kit"
case ":$PATH:" in
  *":$HOME/.local/bin:"*) : ;;
  *) say "      ⚠️  ~/.local/bin 不在 PATH，请加： export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
esac

if [ "$KIT_ROOT" = "$HOME/claude-kit" ]; then
  say "      ✓ clone already at ~/claude-kit"
elif [ -L "$HOME/claude-kit" ]; then
  alias_target="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$HOME/claude-kit")"
  if [ "$alias_target" != "$KIT_ROOT" ]; then
    mkdir -p "$HOME/.local/backups"
    alias_backup="$HOME/.local/backups/claude-kit-alias.$(date +%s)"
    mv "$HOME/claude-kit" "$alias_backup"
    say "      (existing ~/claude-kit symlink backed up → $alias_backup)"
  fi
  ln -sfn "$KIT_ROOT" "$HOME/claude-kit"
  say "      ✓ ~/claude-kit → $KIT_ROOT"
elif [ ! -e "$HOME/claude-kit" ]; then
  ln -s "$KIT_ROOT" "$HOME/claude-kit"
  say "      ✓ ~/claude-kit → $KIT_ROOT"
else
  say "      ✗ ~/claude-kit alias preflight invariant failed"
  exit 1
fi

install_claude() {
  local d f name agents_dir_was_new=0
  say "[claude] linking skills, rules, and agents…"
  mkdir -p "$HOME/.claude/skills" "$HOME/.claude/rules"
  for d in "$KIT_ROOT"/skills/*/; do
    [ -d "$d" ] || continue
    name="$(basename "$d")"
    apply_asset skill "$name" "${d%/}" "$(asset_dest claude skill "$name")" "$HOME/.claude/backups"
  done
  for f in "$KIT_ROOT"/rules/global/*.md "$KIT_ROOT"/rules/optin/*.md; do
    [ -f "$f" ] || continue
    name="$(basename "$f" .md)"
    apply_asset rule "$name" "$f" "$(asset_dest claude rule "$name")" "$HOME/.claude/backups"
  done
  [ -d "$HOME/.claude/agents" ] || agents_dir_was_new=1
  mkdir -p "$HOME/.claude/agents"
  for f in "$KIT_ROOT"/agents/*.md; do
    [ -f "$f" ] || continue
    name="$(basename "$f" .md)"
    apply_asset agent "$name" "$f" "$(asset_dest claude agent "$name")" "$HOME/.claude/backups"
  done
  if [ "$agents_dir_was_new" = 1 ]; then
    say "      ⚠️  ~/.claude/agents 是本次新建的；正在跑的 Claude session 需重开才会发现 agent。"
  fi

  say "[claude] merging hooks into ~/.claude/settings.json…"
  mkdir -p "$HOME/.claude"
  python3 - "$HOME/.claude/settings.json" "$(asset_state hook git-guard)" "$(asset_state hook instructions-loaded)" \
    "$(asset_state hook wrap-up-trigger)" "$(asset_state hook gotchas-contract)" <<'PY'
import json, os, sys

path, guard_state, il_state, wu_state, gc_state = sys.argv[1:]
hooks = [
    ("PreToolUse", "Bash", "$HOME/claude-kit/hooks/git-guard.sh", "git-guard", guard_state),
    ("InstructionsLoaded", "session_start|nested_traversal|path_glob_match|include",
     "$HOME/claude-kit/hooks/instructions-loaded.sh", "instructions-loaded", il_state),
    # 2026-09-03. wrap-up-trigger: an explicit short 收尾/存档/交接/接手 instruction puts
    # "invoke the checkpoint skill now" into context (UserPromptSubmit stdout is context).
    # gotchas-contract: a NEW GOTCHAS entry must declare `闸: <path>` or `闸: 无 — <reason>`.
    ("UserPromptSubmit", "", "$HOME/claude-kit/hooks/wrap-up-trigger.py", "wrap-up-trigger", wu_state),
    # PostToolBatch, not PostToolUse: it fires ONCE after a whole batch of parallel
    # calls resolves, before the next model call, so the hook cannot race itself over
    # the same state file. It has no matcher (measured: always fires), so the script
    # filters on tool_calls[] itself. exit 2 still stops the loop. Verified on Claude
    # Code 2.1.261 by registering a probe hook and observing the event + its payload.
    ("PostToolBatch", "", "$HOME/claude-kit/hooks/gotchas-contract.py", "gotchas-contract", gc_state),
]
d = {}
if os.path.exists(path):
    with open(path) as handle:
        d = json.load(handle)

changed = False
for event, matcher, command, label, state in hooks:
    # ⭐ Strip this command from EVERY event, not just the one we are about to write.
    # Cleaning only the target event left a copy registered under some OTHER event
    # alive forever — so a hook could be present but bound to an event it never fires
    # on, and re-running the installer would not fix it. (Found 2026-09-05 by the
    # per-event hook verdict; a registration COUNT cannot see this at all.)
    d.setdefault("hooks", {})
    for ev in list(d["hooks"]):
        groups_any = d["hooks"][ev]
        for group in list(groups_any):
            before = len(group.get("hooks", []))
            group["hooks"] = [h for h in group.get("hooks", []) if h.get("command") != command]
            if len(group["hooks"]) != before:
                changed = True
            if not group["hooks"]:
                groups_any.remove(group)
        if not groups_any and ev != event:
            d["hooks"].pop(ev, None)
    groups = d["hooks"].setdefault(event, [])
    if state == "on":
        groups.append({"matcher": matcher, "hooks": [{"type": "command", "command": command}]})
        changed = True
        print(f"      ✓ {label} hook registered exactly once")
    else:
        print(f"      · {label} off (kit.conf)")
    if not groups:
        d["hooks"].pop(event, None)
if not d.get("hooks"):
    d.pop("hooks", None)
if changed or not os.path.exists(path):
    with open(path, "w") as handle:
        json.dump(d, handle, indent=2, ensure_ascii=False)
        handle.write("\n")
PY
}

install_codex() {
  local d f name src
  say "[codex] linking supported skills and agents…"
  mkdir -p "$HOME/.agents/skills" "$HOME/.codex/agents" "$HOME/.codex/backups"
  for d in "$KIT_ROOT"/skills/*/; do
    [ -d "$d" ] || continue
    name="$(basename "$d")"
    if src="$(codex_skill_source "$name")"; then
      [ -e "$src" ] || { say "      ✗ missing Codex source for skill $name: $src"; return 1; }
      apply_asset skill "$name" "$src" "$(asset_dest codex skill "$name")" "$HOME/.codex/backups"
    fi
  done
  for f in "$KIT_ROOT"/agents/*.md; do
    [ -f "$f" ] || continue
    name="$(basename "$f" .md)"
    if src="$(codex_agent_source "$name")"; then
      [ -f "$src" ] || { say "      ✗ missing Codex source for agent $name: $src"; return 1; }
      apply_asset agent "$name" "$src" "$(asset_dest codex agent "$name")" "$HOME/.codex/backups"
    fi
  done

  say "[codex] merging hooks into ~/.codex/hooks.json…"
  # Windows: Codex runs hook commands through the session shell (PowerShell), where a bare
  # `$HOME/claude-kit/hooks/x.sh` is a PARSE ERROR → "hook failure" → the tool call proceeds
  # (fail-open) and rules are never injected. `commandWindows` re-enters Git Bash and
  # forwards the real exit code (2 = deny; pwsh would otherwise flatten it to 1).
  local win_bash=""
  case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) win_bash="$(cygpath -w "$(command -v bash)")" ;; esac
  KIT_CODEX_WIN_BASH="$win_bash" python3 - "$HOME/.codex/hooks.json" "$(asset_state hook git-guard)" "$(asset_state hook instructions-loaded)" <<'PY'
import json, os, sys

win_bash = os.environ.get("KIT_CODEX_WIN_BASH", "")

path, guard_state, rules_state = sys.argv[1:]
entries = [
    ("PreToolUse", "^Bash$", "$HOME/claude-kit/hooks/codex-git-guard.sh",
     "git-guard", guard_state, {}),
    ("SessionStart", "startup|resume|clear|compact", "$HOME/claude-kit/hooks/codex-rules.py",
     "instructions-loaded", rules_state, {"additionalContextLimit": 12000}),
    ("SubagentStart", ".*", "$HOME/claude-kit/hooks/codex-rules.py",
     "instructions-loaded", rules_state, {"additionalContextLimit": 12000}),
]
d = {}
if os.path.exists(path):
    with open(path) as handle:
        d = json.load(handle)
d.setdefault("description", "User hooks, including claude-kit cross-host adapters.")

for event, matcher, command, label, state, extra in entries:
    groups = d.setdefault("hooks", {}).setdefault(event, [])
    for group in list(groups):
        group["hooks"] = [h for h in group.get("hooks", []) if h.get("command") != command]
        if not group["hooks"]:
            groups.remove(group)
    if state == "on":
        handler = {"type": "command", "command": command, **extra}
        if win_bash:
            handler["commandWindows"] = f"& '{win_bash}' -lc '\"{command}\"'; exit $LASTEXITCODE"
        groups.append({"matcher": matcher, "hooks": [handler]})
        print(f"      ✓ {label} / {event} registered exactly once")
    else:
        print(f"      · {label} / {event} off (kit.conf)")
    if not groups:
        d["hooks"].pop(event, None)
if not d.get("hooks"):
    d.pop("hooks", None)
with open(path, "w") as handle:
    json.dump(d, handle, indent=2, ensure_ascii=False)
    handle.write("\n")
PY
  say "      ⚠️  Codex 会对新或变更的非托管 hook 要求 trust；重开 Codex 后运行 /hooks 审核。"
}

wants claude && install_claude
wants codex && install_codex

cat <<EOF

Done. target=$TARGET

  kit list
  kit add remote-compute     # 项目 opt-in 清单；Claude 用 symlink，Codex 下次 session 由 hook 读取
  kit sync                   # 重建 Claude 项目链接（Codex 无需物化）
  kit status
  kit state claude|codex
  kit doctor
EOF
