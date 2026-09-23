#!/usr/bin/env bash
# codex_model.sh — resolve which Codex model /cross-ai should use, without a hand-edited pin.
#
# WHY: the skill used to hard-code `-m gpt-5.6-sol`. Every time OpenAI shipped a
# generation (5.5 → 5.6-sol) the pin had to be edited by hand, and until someone
# noticed, cross-AI was quietly reviewing with last year's model.
#
# Codex already keeps a server-fetched model list at ~/.codex/models_cache.json
# (refreshed whenever codex runs, so it is at worst one run stale). Each entry
# carries a `priority` — 1 = current flagship. We read that instead of guessing.
#
# Resolution order (first hit wins):
#   1. $CROSS_AI_CODEX_MODEL          — explicit override; use it to re-run an old
#                                       audit against the exact model it was done with
#   2. ~/.codex/models_cache.json     — lowest `priority` among visible, API-capable models
#   3. ~/.codex/config.toml           — whatever the user's own codex default is
#   4. (empty)                        — caller omits -m and lets codex decide
#
# Effort: $CROSS_AI_CODEX_EFFORT, else xhigh if the chosen model supports it, else high.
# NOTE: newer models also expose `max` / `ultra` above xhigh. Not auto-selected —
# that is a cost/latency call, set CROSS_AI_CODEX_EFFORT if you want them.
#
# Never fails the caller: on any problem it degrades to the next source and, in the
# worst case, prints empty values. Whatever it picks is announced on stderr, so an
# auto-resolved model can never change the reviewer *silently* — the point of the
# original pin was a controlled variable, and this keeps that while dropping the chore.
#
# Usage:
#   eval "$(~/.claude/skills/cross-ai/codex_model.sh)"
#   codex exec -m "$CODEX_MODEL" -c model_reasoning_effort="$CODEX_EFFORT" ...
#
# Env:
#   CROSS_AI_CODEX_MODEL   — force a model slug
#   CROSS_AI_CODEX_EFFORT  — force an effort (low|medium|high|xhigh|max|ultra)
#   CODEX_HOME             — codex state dir (default: ~/.codex)

set -uo pipefail

CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
CACHE="$CODEX_HOME/models_cache.json"
CONFIG="$CODEX_HOME/config.toml"

model="${CROSS_AI_CODEX_MODEL:-}"
effort="${CROSS_AI_CODEX_EFFORT:-}"
source_note=""
efforts=""

# --- 1. explicit override ---------------------------------------------------
if [[ -n "$model" ]]; then
  source_note="CROSS_AI_CODEX_MODEL override"
fi

# --- 2. codex's own model cache --------------------------------------------
if [[ -z "$model" && -r "$CACHE" ]] && command -v python3 >/dev/null 2>&1; then
  read -r model efforts fetched < <(python3 - "$CACHE" <<'PY' 2>/dev/null || true
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    ms = [m for m in d.get("models", [])
          if m.get("visibility") == "list" and m.get("supported_in_api")
          and isinstance(m.get("priority"), int) and m.get("slug")]
    if ms:
        m = min(ms, key=lambda m: m["priority"])
        efforts = ",".join(e.get("effort", "") for e in m.get("supported_reasoning_levels", []))
        print(m["slug"], efforts or "-", (d.get("fetched_at") or "-")[:10])
except Exception:
    pass
PY
  ) || true
  [[ -n "${model:-}" ]] && source_note="codex models_cache (fetched ${fetched:-?})"
fi

# --- 3. the user's codex default -------------------------------------------
if [[ -z "${model:-}" && -r "$CONFIG" ]]; then
  model="$(sed -n 's/^[[:space:]]*model[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$CONFIG" | head -1)"
  [[ -n "$model" ]] && source_note="codex config.toml default"
fi

# --- effort -----------------------------------------------------------------
if [[ -z "$effort" ]]; then
  if [[ -z "$efforts" || "$efforts" == "-" ]]; then
    effort="xhigh"                                   # unknown support → skill's documented fallback path
  elif [[ ",$efforts," == *",xhigh,"* ]]; then
    effort="xhigh"
  else
    effort="high"
  fi
fi

if [[ -z "${model:-}" ]]; then
  echo "cross-ai: could not resolve a codex model (no cache, no config) — falling back to codex's built-in default; omit -m" >&2
  source_note="unresolved"
fi

echo "cross-ai: codex model = ${model:-<codex default>} · effort = ${effort} · via ${source_note}" >&2

# stdout is meant for `eval` — keep it to assignments only.
printf 'CODEX_MODEL=%q\n' "${model:-}"
printf 'CODEX_EFFORT=%q\n' "$effort"
