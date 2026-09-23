<!-- claude-kit reference · concurrency-and-worktrees — 同一 repo 有别的 session 在干活时：worktree 建法、广播的分辨率极限、外发动作的天花板 -->
# 多 session 并发 · worktree · 外发动作的细则

**触发**：工作树里出现不是你改的未提交变更；或你要开 worktree、要做独占型操作
（stash A/B、rebase、大范围 checkout）；或要发 PR / issue 评论。
资格线（**必须已经在 resident 规则里生效**）：`rules/global/git-and-style.md`。

## worktree：要开就自己建，别用宿主默认档

宿主的 `EnterWorktree` 默认从 `origin/<default>` 开分支，⛔ 那会**丢掉本地未推送的 commit**。

```bash
git worktree add -b <branch> .claude/worktrees/<name> HEAD   # 从 HEAD，不是 origin
```

放 `.claude/worktrees/` 下让 `git status` 输出完全不变；`node_modules` 用 symlink +
写进 `.git/info/exclude`（symlink 匹配不上 `node_modules/` 那条 gitignore）。

⚠ 这类「逻辑路径 / symlink 别名」正是**破坏性操作打到真仓库**的形状 —— 动手前把目标
canonicalize 一次，见 `work-discipline` 的「危险操作前先证明目标不是别名」。

## 广播是通知，不是锁（2026-08-08 实测）

跨 session 消息只落在对方**两次工具调用之间的缝隙**里，打不断已经发起的那一次 —— 对方若已
开始 `git stash`，你拦不住。而 `git stash` / 写 `CHECKPOINT.md` 恰恰都是**单次调用**，临界区在
缝隙**内部**，消息永远慢一格。某些 remote session 还无法主动寻址。

⇒ 排他仍以「工作树里有别人的改动就不动」这条**判定信号**为准；广播只降低相撞概率。
真正的锁必须在 PreToolUse hook 层（它在调用**发起前**触发）。

独占型操作前的广播动作：若宿主提供 active-agent / session 列表与消息能力，逐个确认共享同一
cwd 的 peer，再发一条「我要独占 `<repo>` 约 N 分钟」。

## 交接文件的并发分工

- `LOG.md` append-only 天然不冲突（并发期间的唯一真相）。
- 快照（`CHECKPOINT.md`）单写者；整页刷新只在自己是唯一 session 时做。
- `GOTCHAS.md` 编号会撞（两个 session 各自认领同一个号，而号是别处引用的稳定标识）——
  并发期间要么独写，要么用 `12b` 式后缀。
- 详细流程见 `checkpoint` skill。

## 外发动作（gh / PR / issue 评论）的天花板

- **多行 markdown 一律走 `--body-file`，绝不用 `--body`**：`gh issue comment --body-file f.md` /
  `gh pr create --body-file f.md`。两道天花板会静默截断或报错——argv ~128KiB、body 65536 字符。
  （GitHub 故障时 GraphQL 挂而 REST `gh api …/pulls -X POST` 还能建 PR。）
- **发之前把最终文本原样过目一遍**；一条事最终只留**一条**评论。发歪了立刻删掉重发，
  不要追加更正楼。
- **合并 PR 前核对 head**：`git rev-parse HEAD` 必须等于 `gh pr view --json headRefOid` 拿到的值。
  GitHub 可能拿**陈旧的 head** 合并，把你最后一次推送静默丢掉；「新提交没触发 CI」就是这个
  竞态的信号。⇒ 推送成功 ≠ PR 看到了。
- 语气跟用户的语气，不堆 emoji，不写「感谢您百忙之中」这类填充。

## pre-commit 改了文件就要重新 stage

跑完格式化 / lint 的 pre-commit 钩子常会改写你已 stage 的文件，于是提交进去的是格式化**之前**
的版本。收尾顺序 = 先 `git add <显式路径>` → 跑检查 → **把被改写的那几个文件再 `git add` 一次**
→ commit。（`--no-verify` 绕过检查是禁止的，git-guard hook 已硬闸。）

## stash A/B 的细则

`stash push -u` 会吞未跟踪文件、drop 时随之丢——优先 stash **显式 tracked 路径**。
headline 数字 commit 前对干净 HEAD 复现一次。
（前台独占这条本身是 resident 规则，见 `git-and-style`。）
