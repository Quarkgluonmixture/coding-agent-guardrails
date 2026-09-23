#!/usr/bin/env bash
# Codex adapter for git-guard. Codex PreToolUse cannot return "ask", so ASK-tier
# commands fail closed until the user explicitly authorizes the auditable bypass.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_KIT_HOOK_HOST=codex exec "$HERE/git-guard.sh"
