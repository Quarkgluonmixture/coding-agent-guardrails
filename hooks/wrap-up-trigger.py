#!/usr/bin/env python3
# kit-summary: UserPromptSubmit — 用户说「收尾/存档/交接/接手」时确定性地注入「调 checkpoint skill」
"""UserPromptSubmit hook: an explicit, short wrap-up / resume instruction from the
user puts "invoke the checkpoint skill now" into context. Deterministic where the
natural-language router is probabilistic.

Why (2026-09-03)
----------------
The checkpoint skill lists its trigger words and relies on the model to route to
it. Measured on this machine: 481 transcripts, the skill was invoked in 35 (7%).
The user's requirement: when they say 收尾 at the end of a session, the skill
must fire. Hooks cannot invoke a skill (docs: only command/http/mcp_tool/prompt/
agent types), but a UserPromptSubmit hook's stdout on exit 0 is added to
Claude's context. So this hook turns an explicit instruction into an unmissable
"call the Skill tool now". Typing `/checkpoint` remains the 100% path.

Contract (v2, after two independent reviews)
--------------------------------------------
v1 matched a keyword anywhere in the prompt. Measured on 2,557 real prompts:
127 hits, ~42 of them not wrap-up requests (pasted status text, file names like
…_Handoff_….md, executor task packs carrying a `Handoff` identifier, 存档
meaning "archive", 接手机). A false fire is not "one extra skill load": it asks
the model to start a flow that edits LOG/TODO/CHECKPOINT. So the contract is
now "the prompt IS a short instruction", which is also what the user said:

  fire  ⇔  (stripped prompt ≤ 40 chars AND it STARTS with a trigger word,
            after at most 4 filler chars such as 好，/ 先 / 那)
        OR (stripped prompt > 40 chars AND a trigger word sits in the LAST 20 chars)

  triggers: 收尾 · 存档 · 交接 · 接手(not 接手机) · 记录这个坑 · 又踩了一次 · update gotchas
  ⛔ no bare English (wrap-up / handoff had 0 true hits out of 12; "checkpoint"
     and "resume" collide with ML/download vocabulary)

Everything else is silent. "把构建产物存档到 S3" (short, does not start with the
word) → silent. "…然后收尾" at the end of a long message → fires. "先别收尾" →
fires; the injected text tells the model to ignore it if the user is clearly
asking NOT to wrap up (a hook detects words; intent stays with the model).

I/O
---
- Reads stdin as UTF-8 bytes and writes bytes: locale must not decide whether
  Chinese triggers work (kit coding-practice: explicit encoding at process edges).
- Never exit 2 (that erases the user's prompt). Malformed input → one ASCII line
  on stderr + exit 1: docs say non-2 exit codes are non-blocking errors, the
  prompt proceeds, the user sees a hook-error notice.
- The trigger list is the single source for the natural-language path; the
  checkpoint skill body points here. `--triggers` prints it for tests.

Self-test: --self-test (negatives first, drawn from the real false positives).
"""
from __future__ import annotations

import json
import re
import sys

TRIGGERS = ["收尾", "存档", "交接", "接手", "记录这个坑", "又踩了一次", "update gotchas"]
_ALT = r"收尾|存档|交接|接手(?!机)|记录这个坑|又踩了一次|update\s+gotchas"
FILLER = r"[\s,，。.!！:：、好那先请就OKok的]{0,4}"
HEAD = re.compile(rf"^{FILLER}(?:{_ALT})", re.I)
TAIL = re.compile(rf"(?:{_ALT})", re.I)
SHORT = 40
TAIL_WINDOW = 20

MESSAGE = (
    "kit: the user's message is an explicit checkpoint instruction "
    "(收尾 / 存档 / 交接 / 接手 / 记录这个坑 / update gotchas). Invoke the `checkpoint` skill via the "
    "Skill tool as your FIRST action and follow it: wrap-up mode for 收尾/存档/交接, resume mode for "
    "接手, the GOTCHAS step for 记录这个坑. Do not improvise the CHECKPOINT/TODO/LOG/GOTCHAS update "
    "from memory; the skill is the single procedure. Ignore this line only if the user is clearly "
    "asking NOT to wrap up."
)


def decide(prompt: str) -> bool:
    p = prompt.strip()
    if not p:
        return False
    if len(p) <= SHORT:
        return HEAD.search(p) is not None
    return TAIL.search(p[-TAIL_WINDOW:]) is not None


