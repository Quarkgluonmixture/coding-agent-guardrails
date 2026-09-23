#!/usr/bin/env bash
# kit-summary: PreToolUse 两档闸 — DENY 不可逆操作，ASK 毁掉未提交工作但属正常工作法的操作
# git-guard.sh — PreToolUse hook (Bash matcher): gate on git operations that destroy
# work which is not yours.
#
# Why a hook and not a rule: the "never `git add -A`" rule was violated twice under
# pressure (personal launchers into a shared repo; 40 in-progress audio sources pushed
# to a public repo). Rules get forgotten mid-flow; a hook doesn't. Concurrency makes it
# worse: with two sessions on one repo, a sweeping operation eats the OTHER session's
# uncommitted work.
#
# TWO TIERS — deliberately. A guard that blocks operations you legitimately use gets
# switched off, and then it protects nothing.
#
#   DENY (exit 2 → Claude sees stderr and must do it another way):
#     git add:    -A / --all / -u / --update (any short cluster, e.g. -Av) / . / ./
#     git commit: -a in any short cluster / --all      (sweeps every tracked modification)
#     git commit: --no-verify / -n                     (bypasses required checks)
#     git clean:  -f / --force                         (deletes untracked files, unrecoverable)
#     git push:   --force / -f                         (rewrites remote history)
#                 …but `--force-with-lease` is ALLOWED — it is the safe form.
#
#   ASK (Claude: permissionDecision:"ask"; Codex: exit 2 until an explicit bypass):
#     git reset --hard                                 (destroys uncommitted work)
#     git checkout . / -- . , git restore .            (same, minus --staged)
#     git stash (create) without an explicit pathspec  (stash A/B is a real workflow here,
#                                                       but bare stash owns the whole tree)
#     git stash clear                                  (drops every stash irrecoverably)
#
# Allows outright: explicit-path add, `git add -p`, `git commit --amend`, `git checkout <branch>`,
# `git restore --staged .`, `git stash push -- <paths>`, `git push --force-with-lease`.
#
# Escape hatch (rare, auditable in the command itself):
#   CLAUDE_KIT_GIT_GUARD_BYPASS=1 git add -A
#
# Registered globally by install.sh into ~/.claude/settings.json (hooks.PreToolUse).

# NB: the hook payload must reach python via env, NOT a pipe — the heredoc already
# occupies python's stdin (a piped payload would be silently discarded → guard no-ops).
GUARD_INPUT=$(cat) python3 - <<'PY'
import json, os, re, sys

try:
    data = json.loads(os.environ.get("GUARD_INPUT") or "{}")
except json.JSONDecodeError:
    sys.exit(0)
cmd = (data.get("tool_input") or {}).get("command", "")
if not cmd:
    sys.exit(0)

# Explicit, auditable escape hatch — the marker rides in the command string itself.
if "CLAUDE_KIT_GIT_GUARD_BYPASS=1" in cmd:
    sys.exit(0)

# Normalize BEFORE matching:
# 1. strip heredoc bodies (commit messages that merely MENTION `git add -A` must not
#    trip the guard — it blocked its own introducing commit this way);
# 2. UNQUOTE single-token quoted strings so `git add "."` / `git add '-A'` can't hide;
# 3. blank remaining (multi-token) quoted strings — prose, -m messages, echo'd docs.
# Known gap, accepted: `bash -c "git add -A"` hides in a multi-token quote; the
# written rule still covers that.
#
# ⛔ POSITIONING — this is a MISTAKE-PREVENTION guardrail, not a security boundary.
# It regex-parses a shell command string, and the gap above is one of several a
# determined caller could walk through. It is highly effective against the thing it
# exists for (an agent's slip under pressure). It must never be reused as an
# AUTHORIZATION boundary for untrusted input — a future runtime that treats "the
# guard did not fire" as "this caller is allowed to do it" is relying on soft
# enforcement to do isolation's job.
cmd = re.sub(r"<<-?\s*'?([A-Za-z_][A-Za-z_0-9]*)'?[\s\S]*?\n\1(?=\s|$)", "\n", cmd)
cmd = re.sub(r"'([^'\s]*)'", r"\1", cmd)
cmd = re.sub(r'"((?:\\.|[^"\\\s])*)"', r"\1", cmd)
cmd = re.sub(r"'[^']*'", "'…'", cmd)
cmd = re.sub(r'"(?:\\.|[^"\\])*"', '"…"', cmd)

# Stay within one shell command segment (don't match across && ; |).
SEG = r"[^|;&\n]*"


def git_verb(verb):
    """A `git … <verb>` occurrence inside one segment (tolerates -C dir, --no-pager…)."""
    return rf"\bgit\b{SEG}\b{verb}\b"


def short_cluster(letter):
    """A short-flag cluster containing `letter` (-f, -fd, -qam…), never a long --flag."""
    return rf"-(?!-)[A-Za-z]*{letter}[A-Za-z]*\b"


