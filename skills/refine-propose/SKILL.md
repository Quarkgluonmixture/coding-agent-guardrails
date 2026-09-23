---
name: refine-propose
description: 'Turn what this session actually learned into ONE evidence-backed, reviewable proposal to change the harness (a claude-kit rule/skill/agent/hook, a memory, AGENTS/CLAUDE guidance, or a project doc) — routed to the right layer and gated on whether it deserves to be global. Writes a proposal file for human review; never edits the harness itself. Prefer this over checkpoint whenever the request explicitly asks for a proposal. Triggers: "refine", "沉淀一下", "这个该记哪", "把这次的教训固化", "propose a rule/skill for this", noticing the same correction or the same failure for the second time.'
---

# /refine-propose — 把这次的教训路由到正确的那一层

一个 session 结束时最容易发生的浪费：教训只留在对话里，下个 session 从零重蹈。
第二容易发生的浪费：教训被写进**错误的层**——该进 hook 的写成了规则（会被忘），
该留在项目的升成了全局（污染所有项目），该进 rules 的写进了 memory（子 agent 读不到）。

这个 skill 只做一件事：**产出一份有证据、可审查、指明落点的提案**。它不改 harness，
不 commit，不 push。合并由人来做，走正常的 git 编辑。

## 硬规矩

1. **无证据不提案。** 每条提案必须引用**这个 session 里真实发生的事**：具体的失败、
   用户的纠正、实测数字、`file:line`。"一般来说这样更好"不是证据。
2. **一次一条。** 一份提案改一个东西。想改三处 → 三份提案，各自独立成立。
3. **最小组件优先。** 能靠项目文档或一条可维护 memory 解决就不要写规则；能靠一条规则解决就不要写 skill。
4. **不自审自批。** 提案写完，独立验证走 cross-ai skill（已有的 zero-preset 交叉验证），
   不要自己论证自己。
5. **绝不直接改** `~/claude-kit/**`、宿主全局配置或 memory 文件。提案是文件，人来合。

## 第一步：路由（先决定落哪一层，再写内容）

| 这次学到的东西 | 落点 | 为什么 |
|---|---|---|
| "这件事**绝不能发生**"，且能用命令模式识别 | **hook**（`hooks/`） | 规则会被忘，hook 不会。能上 hook 的不要写成规则 |
| 每个执行者（含子 agent）都必须遵守的纪律 | **`rules/global/`** | Claude 经 rules 加载；Codex 经 SessionStart/SubagentStart 注入 |
| 只在某些项目成立的政策 | **`rules/optin/`** + `kit add` | 全局化会污染无关项目 |
| 可复用的多步流程 | **skill** | 按需加载，不占常驻上下文 |
| 反复出现的委派角色（省上下文/省 effort） | **agent**（`agents/`） | ⚠ 每个全局 agent 的 description 每 session 都进主上下文 → 少而精 |
| 跨 session 的静态事实、决策、教训 | **可维护 memory / AGENTS / 项目文档** | memory 不保证到子 agent；Codex generated memory 不直接手改 |
| 项目的现场状态、进度、下一步 | **CHECKPOINT / TODO / LOG** | 不是 harness 改动，别塞进 kit |
| **只在这个仓库会咬人**的技术陷阱 | 项目 `GOTCHAS.md`（`/checkpoint` 第五件） | 动手前要读的耐久知识。往上升层要有理由：**复发**、或有确定性复现、或后果不可逆 |

判不准就往下降一层：memory 比规则便宜，项目级比全局便宜，**降级永远是更安全的错**。

## 第二步：晋升门槛

```
observation  →  candidate lesson  →  validated project pattern  →  global kit asset
（发生了一次）    （有机制解释）        （本项目复现过 ≥2 次或有确定性复现路径）  （跨项目成立）
```

| 目标层 | 门槛 |
|---|---|
| LOG 一条 | 单次有价值的现象即可 |
| 项目 memory | 已验证，且对未来 session 持续有用 |
| 项目 rule / 项目文档 | 本项目重复出现，或有明确复现路径 |
| **claude-kit 全局资产** | **必须回答：为什么它不应该只留在当前项目？** |

最后那一问是硬门槛，不是修辞。答不上来 = 这条提案的目标层写错了，降一级重写。
它砍掉的是最常见的污染：一次偶然失败 → 写成全局规则 → 所有项目开始绕一个不存在的问题走。

反模式（直接驳回，不要写成提案）：
- 单次事故 + 没有机制解释 → 只进 LOG
- 已被现有 rule/skill 覆盖 → 改那条，不要新增
- 措辞更漂亮但行为不变 → 不是提案
- 能用 hook 硬约束的写成规则 → 换成 hook 提案

## 第三步：写提案

写到宿主的 kit proposal 目录：Claude 用 **`~/.claude/kit-proposals/<YYYY-MM-DD>-<slug>/proposal.md`**；
Codex 用 **`~/.codex/kit-proposals/<YYYY-MM-DD>-<slug>/proposal.md`**。

> 落在项目 repo 外面是刻意的：项目仓库里不放个人开发产物，提案也不例外。

模板见 [proposal-template.md](proposal-template.md)（照抄，逐段填，**不要留空段**——
填不出来的那一段就是这条提案不成立的地方）。

## 第四步：交回用户

只报三件事，不要复述提案全文：

1. 一句话：提案改什么、落哪一层。
2. 那个硬门槛的答案（为什么不该只留在当前项目）——若目标是全局资产。
3. 提案文件路径 + 建议的下一步（cross-ai 独立复核 / 直接人工合并 / 先攒着看会不会再发生）。

然后停。合并是人的决定。

## 相关

- 落点是否真的生效：`kit state`（报实测加载，不报声明安装）
- 独立复核：cross-ai skill
- Claude 可维护 memory 的腐坏：memory-audit skill
- 四件套文档流：checkpoint skill
