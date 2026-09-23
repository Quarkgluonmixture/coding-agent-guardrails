---
name: checkpoint
description: 'The project docs-update flow for session continuity. CHECKPOINT.md = the snapshot the next session resumes from directly; TODO.md = future-only plans (done items deleted); LOG.md = append-only history of what happened + WHY; roadmap doc (if any) = sole truth for stages, never copied; GOTCHAS.md = the optional fifth file, the project''s durable numbered traps. Two modes — resume (session start: read CHECKPOINT first, verify load-bearing claims before trusting) and wrap-up (per finished chunk: append LOG → prune TODO → refresh CHECKPOINT → touch memory only if a durable fact changed). Triggers: "checkpoint", "收尾", "存档", "handoff", "交接", "resume", "接手", "记录这个坑", "又踩了一次", "update GOTCHAS", starting work in a project that has a CHECKPOINT.md, finishing a meaningful chunk of work. If the user asks for a reviewable harness-change proposal, use refine-propose instead.'
---

# checkpoint — the docs-update flow (session handover)

One mechanism, four core files (+ an optional fifth), each on its own change-frequency. Each file
has ONE job; mixing them is how handover docs rot.

| 件 | 文件 | 唯一职责 | 谁写 |
|---|---|---|---|
| snapshot | `CHECKPOINT.md` | 下一个 session **直接接手**：现状 + ops 速查 + 一行 phase cursor + 链接 | 单写者，整页刷新 |
| future | `TODO.md` | **只放未来**。做完的条目**立即删除**（历史已在 LOG）| 随做随删 |
| history | `LOG.md` | append-only：发生了什么 + **为什么**（决策/教训）| 只增不改 |
| stages | roadmap doc（有则用）| 阶段的唯一真相；别处只放 cursor 指针，**绝不复制** | 战略变更时 |
| traps（按需）| `GOTCHAS.md` | **编号稳定的耐久陷阱**，动手前扫一遍 | 编号只追加；正文可改 |

Small projects may fold TODO back into a CHECKPOINT section — the delete-on-done rule stays.
If the files don't exist yet, offer to bootstrap minimal ones (don't force the structure on a
repo that has its own working convention — adapt to it and say so).

## Mode: resume（session 开始 / 用户说"接手/继续"）

1. **Read `CHECKPOINT.md` FIRST** — it is the sole entry point; you usually need nothing else to
   get oriented. Then `TODO.md`; LOG only via `tail -n 40` if you need the recent why.
   有 `GOTCHAS.md` 就在**动手前**扫一遍——它不是历史，是**现在仍然会咬人**的东西。
2. **Verify before trusting.** The snapshot predates reality: before acting on a load-bearing
   claim (a path, branch, flag, "X is running"), probe it (`ls` / `git log --oneline -5` /
   `git status`). Same for auto-loaded memories that name files or flags.
3. State the cursor back to the user in one line ("接手点 = <phase> · 上次做到 <X> · 下一步 <Y>")
   so a wrong pickup dies immediately.
4. **扫一眼并发**（要动共享工作树时才值钱；纯读代码可跳过）：若宿主提供 active-agent/session
   列表与消息能力，确认共享同一 cwd 的 peer；无法主动寻址的 remote session 跳过。
   这是**事前**环节，补在「工作树里冒出别人的改动」那条**事后**信号之前——不是替代它。

## Mode: wrap-up（每完成一个有意义的 chunk —— 不是只在 session 末尾）

> 自然语言触发由 kit 的 `wrap-up-trigger` hook 保证：用户的整条消息是一句**显式短指令**（收尾 / 存档 /
> 交接 / 接手 / 记录这个坑 / update gotchas，≤40 字且以触发词开头，或长消息末尾 20 字内）时，
> hook 把「现在调用 checkpoint skill」注入上下文。词表以 hook 为准（`hooks/wrap-up-trigger.py --triggers`）；
> `/checkpoint` 仍是 100% 的路。

Per-chunk, not per-session: a crashed session then still leaves a trail. Order matters:

### 触发时机（用户发起；这些时刻最多提一句，不自作主张开工）

**wrap-up 由用户发起。** 不要因为「感觉该存档了」就自己跑整套流程——它会改四到五个文件，
用户手上可能还有没落地的判断。下面这些是**值得提一句**「要不要先存个档」的时刻，
一句话点到为止，用户说做才做：

- **上下文压缩之前** —— 压缩会把细节（某个数的 n 是多少、为什么放弃 A 方案）磨成摘要，
  事后只能补个大概。**用户会提前说「要 compact 了」**，那时再存档；不用自己猜时机。
