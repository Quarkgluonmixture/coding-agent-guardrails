# Codex adapter

`claude-kit` 的 Codex 端不是把 `~/.claude` 整棵复制到 `~/.codex`，而是保留一份语义真源，
再把它映射成 Codex 原生能力。这避免了两份规则漂移，也不会覆盖现有 `AGENTS.md`。

## 安装与迁移

```bash
~/claude-kit/install.sh --target codex   # 只装 Codex adapter
~/claude-kit/install.sh                  # 默认同时安装 Claude + Codex
kit doctor codex
```

安装器是幂等的，会：

- 把 Codex 可用 skills 链到 `~/.agents/skills/<name>`；
- 把 `executor.toml` 链到 `~/.codex/agents/executor.toml`；
- 合并 kit hooks 到 `~/.codex/hooks.json`，保留其他 hook 和顶层字段；
- 保留 `~/.codex/AGENTS.md` 原样；
- 若目标名已是真文件/真目录，先移到 `~/.codex/backups/` 再建链接。

安装后重开 Codex，运行 `/hooks` 审核并 trust 这三个注册项：

1. `PreToolUse` → `hooks/codex-git-guard.sh`
2. `SessionStart` → `hooks/codex-rules.py`
3. `SubagentStart` → `hooks/codex-rules.py`

Codex 会对 hook **定义**记录 trust；新增或变更定义后需重新审核。定义里信任的是本 kit 的
稳定命令路径，所以之后拉取的 hook 脚本也属于该信任边界；更新 repo 前仍应审阅 diff。
安装器不会静默绕过 trust。官方机制见 [Codex hooks](https://learn.chatgpt.com/docs/hooks)。

## 资产映射

| 逻辑资产 | Codex 实现 | 说明 |
|---|---|---|
| `rules/global/*.md` | `SessionStart` / `SubagentStart` 动态注入 | 和 Claude 读同一文件 |
| `rules/optin/*.md` | 读项目 `.claude/kit-rules` | 不需 `kit sync` 建链接 |
| `checkpoint` | 共享 skill symlink | Codex memory 部分已做宿主分支 |
| `refine-propose` | 共享 skill symlink | proposal 写到 `~/.codex/kit-proposals` |
| `report-dashboard` | 共享 skill symlink | 共享 template 和 workflow |
| `cross-ai` | `codex/skills/cross-ai` | 反向调 Claude，不会调第二个 Codex 冒充跨谱系 |
| `memory-audit` | 不安装 | 它操作 Claude 的可编辑 auto-memory |
| repo `skill-creator` | 不安装 | 避免遮蔽 Codex 自带的 `skill-creator` |
| `executor.md` | `codex/agents/executor.toml` | 同一角色契约，Codex 原生 TOML |
| `git-guard` | Codex wrapper + 共享 guard | DENY 一致；ASK 见下文 |

Codex 的 skill 发现目录与 custom-agent TOML 格式参见
[Build skills](https://learn.chatgpt.com/docs/build-skills) 和
[Custom agents](https://learn.chatgpt.com/docs/agent-configuration/subagents)。

## 规则加载与项目 opt-in

`hooks/codex-rules.py` 每次启动时：

1. 解析当前项目的 git root；
2. 读 `kit.conf` 开关；
3. 按文件名排序加载开启的 global rules；
4. 再加载机器级开启、或项目 `.claude/kit-rules` 列出的 opt-in rules；
5. 把文件路径和 SHA-256 写入 `~/.codex/kit-state/instructions.jsonl`；
6. 把同一正文作为 extra developer context 返回给 Codex。

`SubagentStart` 使子 agent 也收到同一规则集。安装器因此无需改写个人 `AGENTS.md`；项目自己的
`AGENTS.md` 仍由 Codex 原生指令层级负责。官方层级见
[AGENTS.md](https://learn.chatgpt.com/docs/agent-configuration/agents-md)。

```bash
cd <project>
kit add remote-compute     # 同一 manifest 同时给 Claude/Codex 用
kit state codex            # 必须在新 session 后才能看到新的实测记录
kit state codex --json
```

`kit state codex` 不仅报「安装了什么」，而是报最近一次 root/subagent 启动真正注入了什么。
若加载后规则正文变过，它会用 hash mismatch 明示。

## git-guard 差异

DENY 档在两端都直接拦截，例如 `git add -A`、`git clean -f`、`git push --force`。

Claude hook 支持 ASK，所以 `git reset --hard`、裸 `git stash` 等正常但会毁未提交工作的命令可弹一次确认。
Codex 当前会解析但不支持 `PreToolUse permissionDecision: "ask"`；返回该值反而会继续工具调用。
所以 Codex adapter 对 ASK 档先 exit 2，然后只在用户明确授权后允许：

```bash
CLAUDE_KIT_GIT_GUARD_BYPASS=1 git reset --hard
```

bypass 会留在命令文本里，可审计；不要把它做成全局环境变量。

## memory 边界

Codex 的 `~/.codex/memories` 是生成态，本 kit 不把直接编辑它当作可靠控制面。需要稳定继承的事实写到
`AGENTS.md` 或项目文档；项目现场状态仍用 CHECKPOINT / TODO / LOG。`memory-audit` 和
`kit memory-link` 只服务 Claude 的可人工维护 auto-memory。官方说明见
[Codex memories](https://learn.chatgpt.com/docs/customization/memories)。

## 排障

```bash
kit doctor codex
kit state codex
```

- `doctor` 报 hook 缺失：重跑 `install.sh --target codex`。
- hook 已注册但 `state` 无记录：重开 Codex，在 `/hooks` trust，然后再开新 session。
- `cross-ai` 无第二意见：确认 `claude` 在 PATH 且已登录；不得静默退化后仍称 cross-check。
- 规则清单有项但未加载：确认从项目内启动新 session，并查 `kit state codex --json`的 `project`。
