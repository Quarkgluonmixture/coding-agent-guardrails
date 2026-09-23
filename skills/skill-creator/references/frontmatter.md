# SKILL.md frontmatter — 完整字段

核对于 Claude Code 官方文档，2026-08-07（CLI v2.1.224）。Claude Code 遵循
[Agent Skills](https://agentskills.io) 标准并加了若干扩展；下表标注哪些是扩展。

## 路由相关（几乎总要写）

| 字段 | 必填 | 说明 |
|---|---|---|
| `name` | 否 | skill 列表里的显示名，**缺省取目录名**。你输入的命令名由目录名决定 |
| `description` | 建议 | 做什么 + 何时用。**缺省取正文首段**。⭐ 与 `when_to_use` 合计在列表里**截断于 1,536 字符** |
| `when_to_use` | 否 | 触发短语、例子请求。追加在 `description` 之后，**共用那 1,536 上限** |
| `argument-hint` | 否 | 自动补全时的参数提示，如 `[issue-number]` |
| `arguments` | 否 | 具名位置参数，供正文里 `$name` 替换。空格分隔字符串或 YAML 列表 |

## 调用控制（Claude Code 扩展）

| 字段 | 说明 |
|---|---|
| `disable-model-invocation` | `true` = 模型不会自动加载，只能 `/name` 手动触发。**同时会阻止它被 subagent 的 `skills:` 预载**，也阻止它作为 scheduled task 的 prompt 运行 |
| `user-invocable` | `false` = 从 `/` 菜单隐藏。用于「只给模型看的背景知识」 |
| `paths` | glob 列表；设了之后**只在处理匹配文件时**才自动加载。格式同 path-scoped rules |

## 执行环境（Claude Code 扩展）

| 字段 | 说明 |
|---|---|
| `allowed-tools` | 本轮内免权限询问的工具。**下一条用户消息即失效** |
| `disallowed-tools` | 本 skill 活跃期间从工具池移除的工具。适合自治型 skill 屏蔽 `AskUserQuestion` |
| `model` | 本 skill 活跃期间的模型；本轮结束即恢复会话模型。可用 `inherit` |
| `effort` | 同上，`low`/`medium`/`high`/`xhigh`/`max`，取决于模型 |
| `context: fork` | 在**分叉的子 agent 上下文**里跑（继承父会话） |
| `agent` | 配合 `context: fork`，指定用哪个 subagent 类型 |
| `background` | 仅在 `context: fork` 下有意义；`false` = 在本轮内等结果，不后台跑。需 v2.1.218+ |
| `hooks` | 绑定到本 skill 生命周期的 hook |
| `shell` | `bash`（默认）或 `powershell`，决定正文里 `` !`cmd` `` 用哪个 shell |

## 元数据（接受但不影响行为）

| 字段 | 说明 |
|---|---|
| `metadata` | 自定义 key-value map，供你自己的工具读取。值不是 map 会被丢弃；别复用已有字段名 |
| `license` | Agent Skills 标准字段 |
| `compatibility` | 环境要求，≤500 字符。Agent Skills 标准字段 |

## 容易踩的三点

1. **`description` 不是必填，但缺省行为是取正文首段** —— 首段若是一句寒暄，路由就废了。
2. **1,536 是 `description` + `when_to_use` 合计**，不是各自。触发短语堆太多会把正事挤掉。
3. **`disable-model-invocation: true` 有连带影响**：这个 skill 就不能再被 subagent 的
   `skills:` 字段预载了。要给某个 agent 预载全文的 skill，别设这个字段。