- **测试转绿、A/B 出结论、bug 定位到根因** —— 结论刚成立、证据还在手上的那一刻最值钱。
- **起一个长任务之前**（后台跑批、远端 GPU 作业、CI 长流水）—— 等它回来时上下文可能已经换了一茬。
- **切 repo / 切大方向之前** —— 离开一个上下文就把它落盘。
- **chunk 失败或中途放弃时**（最容易跳过、其实最该写）—— 试到哪、卡在哪、下次别再走这条路。

时间紧时可以只做第 1 步：**append 一条 LOG** 就够了。LOG 是 append-only，不覆盖任何东西。

1. **Append ONE dated entry to `LOG.md`** (never read the whole file first):
   ```bash
   TS=$(date '+%Y-%m-%d %H:%M')
   { echo ""; echo "## [$TS] <short title>  #<tag>"; echo "- <what changed + WHY / decision / lesson>"; echo "- <next>"; } >> LOG.md
   ```
   Stale live-state being evicted from CHECKPOINT lands here too — rewritten as a dated
   "截至 X 时" snapshot, no "当前" wording (frozen live-state is guaranteed stale).
   ⭐ 这个 chunk 里**踩到坑**的话，LOG 记事件（`#incident`）之后还有半步 —— **写哪儿看项目现状**：
   已有 `GOTCHAS.md`（按 CHECKPOINT 的指针找）就写进去；**没有就写进 `CHECKPOINT.md` 的坑一节**，
   不要为了第一条坑新建文件（拆分门槛见下方 GOTCHAS 一节）。
   ⭐ 反向也要做：这个 chunk 如果**给某条老坑加上了守卫**（测试/hook/类型），同一次 wrap-up 里
   就把那条**退休成一行墓碑**。攒着不退休 = 下次没人扫得动。
2. **Prune `TODO.md`**: delete what's done; add newly discovered future work.
3. **Refresh `CHECKPOINT.md`**: 现状 / ops facts / cursor / links. **Hard cap ~1-2 页（~120 行）** —
   over budget means history crept into the snapshot → evict to LOG. The cap is the self-cleaning
   mechanic, not a style preference.
4. **Memory** only if a durable fact changed (decision, correction, mechanism — not progress).
   For an editable memory store, follow `memory-hygiene` and update its index in the same turn.
   Treat Codex local memories as generated state; put required durable facts in `AGENTS.md` or repo docs.
5. Report to the user in one line what was updated ("checkpoint 已存档：LOG +1 · TODO -2 · 快照刷新")。
   **动了 GOTCHAS 就明写**（"坑 +1 / 坑 12 复发计数 +1 / 坑 7 退休"）—— 那是第五次写入，别让它隐形。

### What NEVER goes in the snapshot

- **Git state** — no pinned HEAD, no "N commits ahead", no commit-hash lists, no "push" TODO.
  All derivable (`git log --oneline origin/main..HEAD`), stale every commit, and the #1 thing
  concurrent sessions collide on. At most a one-line pointer to the command.
- **Done detail** — verification logs, slice-by-slice history → LOG only.
- **Roadmap stages** — cursor pointer only.

### LOG 台账：标签 + grep，不另开文件

LOG 长到几百条以后，「我们当时为什么不用 X」就靠 grep 找不回来了——正文是中英混写的散文。
解法是**在标题行打标签**，让 `grep '^## '` 直接产出一张分类目录。不建第二个索引文件：
一份内容两处维护 = 必然腐烂，这正是本流程要避免的东西。

标签词表（固定这 5 个，别扩；一条可多标）：

| tag | 什么时候打 | 为什么值钱 |
|---|---|---|
| `#decision` | 决定做 / 不做 / 回退某事 | 半年后重提同一方案时，先翻这个 |
| `#measure` | 任何测量结果 | **必须带 n / k / 日期 / 怎么复现**，否则就是个无法证伪的数 |
| `#deadend` | 试过、不行、放弃 | 连同**排除它的那个证据**一起记，防止重新论证一遍 |
| `#incident` | 踩坑 / 事故 / 外部故障 | 复发时第一时间能认出来 |
| `#ship` | 落地：commit / deploy / 交出去 | 「做完了」和「上线了」是两件事 |

查询（LOG 与归档一起搜，rotation 不会让旧条目失联）：

```bash
grep -n '^## ' LOG.md LOG-archive/*.md          # 全量目录
grep -n '#deadend' LOG.md LOG-archive/*.md      # 试过什么不行
grep -n -A4 '#measure' LOG.md LOG-archive/*.md  # 所有数字连同出处
```