# stdin is already read as bytes; stdout/stderr need the same treatment. Both the
# trigger list and the self-test's case names are Chinese, so on an ASCII-locale
# launch path a bare print() raises UnicodeEncodeError — and for a UserPromptSubmit
# hook that means the checkpoint injection silently never happens (fail-open).
for _s in (sys.stdout, sys.stderr):
    try:
        _s.reconfigure(encoding="utf-8", errors="replace")   # type: ignore[union-attr]
    except (AttributeError, OSError):
        pass


def main(argv: list[str]) -> int:
    if "--triggers" in argv:
        sys.stdout.write("\n".join(TRIGGERS) + "\n")
        return 0
    if "--self-test" in argv:
        return self_test()
    raw = sys.stdin.buffer.read() if not sys.stdin.isatty() else b""
    try:
        payload = json.loads(raw.decode("utf-8", "replace") or "{}")
        if not isinstance(payload, dict):
            raise ValueError("payload is not a JSON object")
        prompt = payload.get("prompt", "")
        if not isinstance(prompt, str):
            raise ValueError("prompt is not a string")
    except (ValueError, json.JSONDecodeError) as exc:
        sys.stderr.buffer.write(f"wrap-up-trigger: unreadable hook input ({exc.__class__.__name__}); "
                                f"checkpoint skill NOT auto-invoked\n".encode("ascii", "replace"))
        return 1
    if decide(prompt):
        sys.stdout.buffer.write(MESSAGE.encode("utf-8") + b"\n")
    return 0


def self_test() -> int:
    long_pad = "这是一段很长的粘贴文本，" * 6
    cases = [
        # negatives — each one is a real or reviewer-constructed false positive of v1
        ("plain question", "为什么这个测试会红？", False),
        ("ML checkpoint (English excluded)", "load the model checkpoint from step 4000", False),
        ("resume a download", "resume the download please", False),
        ("this hook's own file name", "请审查 wrap-up-trigger.py", False),
        ("archive meaning, not at head", "把构建产物存档到 S3", False),
        ("business handover, not at head", "让 Alice 接手这个模块", False),
        ("接手机 must not fire", "接手机看看有没有消息", False),
        ("unwrapup substring", "unwrapup is not a command", False),
        ("executor pack with Handoff identifier", "This is the bounded implementation round. PaymentLiveHandoffBridge must stay green.", False),
        ("long paste, word in the middle", long_pad + "收尾感很强的一段" + long_pad, False),
        ("long paste, file name near end", long_pad + "see docs/Signing_Handoff_2026-08-08.md", False),
        ("word only in cwd, not prompt", "ls", False),
        ("empty", "   ", False),
        # positives — the user's actual shapes
        ("收尾", "收尾", True),
        ("好，收尾 session", "好，收尾 session", True),
        ("先存档", "先存档", True),
        ("存档,然后开工 (real prompt)", "存档,然后开工,研究侧在跑", True),
        ("接手 (resume)", "接手", True),
        ("记录这个坑", "记录这个坑", True),
        ("update  gotchas (double space)", "update  gotchas", True),
        ("long message ending with 然后收尾", long_pad + "改完这个之后然后收尾", True),
        ("long message ending with 先别收尾 (fires; model told to ignore)", long_pad + "先别收尾", True),
    ]
    bad = 0
    print("self-test:")
    for name, prompt, expect in cases:
        got = decide(prompt)
        print(f"  {'ok  ' if got == expect else 'FAIL'}  {name}")
        bad += 0 if got == expect else 1
    # I/O path: malformed input must exit 1, never 2, never crash
    import subprocess
    me = sys.argv[0]
    for name, raw, want_rc, want_out in [
        ("malformed JSON → exit 1, no output", b"{not json", 1, False),
        ("top-level array → exit 1", b"[1,2]", 1, False),
        ("non-string prompt → exit 1", b'{"prompt": 5}', 1, False),
        ("valid trigger → exit 0 + message", '{"prompt":"收尾"}'.encode(), 0, True),
        ("latin-1 garbage bytes → exit 1 or silent, never crash", b'{"prompt":"\xff\xfe"}', None, False),
    ]:
        cp = subprocess.run([sys.executable, me], input=raw, capture_output=True)
        ok = (want_rc is None or cp.returncode == want_rc) and (bool(cp.stdout.strip()) == want_out) and cp.returncode != 2
        print(f"  {'ok  ' if ok else 'FAIL'}  {name}  (rc={cp.returncode})")
        bad += 0 if ok else 1
    print("self-test: PASS" if not bad else f"self-test: {bad} FAILURE(S)")
    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