# ---------------------------------------------------------------- DENY tier
# -A / -u anywhere in a short-flag cluster, or the long forms.
add_sweep = re.compile(rf"{git_verb('add')}{SEG}\s({short_cluster('A')}|{short_cluster('u')}|--all\b|--update\b)")
add_dot = re.compile(rf"{git_verb('add')}{SEG}\s\.(/)?(\s|$|[;&|])")
# -a anywhere in a short cluster (-a, -am, -av, -qam…) or --all; (?!-) keeps --amend safe.
commit_sweep = re.compile(rf"{git_verb('commit')}{SEG}\s({short_cluster('a')}|--all\b)")
commit_noverify = re.compile(rf"{git_verb('commit')}{SEG}\s(--no-verify\b|{short_cluster('n')})")
clean_force = re.compile(rf"{git_verb('clean')}{SEG}\s({short_cluster('f')}|--force\b)")
# --force-with-lease (and other --force-* forms) stay allowed; bare --force / -f do not.
push_force = re.compile(rf"{git_verb('push')}{SEG}\s({short_cluster('f')}|--force(?![-\w]))")

DENY = [
    (add_sweep, "`git add -A/-u/--all/--update` 会把不是你显式指定的文件（含并发 session 的在制工作）"
                "卷进暂存区（两次血泪规则）。请先 `git status`，再按显式路径 stage。"),
    (add_dot, "`git add .` 同上——按显式路径 stage 本次改动的文件。"),
    (commit_sweep, "`git commit -a/--all` 会连带 stage 所有 tracked 修改（含并发 session 的）。"
                   "请显式 `git add <paths>` 后再 commit。"),
    (commit_noverify, "`git commit --no-verify` 绕过 pre-commit 检查（格式/类型/测试）。"
                      "修好检查再提交，不要绕。"),
    (clean_force, "`git clean -f` 删除未跟踪文件且不可恢复——里面可能有用户或并发 session 的在制内容。"
                  "请逐个 `rm` 你确认属于自己的文件。"),
    (push_force, "`git push --force` 重写远端历史，会抹掉别人已推的提交。"
                 "要覆盖请用 `--force-with-lease`（本 guard 放行）。"),
]

for pattern, msg in DENY:
    if pattern.search(cmd):
        print(f"claude-kit git-guard: BLOCKED — {msg} "
              "特殊情况确需执行:在命令前加 CLAUDE_KIT_GIT_GUARD_BYPASS=1（需用户明确授权）。",
              file=sys.stderr)
        sys.exit(2)

# ---------------------------------------------------------------- ASK tier
reset_hard = re.compile(rf"{git_verb('reset')}{SEG}\s--hard\b")
checkout_dot = re.compile(rf"{git_verb('checkout')}{SEG}\s\.(\s|$|[;&|])")
restore_seg = re.compile(rf"{git_verb('restore')}{SEG}\s\.(\s|$|[;&|])")
restore_staged_only = re.compile(rf"{git_verb('restore')}{SEG}\s--staged\b")
restore_worktree = re.compile(rf"{git_verb('restore')}{SEG}\s(--worktree\b|-W\b)")
stash_clear = re.compile(rf"{git_verb('stash')}{SEG}\sclear\b")
# stash creation = bare `git stash`, `git stash push`, `git stash save` (anything that is
# not an inspect/restore subcommand). A `--` means the caller named explicit paths.
stash_create = re.compile(rf"{git_verb('stash')}(?!{SEG}\s(pop|apply|list|show|drop|branch|clear)\b)")
stash_pathspec = re.compile(rf"{git_verb('stash')}{SEG}\s--\s")

ask = None
if reset_hard.search(cmd):
    ask = ("`git reset --hard` 会丢弃工作树里所有未提交改动——包括并发 session 的在制工作。"
           "确认这棵树现在只有你在写？")
elif checkout_dot.search(cmd):
    ask = ("`git checkout .` 会丢弃工作树里所有未提交改动（不只你改的那些）。"
           "只想还原自己的文件请写显式路径。")
elif restore_seg.search(cmd) and not (restore_staged_only.search(cmd) and not restore_worktree.search(cmd)):
    ask = ("`git restore .` 会丢弃工作树里所有未提交改动（不只你改的那些）。"
           "只想还原自己的文件请写显式路径。")
elif stash_clear.search(cmd):
    ask = "`git stash clear` 会不可恢复地删掉所有 stash 条目。"
elif stash_create.search(cmd) and not stash_pathspec.search(cmd):
    ask = ("裸 `git stash` 拥有整棵工作树——A/B 舞步期间不能有并发的 git/文件操作，"
           "且 `-u` 会吞未跟踪文件。确认这是前台独占的 A/B？（只 stash 自己的文件：`git stash push -- <paths>`）")

if ask:
    if os.environ.get("CLAUDE_KIT_HOOK_HOST") == "codex":
        print(
            "claude-kit git-guard: BLOCKED pending explicit user approval — " + ask +
            " 若用户已明确授权，在原命令前加 CLAUDE_KIT_GIT_GUARD_BYPASS=1 重跑。",
            file=sys.stderr,
        )
        sys.exit(2)
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "ask",
            "permissionDecisionReason": f"claude-kit git-guard: {ask}",
        }
    }, ensure_ascii=False))
    sys.exit(0)

sys.exit(0)
PY
exit $?