历史条目不用回填标签——从现在起写的带上就行，存量靠全文 grep 兜底。

### 轮转：动作三行，契约四行 —— 契约才是承重的那部分

轮转本身很简单：live 文件过阈值 ⇒ 把关闭的那一段整体移进
`LOG-archive/LOG-<YYYY-MM>.md` 或 `<NAME>-ARCHIVE-<起>-<止>.md`。
阈值按**你还能一口气读完多少**定：LOG 类 ~600 行；逐条 verbatim 的裁决类 ~1,500 行。
⛔ 但**只做动作不写契约 = 白轮转**——实测一个项目轮转完，归档里 410 个测量数字仍然查不回来，
因为没有定位命令，也没人知道该读哪一段。

live 文件顶部必须写清四件事，少任何一件下个 session 就得靠猜：

| # | 要素 | 例 |
|---|---|---|
| 1 | **live 文件的边界**，写进**标题**（不是正文） | `LIVE FILE, #285 onward` |
| 2 | **档名带编号区间或日期** ⇒ 定位靠档名，零维护 | `…-ARCHIVE-001-284.md` · `LOG-2026-08.md` |
| 3 | **读法**：下个 session 该读多少 | `Resume = tail -n 120 of THIS file` |
| 4 | ⭐ **定位命令，glob 必须覆盖 live + 全部归档** | `grep -n "RULING #N " docs/…/PROGRAMME-RULINGS*.md` |

⭐ 第 4 条最省力也最承重：**glob 一写对，轮转就永远不会让引用失联**——一条命令同时命中
live 与所有归档。⛔ 别写只指向 live 文件的定位命令，那等于宣布归档不可检索。

⛔ **不要把轮转阈值、也不要把「上次什么时候轮转的」写进文件头。** 阈值的权威来源是本节，
轮转事件的权威来源是 `LOG.md`（wrap-up 已经会 append 一条）。抄进头部 = 第二份会漂的副本，
而且是要人**记得回头改**的那种——那种一定会漂。

⭐ 四要素为什么不会 stale：**2 和 4 跨轮转根本不变**（档名规则一样、glob 一样），
**1 和 3 从文件内容自明**。唯一要动手的是第 1 条：第二次轮转后改标题里那个起点，
自查断言 = 「标题声称的起点 == 文件首条条目的编号/日期」。

### 轮转之前先问一句：老条目还需要被访问吗

1. **不需要**（计划、路线图当前态、状态快照）⇒ **既不轮转也不归档**：直接**替换**，
   被顶下来的旧状态 append 进 `LOG.md`，改写成「截至 X 时」的快照语气（⛔ 不留「当前」措辞）。
   ⛔ 别给计划类文档做归档目录——旧版本的计划没人会去读，归档只是把它藏起来。
2. **需要**（别处按编号 / 日期 / 锚点引用它——一条 grep 就能查）⇒ **轮转**，按四要素写契约。
   定位靠**档名区间 + 那条 glob**，⛔ 不要再建第二个索引文件（见上面「LOG 台账」那条禁令）。

⚠ 已知未覆盖的一格：**编号与文件顺序脱钩时**（号散在几十节里、有缺号、有倒序），
档名区间在数学上装不下，glob 也只能告诉你「在这一个巨文件里」。那属于项目自己的取舍，
本 skill 不给方案。⛔ 别把这一格当默认情形——绝大多数 append 文档编号是顺序的。

## `GOTCHAS.md` — 按需拆出的第五件（现役危险清单）

四件套按**变化频率**分家，漏掉的正是这一格：**动手前必须读、且随认识加深不断改写**的东西。
快照有硬上限装不下它，塞进 append-only 的 LOG 等于埋掉（没人会为了动手前的自查去翻编年史），
memory 又不保证到达子 agent。所以坑无处可去时会挤在快照里，把快照顶爆——这就是拆出来的信号。

⭐⭐ **它是「现役危险清单」，不是「事故史」。** 已经被守卫堵死的条目留在正文里只会稀释它。
判据：这条**现在还会咬正在改代码的人吗**？不会 ⇒ 退休成一行墓碑，正文进 LOG。
一个长到没人扫的 GOTCHAS 比没有更糟——它让人以为自查做过了。

### 什么时候才拆（默认不拆）

- **触发**：快照里坑类条目多到把它顶过硬上限；或同一个坑**踩到第二次**而快照里没地方写。
- 没到触发条件就留在 `CHECKPOINT.md` 的一节里。**多一个文件是成本**，别为第一条坑提前付。
- 拆的时候把快照里那些条目**搬走**（不是复制），快照只留一句指针（含**真实路径**——
  放 `docs/` 下就写 `docs/GOTCHAS.md`，别人是照这个指针找文件的）。

