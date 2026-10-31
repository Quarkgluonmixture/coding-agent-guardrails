# claude-kit（中文说明）

**公开工程作品快照。** 本仓面向外部读者展示工程方法与可复现资产；日常使用和持续研发的主线仍归 `claude-kit`，本仓不是第二份实时规则权威。下方安装步骤用于复现本快照，不表示与私有主线自动同步（2026-10-31 用户确认定位）。

Claude Code + Codex 跨项目工具箱：通用的**行为约定（rules）**、**skills**、
**可复用委派角色（agents）**和 **hooks** 都收在一个 git repo 里。跨宿主的语义资产
只有一份正文；Claude/Codex 各自只保留最薄的加载 adapter。

| 资产 | Claude Code | Codex |
|---|---|---|
| global / opt-in rules | `~/.claude/rules` 与项目 symlink | `SessionStart` + `SubagentStart` 从同一文件动态注入 |
| 共享 skills | `~/.claude/skills` | `~/.agents/skills` |
| `cross-ai` | 主体 Claude，独立审核者 Codex | 主体 Codex，独立审核者 Claude |
| `executor` | `~/.claude/agents/executor.md` | `~/.codex/agents/executor.toml` |
| hooks | `~/.claude/settings.json` | `~/.codex/hooks.json`（安装后需 `/hooks` trust） |
| memory | 可人工维护，有 `memory-audit` / `memory-link` | generated state，本 kit 不直接编辑 |

上面每一项都能开关：**`kit config`** 决定这台机器**加载时**链哪些（关 = 真拆链），
**`kit add`** 则只让某一个项目生效。两条路径，见下文。

Codex 端的详细映射、迁移和限制见 [`docs/CODEX.md`](docs/CODEX.md)。

## ⭐ 为什么 rules 是特殊的一层

**自定义子 agent 会加载完整 CLAUDE.md 层级（含 `~/.claude/rules/` 与项目 `.claude/rules/`），
但不会加载主会话的 auto memory**，而且没有任何 frontmatter 能改这个行为。

⇒ **凡是需要每一个执行者都遵守的纪律，必须活在 rules 层。** Claude 用原生 rules
层传给自定义 subagent；Codex 的 kit hook 在 root `SessionStart` 和 `SubagentStart` 各注入一次。
两边都不依赖 memory 来约束子 agent，也不在 agent 定义里手抄第二份规则。
详见 `rules/global/memory-hygiene.md` 的"触达边界"一节。

### ⭐⭐ 但常驻是有代价的：内核 / 按需 两层

rules 到得了所有执行者，所以什么都想往里塞——于是失败模式从「规则冲突」变成
**规则显著性稀释**：10 条绝不能破的不变量，和 40 条「通常挺有用」的配方挤在同一视觉权重上。
2026-09-04 实测常驻层已经 29,792 字节（≈11.9k CJK 加权 token），**每个 session、每个 subagent 都吃一遍**。

所以分两层：

| 层 | 住哪 | 装什么 | 谁读得到 |
|---|---|---|---|
| **内核（常驻）** | `rules/global/` | 不变量：**不看具体技术栈也必须遵守**的那句话 | 所有 session + 所有 subagent，自动 |
| **按需（不常驻）** | `references/` | 配方、案例档案、某类问题的调试法 | 规则里那行指针触发时，模型自己去 `~/claude-kit/references/…` 读 |

判据：**「不读也不能违反」的进内核；「遇到这类问题才用得上」的下沉。**
每条下沉都在规则里留一行**带触发条件的指针 + 一句话版本**——一句话版本要足够让你判断
「这次要不要去读」，指针失效或没人指向的 reference 都会被测试挡下。

`tests/test-rules-budget.sh` 给常驻层一个**硬上限**：⭐ 要新增一条常驻规则，先压缩或下沉一条。
⛔ 因为红了就调高上限，正是这道闸防的事。

