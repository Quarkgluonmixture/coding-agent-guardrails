# Proposal: <一句话，动词开头，写行为变化不写实现>

- **date**: <YYYY-MM-DD>
- **target**: <确切落点，如 `rules/global/git-and-style.md` · `hooks/git-guard.sh` · `skills/<name>/SKILL.md` · `agents/<name>.md` · `memory/<name>.md` · `<project>/CHECKPOINT.md`>
- **layer**: <hook | global-rule | optin-rule | skill | agent | memory | project-doc>
- **kit_commit**: <`kit state --json` 里的 kit_commit，用于日后定位当时的 harness>
- **confidence**: <high | medium | low>

## Problem

<发生了什么。一段。写现象和代价，不写解法。>

## Evidence

<这个 session 里真实发生的事。至少一条，越具体越好：>

- <失败/纠正/实测数字，带 `file:line`、命令、或用户原话>
- <如果是"第二次发生"，把第一次也指出来（LOG 条目 / 之前的 commit / memory 条目）>

## Competing explanations

<还有什么别的原因能解释同样的现象？逐条写，并说明为什么排除。>
<只有一个解释、且没试着找第二个 ⇒ confidence 最高只能是 medium。>

## Proposed change

<确切要写什么。规则/hook 就把最终文案写出来，别写"加一条关于 X 的规则"。>

```
<最终文案 / patch 片段>
```

## Why not just this project?

<⭐ 目标是全局资产时的硬门槛。答不上来就把 layer 降一级重写这份提案。>
<要回答的是机制问题：这条约束依赖的前提，在别的项目里也成立吗？>

## Possible regressions

<这条改动会在什么情况下变成噪音、误报、或者挡住正常工作？>
<对 hook 提案尤其要写：会不会拦住用户真在用的工作法？>

## Validation plan

<怎么知道它生效了 —— 可执行的检查，不是"观察一段时间"。>

- <例：`kit state` 在目标项目里能观察到该规则加载>
- <例：给 guard 加一条测试用例，断言 deny/ask/allow>
- <例：删掉某个 agent 文件里的手抄段落，确认行为不变>

## Rollback

<怎么撤。通常是 `git revert <commit>` + `install.sh`；若涉及 settings.json 或项目侧 symlink，写清额外步骤。>