### 四条纪律

1. ⭐ **编号只增不减、永不重排、不复用**（正文可以随时改写）。别处（LOG、TODO、代码注释）
   会按号引用，一重排全部失联。要删就留一行占位，不要把后面的号往前挪；
   并发下抢到同一个号 ⇒ 用 `12b` 这样的后缀，不要改动已有号。
   ⚠ 号是**稳定标识**，不是排序——别把"编号只增"读成"内容只能追加"。
2. ⭐⭐ **踩第二次就在原条目上记复发计数**（"已踩三次"/"这条已被违反两次"），并链到 LOG 那条
   `#incident` 的日期。计数是把**偶发**和**机制**分开的最省力信号，也是 `/refine-propose`
   晋升门槛的输入。⚠ 但**复发不是升层的唯一理由**：有确定性复现路径、或后果不可逆/高影响时，
   **一次就该升**（等第二次 = 主动允许它再发生一次）。
3. ⭐ **能被命令模式识别的坑，走 hook，不要停在文档里**——规则会被忘，hook 不会。
   写进 GOTCHAS 的同时问一句：这条能不能变成一个拒绝动作的 hook / 一条测试 / 一个断言。
   ⭐ **把答案写在条目里，一行**：`闸: <仓库根相对路径>`（**只给部分覆盖**的条目，写清闸不管哪一半），
   或 `闸: 无 — <为什么机器判不了>`。闸**完全覆盖**的条目不留在现役清单，按上文退休成墓碑（墓碑自带路径）。
   kit 的 `gotchas-contract` hook 在写入时检查**新条目**有这一行、路径是本仓库里的文件；它管「问过没有」，
   不管答案诚不诚实。基线 = 首次运行时 `git HEAD` 里的条目；未跟踪的 GOTCHAS 要先 `--seed`。
4. ⛔ **不写密材料**。事故台账天然会吸引带密的证据（口令、token、私钥、恢复码、原始报错里的
   密文）。写**机制**和**位置**（"口令在钥匙串 X / 由脚本 Y 取"），绝不写值本身。
   private repo 不是密码保险箱，而且写进去 = 进了 git 历史。

### 条目怎么写

**症状 → 机制 → ⇒ 规则**，一条三行以内，带日期。
只写症状的条目下次认不出来，只写规则的条目下次不敢信。

- **写机制那半最贵**：不是"记得加 X"，而是"为什么不加 X 时它会静默地错"。
- **同族交叉引用**：新坑和老坑是同一个失败机制时，写一句"与坑 N 同形"。散点因此聚成一个
  **可命名的机制**（实测样本里 4 条坑都指回同一条"不确定性在传递中被抹掉"），
  下次能在**没踩到**之前认出第五种形态。
- 不写现场状态、不写进度、不写 git 状态——那些是快照和 TODO 的活。

### 长到扫不动怎么办 —— 按时刻分节 + 挑读索引，不是删条目

⚠ **别用行数当上限。** 现役陷阱数随项目寿命增长是**正常**的，而按判据（"现在还会咬人吗"）
该退休的通常只是零头（实测一份 2,181 行的 GOTCHAS 里失效条目只有 5 处）。拿行数逼清理，
只会删掉还会咬人的条目，或者被无视。要改的是**读法**，不是量。

**触发阈值按每节条目数：任何一节超过 ~15 条 ⇒ 该分节了。** 三份实测分界很干净：
可扫的两份每节 **3–7** 条和 **3–14** 条，扫不动的那份两节各 **95 / 100** 条——差一个数量级。

1. ⭐ **按「时刻」分节，不按域、更不按主题美学切。** 节标题写成**你正处在哪一步**：
   `起一个长任务之前` · `停一个任务之前` · `跨机部署之前` · `改 config 之前` ·
   `调外部 API 之前` · `相信另一个 agent 的结论之前` · `修完一处之后` · `宣布"完成"之前`。
   为什么严格优于按域（db / 签名 / CI）：**按域要求你先正确判断自己在哪个域**，
   而跨域改动恰恰最容易判错；时刻不用判断——你就在那一步上。
   时刻节里的条目写成 `- [ ]` 勾选框，那才是起飞前检查单该有的样子。
   最后留一节 `本项目特有的硬规则（违反会毁数据，不只是麻烦）` 收不属于任何时刻的红线。
2. ⭐ **第一节固定是「元规律 / 族」**：把散点归成**可命名的失败机制**。认出机制比记住条目管用
   ——下次能在**没踩到**之前认出第 N 种形态。（实测两份可扫的 GOTCHAS 都有这一层。）