> ⭐⭐ **page-in 实测过了，而且两个宿主不一样**（2026-09-05，`tests/canary-page-in.sh`）：
> **Claude 4/4**——指针在触发情境下会真的去读，无关问题上不读；**Codex 0/2 正例**——它不去读。
> 两个替代解释都已排除：规则**确实注入了**（`~/.codex/kit-state` 有那几次的 SessionStart 记录，
> 6 条规则），sandbox 也**读得到**那个路径（codex 会话里 `head` 成功）。
> ⇒ **下沉是 Claude 侧的优化；在 Codex 上被下沉的内容等于没有，只剩规则里那一行。**
> 所以那一行必须是**能独立执行的完整指令**，⛔ 不能写成勾人去读的引子。

## 布局

**机制骨架**（很少变，手写）：

```
install.sh      机器级安装：--target claude|codex|all（默认 all）
bin/kit         助手 (config/list/add/remove/sync/status/state/doctor/memory-link/docs-sync)
lib/assets.sh   单一真源：这个 kit 有哪些资产、各自开没开（bin/kit 与 install.sh 共用）
lib/docs_sync.py  ⭐ 下面那张清单的生成器 —— README 不再手抄资产
kit.conf        开关，只记「例外」；跟仓库走 ⇒ 换机器同一套开关
codex/          Codex 端要换形状的那几个资产（cross-ai skill / executor.toml）
docs/CODEX.md   Codex 安装、资产映射、trust 与限制
tests/          回归。CI 在**普通 push 上只跑 ubuntu**，macOS 只在 PR / workflow_dispatch
                （`.github/workflows/tests.yml` 的 `if:`）。⭐ 这个方向是对的：2026-09-04 那批
                bug 全部在 macOS 上不可见 —— 别把「本机绿」当成 CI 绿。
```

**资产清单**（下面整块由 `kit docs-sync` 从资产本身生成，`--check` 在测试里把关；
⛔ 别手改块内文字，改各自文件头的 `kit-summary` / `claude-kit rule ·` 行）：

<!-- BEGIN GENERATED: kit inventory · `kit docs-sync` -->

安装后 **Claude 端**：5 条常驻规则 · 7 个 skill · 1 个 agent · 4 个 hook。
**Codex 端**：同 5 条规则 · 5 个 skill · 1 个 agent（hook 注册形状见 [`docs/CODEX.md`](docs/CODEX.md)）。
回归测试 13 套。

**`rules/global/`** — 常驻内核，同一正文到达两个宿主及子 agent。实测 18,230 字节，每个 session 和每个 subagent 都吃。
- `coding-practice` — 静默降级最贵 · 走宿主正规入口 · 重试粒度对准失败阶段 · 正向断结构 · 默认往安全倒
- `git-and-style` — push 必问 · 显式路径 stage · 别人的改动不动 · stash A/B 前台独占 · 中英不劈词
- `long-task-monitor` — 先分家 harness 托管 vs 外部；托管的别手写 monitor
- `memory-hygiene` — 四件套各答什么 · 计划权威按问题划界 · memory 写入五规则 · 哪条通道到得了子 agent
- `work-discipline` — 拆大改 · 数值必实测 · 下 verdict 前证明信号有解释力 · 一个事实一个真源 · 破坏前证明目标不是别名

**`rules/optin/`** — 默认关；`kit add` 按项目、`kit config on` 按机器。
- `cross-ai-review` — 只在不可逆/外发那一步之前自动起一轮（怎么做在 cross-ai skill 里，此处不复述）
- `remote-compute` — 共享 / 远端算力：可达性要实测 · 认证过期先于网络怀疑 · 共享节点留余量 · 停机前查依赖

