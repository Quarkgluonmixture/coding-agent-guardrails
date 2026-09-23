---
name: report-dashboard
description: 'Build a leader-facing HTML report/dashboard in the canonical "report look" — light paper background, Charter serif headings, visual-first components (stat tiles / colbox comparison / keep-out boxes / flow steps / ladder status list), low prose, no jargon. Start from the bundled template.html. Triggers: "dashboard", "简报", "给 leader 的报告页", "汇报页面", "做个 HTML 报告", building any single-page HTML brief for a decision-maker.'
---

# /report-dashboard — leader-brief 的固定形态

给决策者的单页 HTML 简报。风格法则：**白纸报告感**（不是 SaaS 后台），**结论先行、组件承重、
prose 极少、不堆术语**。打印/存 PDF 直接可用（模板已带 print CSS）。

## Workflow

1. **Copy the bundled `template.html`**（与本 SKILL.md 同目录；symlink 环境下真身在
   `~/claude-kit/skills/report-dashboard/`）到目标项目的 dashboard 目录（惯例
   `docs/dashboard/<slug>.html`）。`{{…}}` 全部替换，用不到的组件整段删掉。
2. **信息架构先于填空**：masthead 的 h1 = 这页的唯一结论（一句话，重点词 `<span class="hl">`）；
   每个 section 回答一个问题，编号 01/02/03；证据/出处进 `.callout`（给可复查的锚点——命令、
   文件路径、数据来源）。
3. **数字必须实测**：stat tile 里的每个数字都要能溯源（工作纪律里的数值规则同样适用于简报）。
4. **迭代直接编辑本地文件**，让用户在自己浏览器里刷新看——**不要**每轮改动重发 Artifact/截图；
   只有用户要分享链接时才发布。
5. 手机也可读（模板 ≤920px 自动单列），发出前想一眼窄屏。

## 组件选型（一个信息一个组件，别都用）

| 要表达什么 | 用 | 备注 |
|---|---|---|
| 3-4 个关键数字 | `.stats` stat tiles | 数值大字 serif；每 tile 一句注解 |
| 方案/选项对比 | `.triple` colbox | 我们的方案用 `.ours`（绿，带阴影强调）|
| 是什么 vs 不是什么 | `.sent` keep/out 双盒 | 澄清误解的利器（"integration yes, implementation no"）|
| 流程/管线 | `.flow` fstep | 关键步骤加 `.hot` |
| 状态清单/逐项确认 | `.ladder` rung | 右侧 `.loc ok/warn` 状态胶囊 |
| 风险与待决 | `.grid2` + `.card warn` | 开放问题永远单独一节，别藏 |
| 结论的出处 | `.callout` | 每个 section 至多一个 |

## 颜色语义（class 名保持稳定，别改名——与既有简报语料互拷兼容）

`.ours`=绿（我们的/positive/confirmed） · `.mt3`=青（info/参照物） · `.v4`=琥珀（caution/旧方案）
· `.no`=红（negative/排除）。legend 里向读者声明本页的映射。配色改动只动 `:root` 变量。

## 语言与口径

- 中文承重结论，`file:line`/命令/数字用英文 mono；杜绝内部代号裸奔——首次出现给一句人话解释。
- 每个 section 的 `.sec-sub` 用一句话教读者"怎么读这块"。
- 诚实优先：估算标注"估算"，未决标注 open——简报的信用比好看重要。
