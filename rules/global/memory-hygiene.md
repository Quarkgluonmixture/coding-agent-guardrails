<!-- claude-kit rule · memory-hygiene — 四件套各答什么 · 计划权威按问题划界 · memory 写入五规则 · 哪条通道到得了子 agent -->
## 记录与记忆纪律

项目的"记忆"按**变化频率**拆文件，职责互斥，不要混写。⭐ 每个文件**只回答一个问题**：

- `CHECKPOINT.md` — 下一个 session **直接接手**需要的现场。**硬上限 1-2 页**（这是自清理力学：
  想膨胀就必须把变 stale 的内容挤进 LOG）。
- `TODO.md` — **只放未来/未完的活**。做完的条目**立即删除**，不留 done 列表。
- `LOG.md` — **append-only**：发生了什么 + **为什么**。live 内容入档时改成"截至 X 时的状态"
  语气，不留"当前"措辞（冻 live = 必 stale）。
- roadmap 文档（有则用）— **阶段的唯一真相**。别处只放一行 cursor 指针，**绝不复制 stages**。
- `GOTCHAS.md`（按需拆出）— **编号稳定的耐久陷阱**，动手前扫。编号只追加，**永不重排**。
  **有这个文件的项目：动手前读它**；委派子 agent 时把相关条目**带进 brief**——加了文件 ≠ 送到执行者手里。

> **操作化全在 `checkpoint` skill**（resume / wrap-up 两模式、轮转契约、GOTCHAS 何时拆与怎么写、
> 并发分工）。⛔ 别在别处复述那套流程；这里只放"哪个文件答什么"这一层不变量。

- **计划权威按问题划界**：仓库可以有多份计划，但对**同一范围、同一问题**只能有一个 live 真相源。
  要写一份会回答「顺序 / 进度 / 未完的活 / 下一步」的文档前，**先找现有权威** —— 判据在**动笔那一刻**
  生效，⛔ 不是事后清查。非权威处只链接或派生，⛔ 不手抄状态。
  动手前读 `~/claude-kit/references/plan-authority.md`（怎么判、⛔ 别按文件名执法、ID 冲突怎么办）。

### memory（跨 session 静态事实）写入五规则

宿主提供**可人工维护的 memory 文件**时，每次 Write/Edit 前过一遍——**烂 memory 比没有更糟**：

1. **Durable-only**。memory 只放决策、纠正、机制、教训；live 状态（phase 进度、部署日期、"X pending"）
   属于 checkpoint/TODO，在 memory 里最多留一个指针。必须存的时点结果要带日期（"截至 2026-07-02"）。
2. **落点唯一**（同 `work-discipline` 的单一真源）：写事实前先扫索引，已有同主题文件 → 更新那个文件，
   别处只用 `[[name]]` 链接，同一段话绝不复制进第二个 memory。
3. **索引同笔同步**。改正文 ⇒ 同一操作里更新它在索引（MEMORY.md）的那一行；建新文件 ⇒ 索引行同 turn 写。
4. **不 pin 易变标识**。行号、易改路径要么不写，要么带日期（"~L305 as of 2026-07-02"）；优先用稳定名。
5. **立即 supersede**。session 中一旦得知某条 memory 过时，**当场改那个 memory 文件**——不要只把
   纠正留在 checkpoint/LOG/对话里。

> 反腐三层：写入时五规则 → 读取时先验证 → 周期审计（`memory-audit` skill）。
> Codex 的本地 memories 是生成态，⛔ 不把直接编辑 `~/.codex/memories/` 当控制面；需要可靠继承的
> 事实放 `AGENTS.md` 或项目文档。

### ⭐⭐ 触达边界：哪条通道到得了子 agent

**凡是需要子 agent 也遵守的纪律，必须活在 rules 层，不能只活在 memory 里。**
Claude 自定义 subagent 加载 CLAUDE.md/rules 层级但**不加载**主会话 auto memory；Codex 由 kit 的
`SubagentStart` hook 显式注入同一批规则。⛔ 不要假定任一宿主的 memory 会自动到达子 agent。

| 知识类型 | 住哪 | 到得了子 agent 吗 |
|---|---|---|
| 必须约束每个执行者的纪律 | **rules**（claude-kit） | ✅ 普通/自定义 subagent 自动；⛔ **Explore / Plan 除外** |
| 跨 session 的静态事实、决策、教训 | memory | ❌ 不保证 |
| 项目现场状态 | CHECKPOINT / TODO / LOG | ❌（除非 agent 自己去读仓库） |
| 某个 agent 专属的长流程 | skill 或 agent 自身 instructions | ✅ 显式指定时 |

⛔ **内置 Explore / Plan 不加载 CLAUDE.md 层级**（含 `~/.claude/rules/`，官方明示，为了快和省）。
⇒ 若某条**范围 / 授权 / 读取边界**必须约束它们，把那几条**随 delegation brief 带过去**；
⛔ 但别整套复制 —— git stage 之类它们根本用不到。

推论：**agent 定义文件里不要手抄 kit 规则**（又一份会漂移的副本）。写 agent 时假定全局 rules
已在其上下文里，只写这个角色独有的东西。（要某条 skill 全文 → 用 `skills:` 字段，别复制正文。）