3. **顶部放一张挑读索引表**，第一列是时刻或动作，不是主题：

   ```
   ## 动手前按你正在哪一步挑着读

   | 你要动 / 你正在哪一步 | 先读 |
   |---|---|
   | 起一个长任务之前 | **30**（一句话摘要） |
   ```

   ⭐ 索引表是**派生**的（编号 + 一句话摘要）——⛔ 别把条目内容抄进表里，那就是第二份会漂的
   副本，而漂的那份正是读者先看到的那份。
4. ⭐⭐ **写一条准入判据钉在文件末尾，并给一个分流目标。** 两个闸门必须叠加：
   **未来还会遇到**（复发性）∧ **当时不会报错**（静默性）。
   ⛔ 会报错的、被现有测试抓得到的、只发生过一次的**不进这里**——分流到缺陷台账 /
   LOG 的 `#incident` / 一条测试，并在准入判据里**点名去哪**。
   没有分流目标的 GOTCHAS 一定会收下所有东西（实测：无判据无出口的那份收了 195 条）。
5. ⛔ **不要按「域」拆成多个文件**（db / ui / CI 各一份）。单一编号空间是"编号只增、永不重排"
   赖以成立的前提（别处按号引用），而"动手前读"的入口从 1 个变成 N 个 ⇒ 漏读一个文件比长一点
   更危险。真要外移（如密材料操作手册），顶部留一行"另见 X"。
   ⭐ 按**层**分文件是另一回事（操作层 / 分析写作层 / 代码缺陷各一份，各带自己的编号空间），
   前提是顶部互相指得到。

### ⭐ 交付：加了文件 ≠ 送到执行者手里

拆出 GOTCHAS 的**同一笔**改动里，把它写进该项目 `AGENTS.md` / `CLAUDE.md` 的必读清单。
理由是机制性的：子 agent 不保证继承主 session 的 skill 或 memory 上下文。**没进必读清单的 GOTCHAS，
只有恰好触发了 checkpoint skill 的主 session 才会读到。**
委派子 agent 做具体改动时，把**相关条目号连同正文**放进 brief，别指望它自己去翻。

### 与 LOG `#incident` 的边界

同一次事故，两处都要，写的**不是同一半**：LOG 记**那次发生了什么**（编年史，带日期与证据，
不再改动）；GOTCHAS 记**它现在还会怎么咬你**（耐久规则，随认识加深而改写）。
判据：读者是"想知道当时为什么这么决定"就去 LOG，是"我正要动这块代码"就看 GOTCHAS。

## 多 session 并发（同一 repo 同时有别的 session / 用户在干活）

- **判定信号**：工作树里出现不是你改的未提交变更 ⇒ 有并发活动。不 stash / reset / checkout
  别人的在制工作——surface 它，只动自己的文件。
- **LOG 是并发下的唯一真相**：append-only 天然不冲突，每个 session 各自追加自己的条目。
- **GOTCHAS 编号会撞**：两个 session 同时"追加下一条"就会各自认领同一个号，而号是别处引用的
  稳定标识，撞了比普通冲突更难修。并发期间要么让一个 session 独写，要么用 `12b` 式后缀。
- **快照单写者**：整页刷新 `CHECKPOINT.md` 只在你是唯一 session 时做；并发期间只对自己拥有的
  小节做定点小改。
- **commit 按显式路径 stage 自己 session 改的文件**（git-guard hook 已硬闸 `add -A/.`——并发时
  `-A` 会把别人的在制工作卷进你的 commit）。`git diff --cached --name-only` 过目确认后再 commit。
- 独占型操作（stash A/B、rebase、大范围 checkout）动手前，若宿主支持跨 session/agent 消息，向
  同 cwd 的 peer 广播一条「我要独占 `<repo>` 约 N 分钟」。**广播是通知不是锁**（消息够不到单次工具调用
  的内部，且部分 remote session 主动寻址不了）——机制与局限见 `git-and-style` 并发段，
  别把它当排他保证。

## 与其他机制的关系

- 这些文件是否 git-track 由项目定（gitignored 本地态和 committed 皆可；含敏感内容 → repo 必须私有）。
- 里程碑级 wrap-up 之前跑 cross-ai 审查门（见 `cross-ai-review` 规则）：先审 → 修 → 一个干净
  的已审 commit，而不是 commit 后再补丁。
- memory 的防腐是三层：写入时五规则（本流程第 4 步）→ 读取时先验证（resume 第 2 步）→ 周期性
  memory-audit 实测审计（仅适用于宿主提供的可人工维护 memory）。