**`references/`** — **不常驻**。规则里只留一行指针，遇到那类问题才 page in。
- `concurrency-and-worktrees.md` — 同一 repo 有别的 session 在干活时：worktree 建法、广播的分辨率极限、外发动作的天花板
- `external-task-monitors.md` — 只给 harness 管不到的任务写 monitor 时：done-condition 分级、自检、cadence
- `plan-authority.md` — 一个仓库多份计划时，谁回答「顺序/进度/下一步」，以及怎么不写出第二份
- `silent-degradation-cases.md` — 静默降级 / 没走正规入口 / 重试粒度错位的实盘案例档案
- `text-encoding-and-cjk.md` — 跨进程文本、CJK 文件名 glob 假阴性、零宽字符的自伤
- `ui-render-verification.md` — 怎么真的验证一个 UI 改动生效了：级联、陈旧进程、headless 的两个前提

**`skills/`** — 全局 skill（★ = Codex 端也装）。
- ★ `checkpoint` — The project docs-update flow for session continuity
- ★ `cross-ai` — Get an independent second opinion from another AI
- ★ `deep-dive` — 深挖：一个词展开整条工作流
-   `memory-audit` — Periodic reality-check of the auto-loaded memory
- ★ `refine-propose` — Turn what this session actually learned into ONE evidence-backed, reviewable proposal to…
- ★ `report-dashboard` — Build a leader-facing HTML report/dashboard in the canonical "report look"
-   `skill-creator` — Write or revise a Claude Code skill correctly

**`agents/`** — 全局委派角色；纪律从 rules 继承，不手抄。
- `executor` — Executes exactly ONE already-authorized, already-specified step in a fresh context window…

**`hooks/`** — 规则说不动的那几件，交给闸。
- `git-guard` — PreToolUse 两档闸 — DENY 不可逆操作，ASK 毁掉未提交工作但属正常工作法的操作
- `instructions-loaded` — 记录哪些指令文件**真的**加载了，`kit state claude` 的地面真相来源
- `wrap-up-trigger` — UserPromptSubmit — 用户说「收尾/存档/交接/接手」时确定性地注入「调 checkpoint skill」
- `gotchas-contract` — PostToolBatch — 新增的 GOTCHAS 条目必须写清 `闸: <路径>` 或 `闸: 无 — 理由`

<!-- END GENERATED: kit inventory -->

## ⭐ 新机器流程（这是 kit 存在的理由，有测试撑着）

```bash
# 机器级 —— 两条命令（默认同时安装 Claude + Codex）
git clone <this-repo-url> ~/claude-kit
~/claude-kit/install.sh

# 也可只安装一端
~/claude-kit/install.sh --target claude
~/claude-kit/install.sh --target codex

kit config                 # 看这台机器开了什么（开关随 kit.conf 从上一台继承过来）
kit config on <name>       # 想改再改；不改就到此为止
```

跑完装上什么，见上面「资产清单」那一块（生成的，不会漂）。

**三个人工动作**（install 会自己提示）：

1. `~/.local/bin` 不在 PATH → 加 `export PATH="$HOME/.local/bin:$PATH"`
2. `~/.claude/agents` 是本次新建的 → **重开一个 session** 才会被发现（rules/skills 不用）
3. Codex 重开后运行 **`/hooks`**，审核并 trust 新增或变更的 hook 定义

```bash
# 每个项目 —— clone 之后
kit sync          # 该项目 opt 过规则时；按 .claude/kit-rules 重建 symlink
kit memory-link   # 该项目把 .claude-memory 纳入了 git 时
kit doctor        # 验收两端；也可 kit doctor claude|codex
```

⚠ **不会自动回来的三样**：auto memory（除非原机器做过 `memory-link` 且已提交）·
`codex` / `agy` 的 OAuth（每台机器重来一次）· 项目侧 symlink（故意不进 git，靠 `kit sync` 重建）。

> `tests/test-fresh-machine.sh` **执行**这套流程而不是描述它：fresh HOME + **另一个路径的 clone**
> → `install.sh` → 断言所有链接解析进那个 clone → 建项目、opt-in → 删掉本机生成物再 `kit sync`
> 还原 → **搬走整个 clone** 再 `install.sh`，断言项目侧链接和全局规则都没断。
> **核心不变量：项目侧可移植链接与 hook 命令不写死 checkout 路径**，一律走
> `~/claude-kit` 别名。机器级 skill/rule/agent 链接可直指当前 checkout；整仓搬家后重跑 installer 刷新。

