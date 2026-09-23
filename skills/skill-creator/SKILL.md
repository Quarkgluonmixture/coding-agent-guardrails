---
name: skill-creator
description: Write or revise a Claude Code skill correctly — where it lives, what the frontmatter can do, how to write the description so the router actually finds it, and what belongs in the body vs a references/ file. Also covers the claude-kit conventions for skills that ship globally.
when_to_use: Creating a new skill, fixing one Claude never picks up on its own, turning a repeated procedure or a bloated CLAUDE.md section into a skill, or asking where skills live and which frontmatter fields exist.
---

# /skill-creator — 写一个真的会被用上的 skill

一个 skill = 一个目录 + 一个 `SKILL.md`（YAML frontmatter + markdown 正文）。
**启动时只有 name 与 description 进上下文；正文在被用到时才加载。**
这条力学决定了下面每一条建议。

## 先确认它该是个 skill

| 它是什么 | 该放哪 |
|---|---|
| 每个 session 都要成立的**事实/约束** | CLAUDE.md 或 rules（常驻，且 rules 能到子 agent） |
| "绝不能发生"、且能用命令模式识别 | **hook**（规则会被忘，hook 不会） |
| 一套**按需展开的多步流程** | ✅ **skill** |
| 反复出现的委派角色 | agent |

判不准 → 用 `/refine-propose` 的路由表。**CLAUDE.md 里长成流程的那一节，就是 skill 的原料。**

## 放哪

| 位置 | 范围 |
|---|---|
| `~/.claude/skills/<name>/SKILL.md` | 个人级，所有项目 |
| `.claude/skills/<name>/SKILL.md` | 项目级，跟仓库走 |
| `.claude/commands/<name>.md` | 旧式单文件命令，仍可用；新写一律用 skill 目录 |

**claude-kit 约定**：正文放 `claude-kit/skills/<name>/`，`install.sh` 自动 symlink 进
`~/.claude/skills/`——**不要在 `~/.claude/skills/` 下直接建目录**，那会脱离版本控制。
装完即生效，不用重启。

## Frontmatter

必填其实一个都没有：`name` 缺省取目录名，`description` 缺省取正文首段。但**两个都要写**，
因为路由只看得见它们。

```yaml
---
name: my-skill
description: <做什么 + 什么时候用>
when_to_use: <触发短语、例子请求>
---
```

⭐ **硬上限：`description` + `when_to_use` 合计 1,536 字符**，超出部分在 skill 列表里被截断。
触发短语写进 `when_to_use`，别再塞进 description。

其余字段（`disable-model-invocation` · `user-invocable` · `allowed-tools` · `model` · `effort` ·
`context: fork` · `paths` · `argument-hint` 等）见 [references/frontmatter.md](references/frontmatter.md)——
只在你确实要用时才需要读。

### description 是写给路由器的，不是写给人的

它是模型决定"要不要加载"时唯一看得见的东西。**写清楚做什么 + 什么情况下该用**，
把具体任务、工具名、会出现的措辞点出来。

- ✅ `Extracts text and tables from PDFs, fills forms, merges files. Use when working with PDF documents.`
- ❌ `Helps with PDFs.`

写完自问一句：**用户不提这个 skill 的名字，只描述问题，模型能凭这段话选中它吗？**

### 正文与 references/

正文只放：决策流、常用命令、契约、硬规矩。
推进 `references/*.md` 的是：**只有部分运行才需要的材料**——完整字段表、可选分支、长示例、API schema。

> ⚠ 别机械拆分。正文本来就按需加载，把每次都要用的步骤拆出去只是多一次文件读取。
> 判据是"这段是不是**只有某些运行**才需要"，不是"正文有多长"。

## 验证

1. 目录名 = 你想输入的命令名（`/my-skill`）。
2. `description` 非空、且合计未超 1,536。
3. 新 session 里 skill 列表出现它；或直接 `/my-skill` 调用。
4. 更狠的一步：**换一种说法描述问题、不提名字**，看模型会不会自己选中它。选不中 = description 写坏了。

## claude-kit 专属

- 全局 skill 的 name+description **每个 session 都进上下文**——少而精，别为一次性流程建全局 skill。
- 带脚本的 skill（如 `/cross-ai` 的 `agy_clean.sh`）：`install.sh` 会 `chmod +x`，
  但**脚本行为要在 `tests/` 里有回归**，否则换机器后坏了没人知道。
- 改完在 kit 里编辑即生效（symlink 指的就是 kit 正文），不要另存副本。
