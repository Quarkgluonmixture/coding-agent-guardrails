<!-- claude-kit reference · external-task-monitors — 只给 harness 管不到的任务写 monitor 时：done-condition 分级、自检、cadence -->
# 外部长任务的 monitor 配方

**触发**：`rules/global/long-task-monitor.md` 已经判定这是**外部任务**（远端 qsub/squeue、
远端 docker、CI run、别的机器上的进程 —— harness 收不到完成通知）。
⛔ harness 托管的任务（后台命令 session、Agent、Workflow、Task 系）不适用本文，
它们完成会自动通知，手写 monitor 是纯浪费。

## done-condition 分级（从最 robust 到最 zombie-prone，优先高 tier）

- 🥇 **Tier 1 输出文件 marker**：`[ -s out.json ]` / `[ -f .done ]` / `grep -q DONE log`
- 🥈 **Tier 2 远端 job 状态**：`! <remote> "qstat/squeue/..." | grep -q "<JOB_ID>"`（注意 ssh 超时）
- 🥉 **Tier 3 PID liveness**：启动 `cmd ... & PID=$!`，监控 `! kill -0 $PID 2>/dev/null`（真 PID，不自匹配）
- 🚫 **禁止 pattern 自匹配**：`until ! pgrep -f "<X>"`，当 `<X>` 出现在 monitor 自己的 bash 命令里
  → pgrep 匹配到自己的 `bash -c` eval → 永远 STILL_RUNNING。`grep -v grep` 救不了
  （自己的命令串就含 X）。

## 写之前 3 条自检

1. done-pattern 字符串会出现在 monitor 命令本身吗？→ 是则切 Tier 1/2/3。
2. 有 max-wait 兜底吗？→ `for i in $(seq 1 N); do <cond> && break; sleep 60; done`
   （防 done-cond 写错静默死循环）。
3. 完成后有异步通知吗？（ntfy / 推送）让人不守着也知道。

## cadence 按外部状态的真实变化速度定

| 被等的东西 | sleep |
|---|---|
| 本地文件 marker | 60–90s |
| ssh 远端查状态 | 300s |
| 本地 PID liveness | 30s |

一个 ~8 分钟的 CI run 配**一次 ~480s** 的检查，不是八次 60s。

## 其他

- **post-loop bash 只许 stat-only**（`echo` / `ls` / `tail` / `head` / 简单 `curl`）——不要在
  until-loop 后嵌 `$(python -c "...")` 之类，嵌套引号在 `bash -c` eval 里极易 syntax error →
  exit 127。compute 留给独立 run。
- monitor >2h 没 fire → 怀疑 self-match，`pgrep -af until` 找出来 kill。
