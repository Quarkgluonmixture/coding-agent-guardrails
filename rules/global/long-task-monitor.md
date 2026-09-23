<!-- claude-kit rule · long-task-monitor — 先分家 harness 托管 vs 外部；托管的别手写 monitor -->
## 长任务完成信号

**第一步永远是判断：这个任务 harness 追踪得到吗？**

- **Harness 托管**（后台命令 session、Agent、Workflow、Task 系）：完成会**自动通知**。
  **不要**再手写轮询 monitor、不要 `sleep` 等、不要额外起 until-loop —— 纯浪费 token。
  也**不要** `setsid nohup` 把任务藏出 harness 视野（daemonize = 完成无信号）；直接用宿主提供的
  后台执行或可恢复 session 让 harness 管。

- **外部任务**（harness 管不到：远端 qsub/squeue、远端 docker、CI run、别的机器上的进程）：
  这才需要显式 monitor。**写之前读 `~/claude-kit/references/external-task-monitors.md`**
  —— done-condition 分级、3 条自检、cadence 表都在那里。

⭐ 只记住一条也够避开最常见的死法：**别用 pattern 自匹配**（`until ! pgrep -f "<X>"`，而 `<X>`
就出现在 monitor 自己的命令串里 → 匹配到自己 → 永远 STILL_RUNNING，`grep -v grep` 救不了）。
优先用输出文件 marker，并且**永远配一个 max-wait 兜底**。