## memory 为什么要单独一步（换机器时唯一要留神的一层）

平台侧的 auto memory 是**机器本地**的，天然不跟项目走。`kit memory-link` 把
`~/.claude/projects/<slug>/memory/` 挪进 `<project>/.claude-memory/`（真目录，纳入项目 git）再软链回去。
memory 含私密笔记 → **项目 repo 必须私有**。

> ⚠ **`autoMemoryDirectory` 不是替代品**（2026-08-07 实测）：它只认绝对路径或 `~/` 开头；
> 相对路径与 `$CLAUDE_PROJECT_DIR/...` 都**被静默忽略**（不报错、session 照样说「已保存」，
> memory 实际落回默认目录）。也就是说提交进 repo 的 settings 只能写死本机绝对路径 ⇒ 比 symlink
> **更不可移植**。`kit status` 会把这两种情形都点出来；若某项目确实设了生效的
> `autoMemoryDirectory`，`kit memory-link` 会拒绝叠加第二套机制。
>
> ⚠ `<slug>` 由**仓库**决定，不由你站在哪个子目录决定（同一 repo 的所有 worktree 共用一个 memory 目录），
> 且用的是**解析过 symlink 的真实路径**。`kit memory-link` 按仓库根算；若算出的目录从没被任何 session
> 用过、而旁边存在名字相近的目录，它会**拒绝 link 并把候选列出来**——静默链错等于你以为 memory
> 跟着走了而其实没有。

## 某项目想用 opt-in 规则时

```bash
cd <project>
kit list                # 看菜单（全局档已生效，无需操作；下面是可选档）
kit add remote-compute  # 只要这条
kit remove remote-compute # 反悔（清单删条目 + 拆链）
kit status              # 复查
```

`kit add` 把规则名写进 **`./.claude/kit-rules`（进项目 git，可移植）**。Claude 同时在
**`./.claude/rules/kit/`（本机生成，已 gitignore）** 建 symlink；Codex 不需要这层物化，下次
session 的 rule hook 会直接读同一 manifest。保留 `.claude/kit-rules` 这个旧名是为了项目迁移零改动。

> 为什么拆两半：symlink 存的是**绝对路径**，直接提交进 repo 换台机器就是断链；而
> `@~/claude-kit/...` 那种 import 写法在项目 CLAUDE.md 里属于**外部 import**——首次弹批准框，
> **拒绝一次就永久禁用且不再提示**，是个完全静默的失败模式。清单 + `kit sync` 两者都避开。

换机器 clone 项目后跑一次 `kit sync` 即按清单重建 symlink。

## 开关：`kit config`

哪些资产在**加载时**生效，由 `kit config` 决定，不用逐项目做 opt-in 仪式：

```bash
kit config                      # 一张表：kind / name / on|off / 是否覆盖了默认
kit config on cross-ai-review   # 打开（改完自动重跑 install.sh 生效）
kit config off report-dashboard # 关闭 —— 会真的把 symlink 拆掉，不是只停止再链
```

默认：`rules/global` + `skills` + `agents` + `hooks` = **on**，`rules/optin` = **off**。
`kit.conf` **只记例外**——所以新增一个资产不需要改配置，也不会因为"没列进去"被当成关。
它进 git ⇒ 换机器是同一套开关。

> 项目级的 `kit add` 仍在：需要**只在某个项目**生效时用它；需要**这台机器上到处**生效时用 `kit config`。

## ⭐ 声明 ≠ 生效：`kit status` vs `kit state`

kit 曾经整整一年相信六条规则对项目可用，而实际上**零个项目 opt 过**。manifest、symlink、
`doctor` 三者描述的都是**意图**；只有宿主的实际加载事件能描述**什么真的进了模型上下文**。

