#!/usr/bin/env bash
# assets.sh — the single source of truth for "what does this kit ship, and is it on?".
# Sourced by both bin/kit and install.sh; duplicating this logic in the installer is
# exactly the drift this kit exists to prevent.
#
# Defaults: rules/global, skills, agents and hooks are ON; rules/optin is OFF.
# kit.conf records only the EXCEPTIONS, so adding a new asset never requires a config
# edit, and the file is committed — the same switches on every machine.
#
# Requires KIT_ROOT to be set before sourcing.

GLOBAL_RULES="${KIT_ROOT}/rules/global"
OPTIN_RULES="${KIT_ROOT}/rules/optin"
CONF="${KIT_ROOT}/kit.conf"

# one line per asset: "<kind>\t<name>\t<default-state>"
asset_registry() {
  local f d
  for f in "${GLOBAL_RULES}"/*.md;    do [ -f "$f" ] && printf 'rule\t%s\ton\n'  "$(basename "$f" .md)"; done
  for f in "${OPTIN_RULES}"/*.md;     do [ -f "$f" ] && printf 'rule\t%s\toff\n' "$(basename "$f" .md)"; done
  for d in "${KIT_ROOT}"/skills/*/;   do [ -d "$d" ] && printf 'skill\t%s\ton\n' "$(basename "$d")"; done
  for f in "${KIT_ROOT}"/agents/*.md; do [ -f "$f" ] && printf 'agent\t%s\ton\n' "$(basename "$f" .md)"; done
  # Hook adapters/helpers are implementation details, not separate switches. Keep the
  # logical registry explicit so adding a host wrapper never creates a phantom asset.
  [ -f "${KIT_ROOT}/hooks/git-guard.sh" ] && printf 'hook\tgit-guard\ton\n'
  [ -f "${KIT_ROOT}/hooks/instructions-loaded.sh" ] && printf 'hook\tinstructions-loaded\ton\n'
  # 2026-09-03: two Claude-only hooks (no Codex prompt-level / post-tool adapter yet).
  [ -f "${KIT_ROOT}/hooks/wrap-up-trigger.py" ] && printf 'hook\twrap-up-trigger\ton\n'
  [ -f "${KIT_ROOT}/hooks/gotchas-contract.py" ] && printf 'hook\tgotchas-contract\ton\n'
  return 0
}

# A logical asset may have a host-specific representation. Empty output means the
# asset intentionally does not install on that host (not a missing source).
codex_skill_source() {
  case "$1" in
    cross-ai) printf '%s\n' "${KIT_ROOT}/codex/skills/cross-ai" ;;
    memory-audit|skill-creator) return 1 ;;
    *) printf '%s\n' "${KIT_ROOT}/skills/$1" ;;
  esac
}

codex_agent_source() {
  case "$1" in
    executor) printf '%s\n' "${KIT_ROOT}/codex/agents/executor.toml" ;;
    *) return 1 ;;
  esac
}

# NB: no `exit` in these awk programs. Exiting early closes the pipe and SIGPIPEs
# asset_registry, which under `set -o pipefail` kills the caller with status 141 —
# silently, since nothing is printed. Read all input; keep the first match instead.
asset_kind() { asset_registry | awk -F'\t' -v n="$1" '$2==n && !f {print $1; f=1}'; }
asset_default() { asset_registry | awk -F'\t' -v k="$1" -v n="$2" '$1==k && $2==n && !f {print $3; f=1}'; }

# on | off | missing
asset_state() {
  local kind="$1" name="$2" override default
  default="$(asset_registry | awk -F'\t' -v k="$kind" -v n="$name" '$1==k && $2==n && !f {print $3; f=1}')"
  [ -n "$default" ] || { echo missing; return 0; }
  if [ -f "${CONF}" ]; then
    override="$(awk -v k="$kind" -v n="$name" \
      '$1 ~ /^(on|off)$/ && $2 == k":"n {v=$1} END {if (v) print v}' "${CONF}")"
    [ -n "$override" ] && { echo "$override"; return 0; }
  fi
  echo "$default"
}

conf_set() {
  local kind="$1" name="$2" state="$3" tmp default
  # Setting something back to its default removes the line rather than recording it.
  # kit.conf must stay a list of EXCEPTIONS; if it drifts into a full inventory, adding a
  # new asset silently means "not listed, therefore off".
  default="$(asset_registry | awk -F'\t' -v k="$kind" -v n="$name" '$1==k && $2==n && !f {print $3; f=1}')"
  if [ ! -f "${CONF}" ]; then
    cat > "${CONF}" <<'HDR'
# claude-kit switches — only the EXCEPTIONS to the defaults live here.
# Defaults: rules/global + skills + agents + hooks = on; rules/optin = off.
# Edit with `kit config on|off <name>`; install.sh applies it (links or unlinks).
HDR
  fi
  tmp="${CONF}.tmp"
  awk -v k="$kind" -v n="$name" '!($1 ~ /^(on|off)$/ && $2 == k":"n)' "${CONF}" > "$tmp"
  [ "$state" = "$default" ] || printf '%-3s %s:%s\n' "$state" "$kind" "$name" >> "$tmp"
  mv "$tmp" "${CONF}"
}

# Remove a link we own, and report whether anything was actually removed. Returning
# success for "there was nothing there" made install.sh announce "link removed" on a
# fresh machine where the link had never existed.
# Never touches a real file or a link pointing outside the kit — a user's own
# skill/rule sitting at that path is not ours to delete.
unlink_if_ours() {
  local dest="$1" target
  [ -L "$dest" ] || return 1
  target="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$dest" 2>/dev/null || echo "")"
  case "$target" in
    "$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "${KIT_ROOT}")"/*) rm -f "$dest"; return 0 ;;
  esac
  return 1
}

# asset_dest <host> <kind> <name> — where this logical asset installs on that host.
# Empty output = it intentionally does not install there (not an error).
#
# ⭐ One source for the destination path. install.sh used to spell these inline while
# `kit status` and `kit doctor` re-derived them by walking directories — and because
# the walkers enumerated rules/global/ instead of the registry, they were blind to
# an opt-in rule turned on machine-wide (`kit config on cross-ai-review`): if its
# link was missing, doctor never looked, and reported green.
asset_dest() {
  local host="$1" kind="$2" name="$3"
  case "${host}:${kind}" in
    claude:skill) printf '%s\n' "$HOME/.claude/skills/$name" ;;
    claude:rule)  printf '%s\n' "$HOME/.claude/rules/$name.md" ;;
    claude:agent) printf '%s\n' "$HOME/.claude/agents/$name.md" ;;
    codex:skill)  codex_skill_source "$name" >/dev/null 2>&1 && printf '%s\n' "$HOME/.agents/skills/$name" ;;
    codex:agent)  codex_agent_source "$name" >/dev/null 2>&1 && printf '%s\n' "$HOME/.codex/agents/$name.toml" ;;
    codex:rule)   : ;;   # injected by the SessionStart hook, never materialised
    *) : ;;
  esac
  return 0
}

# asset_verdict <host> <kind> <name> — the four cells of declared-vs-installed.
# Prints one of: on-ok | on-missing | off-ok | off-stale | off-foreign | n/a
# `off-stale` is the cell everyone forgets: `kit config off X` must UNLINK, so a
# surviving link of ours is a real failure, not a harmless leftover. A link that is
# NOT ours at that path is `off-foreign` — a warning, since we must not delete it.
asset_verdict() {
  local host="$1" kind="$2" name="$3" state dest target want
  dest="$(asset_dest "$host" "$kind" "$name")"
  [ -n "$dest" ] || { echo "n/a"; return 0; }
  state="$(asset_state "$kind" "$name")"
  case "$kind" in
    skill) want="${KIT_ROOT}/skills/$name" ;;
    rule)  want="${KIT_ROOT}/rules/global/$name.md"
           [ -f "$want" ] || want="${KIT_ROOT}/rules/optin/$name.md" ;;
    agent) want="${KIT_ROOT}/agents/$name.md" ;;
  esac
  if [ "$host" = codex ]; then
    case "$kind" in
      skill) want="$(codex_skill_source "$name")" ;;
      agent) want="$(codex_agent_source "$name")" ;;
    esac
  fi
  target=""
  [ -L "$dest" ] && target="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$dest" 2>/dev/null || echo "")"
  if [ "$state" = on ]; then
    if [ -n "$target" ] && [ "$target" = "$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$want" 2>/dev/null || echo "")" ]; then
      echo "on-ok"
    else
      echo "on-missing"
    fi
  else
    if [ ! -e "$dest" ] && [ ! -L "$dest" ]; then
      echo "off-ok"
    elif [ -n "$target" ] && case "$target" in "$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "${KIT_ROOT}")"/*) true ;; *) false ;; esac; then
      echo "off-stale"
    else
      echo "off-foreign"
    fi
  fi
}

# ── hooks: same verdict vocabulary, a different notion of "installed" ────────
# A hook is not a symlink at a path; it is a REGISTRATION inside the host's settings
# JSON. It was therefore outside asset_verdict entirely, and doctor counted it with
# bespoke logic while rules/skills/agents had six states — so `kit config off
# <hook>` had no state model to be checked against.
#
# hook_script <host> <name> — the script whose registration we look for; empty = the
# hook intentionally does not exist on that host.
hook_script() {
  local host="$1" name="$2"
  case "${host}:${name}" in
    claude:git-guard)           printf 'hooks/git-guard.sh\n' ;;
    claude:instructions-loaded) printf 'hooks/instructions-loaded.sh\n' ;;
    claude:wrap-up-trigger)     printf 'hooks/wrap-up-trigger.py\n' ;;
    claude:gotchas-contract)    printf 'hooks/gotchas-contract.py\n' ;;
    # Codex: git-guard has an adapter; codex-rules.py is both the injector and the
    # observation channel, i.e. the Codex representation of instructions-loaded.
    codex:git-guard)            printf 'hooks/codex-git-guard.sh\n' ;;
    codex:instructions-loaded)  printf 'hooks/codex-rules.py\n' ;;
    # 2026-09-03: no Codex adapter yet for the two prompt/post-tool hooks.
    codex:wrap-up-trigger|codex:gotchas-contract) : ;;
    *) : ;;
  esac
  return 0
}

hook_settings_file() {
  case "$1" in
    claude) printf '%s\n' "$HOME/.claude/settings.json" ;;
    codex)  printf '%s\n' "$HOME/.codex/hooks.json" ;;
    *) : ;;
  esac
  return 0
}

# hook_events <host> <name> — the events this hook MUST be registered on, exactly once
# each. ⭐ A count is the wrong predicate: codex:instructions-loaded is registered
# TWICE by design (SessionStart + SubagentStart), so counting called correct state
# "duplicated"; and a count cannot see a hook registered on the WRONG event at all.
hook_events() {
  local host="$1" name="$2"
  case "${host}:${name}" in
    claude:git-guard)           printf 'PreToolUse\n' ;;
    claude:instructions-loaded) printf 'InstructionsLoaded\n' ;;
    claude:wrap-up-trigger)     printf 'UserPromptSubmit\n' ;;
    claude:gotchas-contract)    printf 'PostToolBatch\n' ;;
    codex:git-guard)            printf 'PreToolUse\n' ;;
    codex:instructions-loaded)  printf 'SessionStart\nSubagentStart\n' ;;
    *) : ;;
  esac
  return 0
}

# Prints one "<event> <count>" line per event where this hook's script is registered.
hook_registrations() {
  local host="$1" name="$2" script settings
  script="$(hook_script "$host" "$name")"
  [ -n "$script" ] || return 0
  settings="$(hook_settings_file "$host")"
  [ -f "$settings" ] || return 0
  python3 - "$settings" "$script" <<'PY'
import json, sys
# Windows python writes CRLF in text mode; the caller compares this output byte-for-byte
# against LF `want` lines, so a correct two-event registration read as on-wrong-events.
sys.stdout.reconfigure(newline="\n")
try:
    with open(sys.argv[1], encoding="utf-8") as fh:
        data = json.load(fh)
except (OSError, ValueError):
    print("__UNREADABLE__ 1")       # ⛔ not the same thing as "no registrations"
    raise SystemExit(0)
needle = sys.argv[2]
counts = {}
def walk(node, event):
    if isinstance(node, dict):
        cmd = node.get("command")
        if isinstance(cmd, str) and needle in cmd and event:
            counts[event] = counts.get(event, 0) + 1
        for k, v in node.items():
            walk(v, k if event is None else event)
    elif isinstance(node, list):
        for v in node:
            walk(v, event)
walk(data.get("hooks", {}), None)
for ev in sorted(counts):
    print(ev, counts[ev])
PY
}

# on-ok | on-missing | on-wrong-events | off-ok | off-stale | settings-unreadable | n/a
hook_verdict() {
  local host="$1" name="$2" state want got
  [ -n "$(hook_script "$host" "$name")" ] || { echo "n/a"; return 0; }
  state="$(asset_state hook "$name")"
  got="$(hook_registrations "$host" "$name")"
  case "$got" in *__UNREADABLE__*) echo "settings-unreadable"; return 0 ;; esac
  want="$(hook_events "$host" "$name" | sed 's/$/ 1/')"
  if [ "$state" = on ]; then
    if [ "$got" = "$want" ]; then echo "on-ok"
    elif [ -z "$got" ]; then echo "on-missing"
    else echo "on-wrong-events"; fi
  else
    [ -z "$got" ] && echo "off-ok" || echo "off-stale"
  fi
}

# selected_rules <project_dir> — THE canonical answer to "which rules apply here".
# Machine-wide state (kit.conf over the registry defaults) plus this project's opt-in
# manifest. Prints "<name> <tier>" per line, sorted.
#
# ⭐ This exists because the answer was being derived three times: install.sh linked
# by directory, `kit state` built its expected-set from whichever links happened to
# exist (so an opt-in rule switched on machine-wide was never expected, and a missing
# link quietly removed a rule from the expected set instead of being reported), and
# codex-rules.py re-derived the whole thing in python. Same question, three answers.
selected_rules() {
  local project="${1:-.}" f n manifest_file
  manifest_file="${project}/.claude/kit-rules"
  {
    for f in "${GLOBAL_RULES}"/*.md; do
      [ -f "$f" ] || continue
      n="$(basename "$f" .md)"
      [ "$(asset_state rule "$n")" = on ] && printf '%s global\n' "$n"
    done
    for f in "${OPTIN_RULES}"/*.md; do
      [ -f "$f" ] || continue
      n="$(basename "$f" .md)"
      if [ "$(asset_state rule "$n")" = on ]; then
        printf '%s optin\n' "$n"
      elif [ -f "$manifest_file" ] && grep -qx "[[:space:]]*$n[[:space:]]*" "$manifest_file" 2>/dev/null; then
        printf '%s optin\n' "$n"
      fi
    done
  } | sort
  return 0
}
