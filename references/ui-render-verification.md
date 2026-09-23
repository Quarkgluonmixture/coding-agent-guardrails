<!-- claude-kit reference · ui-render-verification — 怎么真的验证一个 UI 改动生效了：级联、陈旧进程、headless 的两个前提 -->
# UI / 渲染验证 — 方法，不是像素信仰

**触发**：你打算说「这个样式/布局/组件改好了」，或打算用 headless 浏览器证明什么。
资格线：`rules/global/work-discipline.md` 那一行「UI 渲染验证走逻辑不走像素」。

## 基线方法

验证 = **数据在**（查库 / 调接口）+ **组件在该条件下渲染**（读代码）+ **类型检查干净**。
**像素以用户浏览器为准**：headless 结果与用户所见冲突时**信用户**，停止重跑。

headless 浏览器对 dev server（Vite 等）的文本检查会假阴性——dep-optimizer 504、
client-render 时序——⛔ 别拿它证明「没渲染」。真要看渲染：production build
（`vite build` + `preview`）+ 等**具体 locator**，不 grep 全文。

## ⭐⭐ 级联 / computed-style 的问题 grep 答不了

grep 源码或产物只证明这条声明**存在**，不证明它**赢**。

实例：`.home a{color:inherit}` 特异度 0,1,1 压过 `.pri{color:#fff}` 0,1,0。那个 hex 一直在
chunk 里 ⇒ grep 报「已修复」，而用户说了两次「没变化」。

⇒ 样式问题要**渲染后的输出**：production build 截图去看，或走 CDP 读 computed style。

## ⭐ 还要确认答你的是新进程

`next start` 之类**不会**自动捡 rebuild；重启还可能 `EADDRINUSE` **静默失败**而旧进程照常应答
⇒「我重新构建后验证过」可能是陈旧读数。按端口确认再信：

```bash
lsof -nP -iTCP:<port> -sTCP:LISTEN
```

## ⭐ headless 对 layout 可靠的两个条件（要同时成立）

1. production build；
2. CDP 真机模拟：`Emulation.setDeviceMetricsOverride { mobile: true }`。

⛔ 只用 `--window-size` 会**忽略 viewport meta**，报出幻影横向溢出。

模拟能对 layout，对触感 / 字体渲染不对 ⇒ 最终仍以用户的手机为准。