```bash
kit status   # 声明层：这个项目 opt 了什么、链接建没建
kit state claude          # Claude InstructionsLoaded 实测
kit state codex           # Codex SessionStart/SubagentStart 实测，含规则 SHA-256
kit state codex --json
```

`kit state` 会显式指出「清单里声明了、但从没观察到加载」的规则——这正是当年那个盲区的探测器。
Claude 记录在 `~/.claude/kit-state/instructions.jsonl`；Codex 记录在
`~/.codex/kit-state/instructions.jsonl`，并保存每条规则当时的 SHA-256，所以能指出「加载后正文已改」。

## git-guard 两档

一个会拦住你正常工作法的闸会被关掉，关掉就什么都不保护了。所以分两档：

| 档 | 行为 | 覆盖 |
|---|---|---|
| **DENY** (exit 2) | 直接拦，Claude 必须换做法 | `git add -A/-u/--all/.`、`commit -a/--all`、`commit --no-verify/-n`、`clean -f`、`push --force`（`--force-with-lease` 放行） |
| **ASK** | Claude 弹确认；Codex 先 deny，用户明确授权后带 bypass 重跑 | `reset --hard`、`checkout .` / `restore .`、无 pathspec 的 `git stash`、`stash clear` |

逃生口（需用户明确授权，且写在命令里可审计）：`CLAUDE_KIT_GIT_GUARD_BYPASS=1 git add -A`

Codex 这样处理 ASK 是平台约束：当前 `PreToolUse permissionDecision: "ask"` 会被标成 hook 失败并
继续执行，不能当安全闸。所以 adapter 采用 exit 2 fail-closed，不伪装成已弹授权。

⛔ **定位：它是防手滑的 guardrail，不是 security boundary。** 它 regex 解析一条 shell 命令串，
`bash -c "git add -A"` 这类已知缝隙是接受的（正文里写着）。对它存在的目的——agent 在压力下的
一次手滑——非常有效；但**永远不要**把「闸没响」当成「这个调用方被授权做这件事」。

## 与项目级 CLAUDE.md / AGENTS.md 的关系

用户级（本 kit）只放跨项目稳定规则；项目专属（架构、术语、跑实验 hard rule）仍写各自
`CLAUDE.md` / `.claude/CLAUDE.md` 或 `AGENTS.md`。安装 Codex adapter **不会覆盖或改写**
`~/.codex/AGENTS.md`；kit 规则由 hook 叠加进 developer context。想覆盖通用规则，在项目侧写更具体的版本。

"项目 CLAUDE.md 会腐"的教训恰是这个架构的动机：腐烂的根因是规则正文被复制进多个项目、
各自漂移。本 kit 里正文单一真源、别处只有链接——改一处，处处生效。

## 平台支持

- **macOS / Linux = 一等公民**（CI 双平台跑全套测试；`bin/kit` 不依赖 GNU `readlink -f`）。
- **Windows → 用 WSL**。原生 Windows 未支持：Git Bash 的 symlink 默认退化成复制（破坏"改 kit 即生效"）。
- 机器状态自检：`kit doctor`（链接/hook/依赖/平台一次看全）。

## 依赖

Claude 端 `/cross-ai` 需 `codex` CLI；Codex 端 `cross-ai` 需 `claude` CLI。可选第三谱系需
`agy`（Antigravity CLI）。缺失时 skill 必须声明降级，不得把单模型分析称为 cross-check。
`kit` helper 纯 bash + python3。

## 致谢

`agents/executor.md` 的角色形态与 git-guard 的破坏性操作清单，参考了
[PrimeIntellect-ai/prime-agent](https://github.com/PrimeIntellect-ai/prime-agent)（MIT）的
`AGENTS.md` 与 continual-harness 设计。只借了思路与个别措辞，无代码移植。

> 前身说明：早期的 `/stress`·`/codex-stress`·`/gemini-stress` 三件套已退役并入 `/cross-ai`
> （保留 post-flight 验证、数值必实测、修复前先呈统一清单、agy 冷读配方）。旧实现在 git 历史里。
