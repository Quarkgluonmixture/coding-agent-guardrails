<!-- claude-kit rule · git-and-style — push 必问 · 显式路径 stage · 别人的改动不动 · stash A/B 前台独占 · 中英不劈词 -->
## 语言与表达

- 默认中文（宿主已有语言偏好时，此处只补行为细节）。
- **不要中英劈词缝合**：动词用纯中文（我来 / 让我 / 我看看），英文只保留 code identifier
  与术语（`tool_calls` / AUROC / p99）。禁止 "让me" / "fix掉" 这类滑稽拼接。
  双语规范：框架/结论用中文承重，`file:line`、函数名、数字、正则用英文保精确。
- **说人话**（2026-08-11 用户直接打断「说人话」时定的）：默认**短句 + 结论先行**，论证压到必要的
  几句。⛔ 表格只在**真的在对比**时用，不拿来排版普通段落；⭐⛔⚠️ 这类符号在**落盘文件里**是导航、
  在**对话回复里**是噪音。长产出**进文件**，回复只说「做了什么 + 在哪 + 你要定什么」。
  被说太密时 ⛔ 不要道歉铺垫，直接用人话把同样的内容重说一遍。
  （密度不是专业，是让对方多做功。此条只管**回复**，不约束 `docs/` 里的文件。）

## Git

- **commit 可自主**（在非默认分支上；在默认分支先开分支）。**push 必须先问** —— 任何 push / PR /
  推到 remote 前显式确认；外发动作不可逆。
- **永不 `git add -A` / `git add .`** —— `git status` 后按显式路径 stage 本次改动的文件，commit 前
  `git diff --cached --name-only` 过目确认。**工作树里我没创建、没读过的文件不是我的**：surface 给
  用户，不 commit（血泪 ×2：个人 launcher 混进共享 repo commit；`add -A` 把用户 40 个在制音频源
  卷进公共 push）。编辑器/构建缓存 → `.gitignore`，不 commit。
  （kit 的 **git-guard hook** 已全局硬闸 `add -A/./--all`、`commit -a`、`--no-verify` —— 规则会被忘，
  hook 不会。Codex 的 ASK 档先拒绝、用户明确授权后带 bypass 重跑。）
- **stash A/B 前台独占**：stash → 测 → pop 的 A/B 舞步拥有整棵工作树——严格前台跑，期间不并行
  任何碰 git/文件的测量或后台任务（否则测到的是**从未存在过的杂交状态**）。
- **不把 git 状态 pin 进任何快照/交接文档**（HEAD hash、"N commits ahead"、push TODO）：每次 commit
  都过期，且是并发相撞的第一名；要看就现查 `git log --oneline origin/main..HEAD`。
- commit message 收尾按 harness 要求的 Co-Authored-By 行。

## 并发：判定信号（这一条必须常驻）

**工作树里出现不是自己改的未提交变更 ⇒ 有并发活动。别 stash / reset / checkout 掉别人的在制
工作——surface，并只动自己的文件。** 排他就以这条为准；跨 session 广播只是通知，**不是锁**
（消息打不断已经发起的那一次调用）。

### 先读 reference 再动手（不常驻，按需 page in）

开 worktree · 独占型操作 · 发 PR/issue 评论 · 合 PR · pre-commit 改了文件 →
`~/claude-kit/references/concurrency-and-worktrees.md`。⭐ 一句话版：宿主 `EnterWorktree` 默认档会
**丢掉本地未推送的 commit**；`gh` 多行 markdown 一律 `--body-file`（`--body` 有两道静默截断的天花板）；
合并 PR 前核对 head，GitHub 会拿**陈旧的 head** 合并。
