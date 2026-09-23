<!-- claude-kit reference · text-encoding-and-cjk — 跨进程文本、CJK 文件名 glob 假阴性、零宽字符的自伤 -->
# 文本编码边界 与 CJK 路径

**触发**：跨进程捕获文本（`subprocess`）、读写 JSON/日志、处理含中文的路径、
或要在源码里写不可见字符的字符类。
资格线：`rules/global/coding-practice.md` 的「文本编码边界」一行。

## 跨进程文本一律显式编码

- `subprocess` 捕获走 **bytes + 显式 decode**，⛔ 不用 `text=True`（那是**进程自己的 locale**，
  跨启动路径不稳定；踩过的实例见 `silent-degradation-cases.md` 的 subprocess locale 一条）。
- 读写 JSON / 日志写死 `encoding='utf-8'`（裸 `open()` 遇 CJK 会 GBK 崩）。
- Python 项目设 `PYTHONUTF8=1` 兜住所有启动路径。

## ⛔ 源码里别粘贴字面零宽 / 不可见字符

用 `chr()` 构造字符类——编辑器会把「意图」变成真字形，然后这份源码自己就成了注入扫描器的
误报源。

## CJK 文件名的 shell glob 陷阱

含中文的路径在部分环境里 `ls` / `find` / `wc` / glob 会**假阴性**。

```bash
git -c core.quotePath=false ls-files -z    # 取字节
```

或直接用 Python 操作。下「文件被删 / 不存在」结论前**做 bytes 级交叉验证**。
（这是 `work-discipline` 那条「负面或空结果多问一步」的一个具体形状。）
