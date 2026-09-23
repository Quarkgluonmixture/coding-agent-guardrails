#!/usr/bin/env python3
# kit-summary: PostToolBatch — 新增的 GOTCHAS 条目必须写清 `闸: <路径>` 或 `闸: 无 — 理由`
"""PostToolBatch hook: a NEW GOTCHAS entry must say what its gate is, or why none can exist.

Why (2026-09-03)
----------------
The kit's own doctrine (skills/checkpoint/SKILL.md, discipline 3, since 2026-08-09)
says: a trap a command can recognise goes into a hook / test / assertion, not
prose. Measured: the skill is invoked in 7% of sessions; most sessions that edit
a GOTCHAS.md never invoke it. So "can this be a gate?" is asked at a minority of
the moments it is meant for, and the answer is never written down — which is how
"numbers only from the engine" was written as prose and violated by its author
30 minutes later.

This hook does not judge whether a gate is possible (a script cannot). It
enforces that the question was ANSWERED, in the entry, when the entry was written.
Forgetting is what it prevents; an insincere answer it cannot, and says so.

Contract (what a NEW entry must contain)
----------------------------------------
  闸: docs/evidence-sources/gate_x.py     relative path, resolves to a FILE inside this
                                          repo (not `.`, not absolute, not ../sibling)
  gate: .claude/hooks/post-write          same, English key
  闸: 无 — <why a machine cannot decide this, ≥ 6 chars>
  also accepted: 没有 / N/A / 无法做成闸，<reason>
  legacy forms so existing repos pass without rewrites:
    "已升级成闸" / "已做成闸" + a backticked in-repo path            → OK
    "做不成闸" / "无法做成闸" / "not gateable" / "judgement-only"    → OK

Coverage semantics (checkpoint skill): `闸: <path>` is for PARTIAL coverage — say
which half the gate does not cover. An entry a gate covers completely retires to a
tombstone (the tombstone carries the path). The hook accepts either; the split is
a human's call.

Entry head forms recognised (five real-world GOTCHAS files, three shapes):
    **12 · title**   /  **G-01 · title**      projects A, B
    ### 12. title                              projects C, D (## / #### too)
    12. ⭐⭐ **title**                          project E — only in a file with NO explicit heads,
                                               only after a blank line or heading, only unseen ids
                                               (otherwise a bold numbered sub-list inside an entry
                                               would be split into entries — it was, in v1)
`--audit <file>` shows what was parsed. 0 entries parsed = silent hook = NOT covered.

Baseline (v2 — both reviews caught the v1 hole)
-----------------------------------------------
v1 grandfathered every entry it saw on its first run. Under this workspace's
launch layout (sessions start in the parent dir), the first bad entry written
via a Bash heredoc was exactly the thing the "first run" then grandfathered.
Now:
  - tracked file → baseline = the entry ids in `git show HEAD:<file>` at the moment
    the state is first created. Anything not in that snapshot is checked. Later
    commits do NOT extend the baseline (an entry committed without passing stays
    "new" until it declares its gate).
  - untracked / gitignored / no git → baseline is EMPTY: every entry is checked
    until someone runs `--seed <file>`, which records the current ids as accepted.
    The red message says so. Fail-closed by default; acceptance is an explicit act.
  - state lives in ~/.claude/kit-state/gotchas/<sha>.json, written atomically;
    unreadable state ⇒ exit 2 with the path (never a silent re-baseline).

Reach: finds GOTCHAS.md / docs/GOTCHAS.md from the payload's file_path, from cwd
(walking up to the nearest .git, never past $HOME), and — for Bash — from any
`…GOTCHAS.md` token in tool_input.command (a parent-dir heredoc names the file).

Red ⇒ exit 2 with the missing ids and the contract on stderr (Claude Code shows it
to the model; the write already happened — this is strong feedback, not a veto).
Internal errors ⇒ exit 2 with traceback.

Usage
-----
    --self-test                      negatives first
    --audit <GOTCHAS.md>             classify every entry, no state written
    --seed  <GOTCHAS.md>             accept current ids as baseline (untracked files)
    --state-dir DIR                  override state dir (tests, dry-runs)
    GOTCHAS_CONTRACT_TRACE=1         one-line trace on stderr
"""
from __future__ import annotations

import contextlib
import hashlib
import json
import os
import pathlib
import re
import subprocess
import sys
import tempfile
import traceback

# flock is POSIX-only. On Windows msvcrt.locking is the byte-range equivalent; the
# contract below (take the lock if we can, proceed unlocked if we cannot) is unchanged.
try:
    import fcntl
except ImportError:  # Windows
    fcntl = None
    import msvcrt

# Process edges are explicit about encoding, per the kit's own coding-practice rule.
# Every diagnostic this gate prints is Chinese; if the launch path hands us an ASCII
# locale, a bare print() raises UnicodeEncodeError and the gate reports a crash
# instead of the verdict it computed. stdin is read as BYTES for the same reason.
for _s in (sys.stdout, sys.stderr):
    try:
        _s.reconfigure(encoding="utf-8", errors="replace")   # type: ignore[union-attr]
    except (AttributeError, OSError):
        pass

HOME = pathlib.Path.home()
DEFAULT_STATE = HOME / ".claude" / "kit-state" / "gotchas"
WRITING_TOOLS = {"Write", "Edit", "MultiEdit", "NotebookEdit", "Bash"}

HEAD_EXPLICIT = [
    re.compile(r"^\*\*([A-Z]{0,2}-?\d+[a-z]?)\s*·"),           # **12 · title**   **G-01 · title**
    re.compile(r"^#{2,4}\s*(\d+[a-z]?)[.)·]\s"),               # ### 12. title
]
HEAD_LIST = re.compile(r"^(\d+[a-z]?)\.\s+(?:[^\w*\n]{0,12})\*\*")   # 12. ⭐ **title**
SECTION = re.compile(r"^#{1,2}\s")
FIELD = re.compile(r"^\s*(?:闸|gate)\s*[:：]\s*(.*?)\s*$", re.I | re.M)
NONE_VALUE = re.compile(r"^(?:无法[^\s—\-–:：,，]*|没有|无|none|no|n/?a)(?:\b|(?=[\s—\-–:：,，]|$))[\s—\-–:：,，]*(.*)$", re.I)
LEGACY_GATE = re.compile(r"已升级成闸|已做成闸|已接闸")
LEGACY_EXCUSE = re.compile(r"做不成闸|无法做成闸|not gateable|judge?ment-only", re.I)
BACKTICK_PATH = re.compile(r"`([~\w./-]+\.(?:py|sh|ts|js|yml|yaml|toml|json))`")
GATE_LIKE = re.compile(r"(?:^|/)(?:gate_|verify_|hook_|check_|guard|run_all)")
BASH_GOTCHAS = re.compile(r"([\w./~-]*GOTCHAS\.md)")


def _trace(msg: str) -> None:
    if os.environ.get("GOTCHAS_CONTRACT_TRACE"):
        print(f"[gotchas-contract] {msg}", file=sys.stderr)


# ── locating ────────────────────────────────────────────────────────────────

def repo_root_of(p: pathlib.Path) -> pathlib.Path | None:
    try:
        p = p.resolve()
    except OSError:
        return None
    if p.is_file():
        p = p.parent
    while True:
        if p == HOME or p == p.parent:
            return None
        if (p / ".git").exists():
            return p
        p = p.parent


def tool_calls(payload: dict) -> list[dict]:
    """One entry per tool call, whichever event delivered it.

    PostToolBatch (measured on Claude Code 2.1.261, 2026-09-05) carries
    `tool_calls: [{tool_name, tool_input, tool_use_id, tool_response}, ...]` plus cwd,
    session_id, prompt_id, permission_mode, transcript_path. PostToolUse carries a
    single call flattened into the payload. Normalising here keeps every caller below
    event-agnostic — and Codex, which has no batch event, keeps working unchanged.
    """
    calls = payload.get("tool_calls")
    if isinstance(calls, list):
        return [c for c in calls if isinstance(c, dict)]
    return [{"tool_name": payload.get("tool_name"), "tool_input": payload.get("tool_input")}]


def gotchas_files(payload: dict) -> list[tuple[pathlib.Path, pathlib.Path]]:
    out: dict[pathlib.Path, pathlib.Path] = {}
    cwd = pathlib.Path(payload["cwd"]) if payload.get("cwd") else None
    explicit: list[pathlib.Path] = []
    for call in tool_calls(payload):
        ti = call.get("tool_input") or {}
        if not isinstance(ti, dict):
            continue
        fp = ti.get("file_path") or ti.get("notebook_path")
        if fp:
            explicit.append(pathlib.Path(fp))
        if call.get("tool_name") == "Bash":
            for tok in BASH_GOTCHAS.findall(ti.get("command") or ""):
                p = pathlib.Path(os.path.expanduser(tok))
                if not p.is_absolute() and cwd:
                    p = cwd / p
                explicit.append(p)
    for p in explicit:
        if p.name == "GOTCHAS.md" and p.exists():
            out[p.resolve()] = repo_root_of(p) or p.resolve().parent
    starts = [p for p in explicit] + ([cwd] if cwd else [])
    for s in starts:
        root = repo_root_of(s)
        if not root:
            continue
        for cand in (root / "GOTCHAS.md", root / "docs" / "GOTCHAS.md"):
            if cand.exists():
                out.setdefault(cand.resolve(), root)
    return list(out.items())


# ── parsing ─────────────────────────────────────────────────────────────────

def parse_entries(text: str) -> list[tuple[str, str]]:
    lines = text.splitlines()
    explicit = any(h.match(l) for l in lines for h in HEAD_EXPLICIT)
    heads: list[tuple[int, str]] = []
    seen: set[str] = set()
    for i, line in enumerate(lines):
        eid = None
        for h in HEAD_EXPLICIT:
            m = h.match(line)
            if m:
                eid = m.group(1)
                break
        if eid is None and not explicit:
            m = HEAD_LIST.match(line)
            if m:
                prev = lines[i - 1].strip() if i else ""
                if (i == 0 or prev == "" or prev.startswith("#")) and m.group(1) not in seen:
                    eid = m.group(1)
        if eid is not None:
            heads.append((i, eid))
            seen.add(eid)
    entries = []
    for k, (i, eid) in enumerate(heads):
        end = heads[k + 1][0] if k + 1 < len(heads) else len(lines)
        for j in range(i + 1, end):
            if SECTION.match(lines[j]):
                end = j
                break
        entries.append((eid, "\n".join(lines[i:end])))
    return entries


def in_repo_file(path_str: str, root: pathlib.Path) -> tuple[bool, str]:
    s = path_str.strip().strip("`*'\"")
    if not s or s.startswith(("/", "~")):
        return False, "must be a repo-root-relative path, not absolute"
    p = (root / s)
    try:
        rp = p.resolve()
        rp.relative_to(root.resolve())
    except (ValueError, OSError):
        return False, "escapes this repository"
    if not rp.is_file():
        return False, "does not resolve to a file from the repo root"
    return True, s


def classify(body: str, root: pathlib.Path) -> tuple[str, str]:
    m = FIELD.search(body)
    if m:
        value = m.group(1).strip().strip("`*").strip()
        if not value:
            return "missing", "`闸:` is empty — write a path or `无 — <reason>`"
        nm = NONE_VALUE.match(value)
        if nm:
            reason = nm.group(1).strip()
            if len(reason) >= 6:
                return "excuse", reason[:60]
            return "missing", "`闸: 无` needs a reason (≥ 6 chars): why can a machine not decide this?"
        # the path token ends at whitespace or an opening parenthesis: people write
        # `闸: docs/gate_x.py（只管产物那半）` with no space before the bracket
        token = re.split(r"[\s（(]", value, maxsplit=1)[0].strip("`*'\",;。，")
        ok, detail = in_repo_file(token, root)
        return ("gate", detail) if ok else ("unresolvable", f"{token} {detail}")
    if LEGACY_GATE.search(body):
        paths = BACKTICK_PATH.findall(body)
        ordered = [x for x in paths if GATE_LIKE.search(x)] + [x for x in paths if not GATE_LIKE.search(x)]
        for pth in ordered:
            ok, detail = in_repo_file(pth, root)
            if ok:
                return "gate", detail
        return "unresolvable", "says 已升级成闸 but no backticked path in the entry is a file in this repo"
    if LEGACY_EXCUSE.search(body):
        return "excuse", "legacy marker (做不成闸 / not gateable)"
    return "missing", "no `闸:` line, no 已升级成闸 + path, no 做不成闸"


# ── state ───────────────────────────────────────────────────────────────────

def state_path(state_dir: pathlib.Path, f: pathlib.Path) -> pathlib.Path:
    return state_dir / (hashlib.sha1(str(f).encode()).hexdigest()[:16] + ".json")


def load_state(sp: pathlib.Path) -> dict | None:
    """None = no state yet. Corrupt state raises — never a silent re-baseline."""
    if not sp.exists():
        return None
    try:
        st = json.loads(sp.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        raise RuntimeError(f"state file unreadable: {sp} ({exc}). Delete it to re-baseline deliberately.") from exc
    if not isinstance(st, dict) or "baseline" not in st:
        raise RuntimeError(f"state file malformed: {sp}. Delete it to re-baseline deliberately.")
    return st


def save_state(sp: pathlib.Path, st: dict) -> None:
    sp.parent.mkdir(parents=True, exist_ok=True)
    # ⚠️ The temp name must be UNIQUE per writer. It used to be `sp.with_suffix(".tmp")`
    # — the same path for every concurrent invocation — so two parallel hooks writing
    # the same GOTCHAS state could have one os.replace() publish the OTHER's
    # half-written file. That is corruption, not merely a lost update.
    tmp = sp.with_suffix(f".tmp.{os.getpid()}")
    try:
        tmp.write_text(json.dumps(st, ensure_ascii=False), encoding="utf-8")
        os.replace(tmp, sp)
    finally:
        try:
            tmp.unlink()
        except OSError:
            pass


@contextlib.contextmanager
def state_lock(sp: pathlib.Path):
    """Serialise the whole read-modify-write, not just the write.

    PostToolUse fires once per tool call and parallel calls run concurrently, so two
    invocations could both load the state, both append their own accepted entry, and
    the second write would drop the first. `os.replace` being atomic does not make the
    TRANSACTION atomic — the entry that lost the race then goes red later for no
    reason the author can see.

    flock is advisory and POSIX; every writer here takes it, which is all that is
    required. If the lock cannot be taken at all we proceed unlocked rather than
    failing a gate over a diagnostic concern.
    """
    lock = sp.with_suffix(".lock")
    lock.parent.mkdir(parents=True, exist_ok=True)
    handle = None
    try:
        handle = open(lock, "a+")
        if fcntl is not None:
            fcntl.flock(handle.fileno(), fcntl.LOCK_EX)
        else:
            handle.seek(0)
            msvcrt.locking(handle.fileno(), msvcrt.LK_LOCK, 1)
    except OSError:
        if handle is not None:
            handle.close()
        handle = None
    try:
        yield
    finally:
        if handle is not None:
            try:
                if fcntl is not None:
                    fcntl.flock(handle.fileno(), fcntl.LOCK_UN)
                else:
                    handle.seek(0)
                    msvcrt.locking(handle.fileno(), msvcrt.LK_UNLCK, 1)
            finally:
                handle.close()


def head_ids(f: pathlib.Path, root: pathlib.Path) -> list[str] | None:
    """Entry ids in HEAD's copy of f; None if f is not tracked (or no git)."""
    try:
        rel = f.resolve().relative_to(root.resolve()).as_posix()
    except ValueError:
        return None
    try:
        tracked = subprocess.run(["git", "-C", str(root), "ls-files", "--error-unmatch", rel],
                                 capture_output=True, timeout=5).returncode == 0
        if not tracked:
            return None
        # bytes + explicit decode: `text=True` would use this process's locale, and a
        # CJK GOTCHAS body would come back mojibake ⇒ zero entry ids parse ⇒ an empty
        # baseline, which reads as "every entry is new".
        cp = subprocess.run(["git", "-C", str(root), "show", f"HEAD:{rel}"],
                            capture_output=True, timeout=5)
    except (OSError, subprocess.TimeoutExpired):
        return None
    if cp.returncode != 0:
        return []          # tracked but not in HEAD yet (staged new file) → nothing is baseline
    return [eid for eid, _ in parse_entries(cp.stdout.decode("utf-8", "replace"))]


# ── hook ────────────────────────────────────────────────────────────────────

def check_file(f: pathlib.Path, root: pathlib.Path, state_dir: pathlib.Path) -> list[str]:
    sp = state_path(state_dir, f)
    with state_lock(sp):
        return _check_file_locked(f, root, sp)


def _check_file_locked(f: pathlib.Path, root: pathlib.Path, sp: pathlib.Path) -> list[str]:
    mtime = f.stat().st_mtime
    st = load_state(sp)
    if st and st.get("mtime") == mtime:
        _trace(f"unchanged: {f}")
        return []
    entries = parse_entries(f.read_text(encoding="utf-8", errors="replace"))
    if st is None:
        base = head_ids(f, root)
        if base is None:
            st = {"baseline": [], "ok": [], "source": "untracked-unseeded"}
            _trace(f"first run, {f} not tracked: baseline empty (run --seed to accept existing entries)")
        else:
            st = {"baseline": sorted(set(base)), "ok": [], "source": "git-HEAD"}
            _trace(f"first run: baseline = {len(base)} ids from HEAD:{f.name}")
    accepted = set(st["baseline"]) | set(st.get("ok", []))
    problems = []
    for eid, body in entries:
        if eid in accepted:
            continue
        verdict, detail = classify(body, root)
        if verdict in ("gate", "excuse"):
            st.setdefault("ok", []).append(eid)
            _trace(f"{eid}: {verdict} ({detail})")
        else:
            problems.append(f"  ✗ entry {eid}: {verdict} — {detail}")
    st["ok"] = sorted(set(st.get("ok", [])))
    st["mtime"] = mtime
    save_state(sp, st)
    if not problems:
        _trace(f"{f}: {len(entries)} entries, every new one declared its gate")
    elif st.get("source") == "untracked-unseeded":
        problems.append(f"  (this file is not tracked by git: existing entries are not exempt. "
                        f"To accept them once: gotchas-contract.py --seed {f})")
    return problems


def hook(raw: str, state_dir: pathlib.Path) -> int:
    try:
        payload = json.loads(raw) if raw.strip() else {}
        if not isinstance(payload, dict):
            raise ValueError("not an object")
    except (ValueError, json.JSONDecodeError) as exc:
        print(f"gotchas-contract: unreadable hook input ({exc.__class__.__name__}); nothing checked", file=sys.stderr)
        return 1
    # Skip only when NOTHING in this batch could have written. A batch of pure reads
    # is the common case and must stay free; one Write in a batch of ten reads must not
    # be skipped because the other nine were reads.
    names = [c.get("tool_name") for c in tool_calls(payload)]
    if names and not any(n in WRITING_TOOLS for n in names if n):
        return 0
    files = gotchas_files(payload)
    if not files:
        _trace("no GOTCHAS.md in reach")
        return 0
    problems: list[str] = []
    for f, root in files:
        ps = check_file(f, root, state_dir)
        if ps:
            try:
                label = f.relative_to(root).as_posix()
            except ValueError:
                label = str(f)
            problems.append(f"{label}:")
            problems += ps
    if not problems:
        return 0
    print("⛔ GOTCHAS entry without a gate declaration — decide it NOW, in the entry:", file=sys.stderr)
    print("\n".join(problems), file=sys.stderr)
    print("Add one line to each entry:  闸: <path from repo root, a file in this repo>   or   "
          "闸: 无 — <why a machine cannot decide this>", file=sys.stderr)
    print("(partial coverage → 闸: <path> and say which half is not covered; full coverage → retire the entry "
          "to a tombstone. rules get forgotten, gates do not — skills/checkpoint/SKILL.md discipline 3)",
          file=sys.stderr)
    return 2


def audit(f: pathlib.Path) -> int:
    root = repo_root_of(f) or f.parent
    entries = parse_entries(f.read_text(encoding="utf-8", errors="replace"))
    base = head_ids(f, root)
    print(f"{f} — {len(entries)} entries parsed (root={root.name}; "
          f"{'tracked, ' + str(len(base)) + ' in HEAD' if base is not None else 'NOT tracked → needs --seed'})")
    counts: dict[str, int] = {}
    for eid, body in entries:
        v, d = classify(body, root)
        counts[v] = counts.get(v, 0) + 1
        print(f"  {eid:>6}  {v:<12} {d[:70]}")
    print("summary:", ", ".join(f"{k}={v}" for k, v in sorted(counts.items())))
    if not entries:
        print("⚠️ 0 entries parsed — head format not recognised; silence here is NOT coverage.")
    return 0


def seed(f: pathlib.Path, state_dir: pathlib.Path) -> int:
    root = repo_root_of(f) or f.parent
    ids = [eid for eid, _ in parse_entries(f.read_text(encoding="utf-8", errors="replace"))]
    sp = state_path(state_dir, f.resolve())
    save_state(sp, {"baseline": sorted(set(ids)), "ok": [], "source": "seed", "mtime": f.stat().st_mtime})
    print(f"seeded {len(ids)} entries as baseline for {f} → {sp}")
    return 0


# ── self-test ───────────────────────────────────────────────────────────────

def self_test() -> int:
    import time

    me = pathlib.Path(__file__).resolve()
    bad = 0
    # platform facts, for when a failure reproduces on one OS only
    print(f"  env: python {sys.version.split()[0]}  {sys.platform}  "
          f"git {subprocess.run(['git', '--version'], capture_output=True, text=True).stdout.strip()}  "
          f"stdout={getattr(sys.stdout, 'encoding', '?')}  fs={sys.getfilesystemencoding()}")

    def case(name: str, ok: bool, detail: str = "") -> None:
        nonlocal bad
        # On failure print the WHOLE detail, not a tail. A 320-char tail of this
        # hook's stderr is always the same advice block, which is exactly the part
        # that says nothing about why — three CI runs were diagnosed from it and
        # every hypothesis it suggested was wrong.
        print(f"  {'ok  ' if ok else 'FAIL'}  {name}")
        if not ok and detail:
            print("".join(f"        │ {ln}\n" for ln in detail.splitlines()), end="")
        bad += 0 if ok else 1

    def git(repo, *a, check=True):
        # env=env carries the fixture's committer identity, and -c pins it even when
        # the machine has no global git config at all (a CI runner does not).
        # It used to run without env: on this laptop git guessed an identity from the
        # system and the fixture committed; where it cannot guess, `commit` failed,
        # nothing was ignored, and `git show HEAD:…` then produced an EMPTY baseline —
        # which the gate reads as "every entry is new". Every declaration-accepted
        # case went red, on Linux only.
        cp = subprocess.run(["git", "-C", str(repo),
                             "-c", "user.name=t", "-c", "user.email=t@t",
                             "-c", "commit.gpgsign=false", "-c", "init.defaultBranch=main",
                             *a], capture_output=True, encoding="utf-8", errors="replace", env=env)
        # ⛔ FAIL-FAST BY DEFAULT. A setup command that fails silently means every case
        # below is measured against a world that was never built — the CI failure this
        # replaces looked like eight logic bugs and was one unchecked `git commit`.
        # Pass check=False only where the caller INSPECTS the return code.
        if check and cp.returncode != 0:
            raise RuntimeError(f"self-test fixture: `git {' '.join(a)}` failed "
                               f"(rc={cp.returncode}) in {repo}\n{cp.stderr.strip()}")
        return cp

    with tempfile.TemporaryDirectory() as td:
        state = pathlib.Path(td) / "state"
        env = {**os.environ, "GOTCHAS_CONTRACT_TRACE": "1", "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t",
               "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t", "PYTHONUTF8": "1",
               "HOME": os.environ.get("HOME", td)}

        def run(payload: dict):
            cp = subprocess.run([sys.executable, str(me), "--state-dir", str(state)],
                                input=json.dumps(payload), capture_output=True,
                                encoding="utf-8", errors="replace", env=env)
            return cp.returncode, cp.stderr

        # ── tracked repo: baseline from HEAD ──
        repo = pathlib.Path(td) / "tracked"; repo.mkdir()
        git(repo, "init", "-q"); (repo / "docs").mkdir(); (repo / "docs" / "gate_x.py").write_text("# gate\n", encoding="utf-8")
        g = repo / "docs" / "GOTCHAS.md"
        g.write_text("# GOTCHAS\n\n**1 · old one**\nno gate, no reason.\n\n**2 · older**\nalso nothing.\n", encoding="utf-8")
        git(repo, "add", ".")
        cp = git(repo, "commit", "-qm", "base", check=False)
        # ⛔ Do not let a broken fixture look like a broken assertion. Everything below
        # is measured against HEAD, so if this commit did not happen the whole suite
        # reports the wrong thing (this is the kit's "prove the check ran" rule).
        show = git(repo, "show", "HEAD:docs/GOTCHAS.md", check=False)
        case("fixture: the baseline commit exists and HEAD:docs/GOTCHAS.md is readable",
             cp.returncode == 0 and show.returncode == 0 and "**1 · old one**" in show.stdout,
             f"commit rc={cp.returncode} {cp.stderr.strip()} | show rc={show.returncode} {show.stderr.strip()}")
        inside = {"cwd": str(repo), "tool_name": "Bash", "tool_input": {}}
        parent = pathlib.Path(td)

        # the v1 hole: parent-dir Bash heredoc appends a bad entry BEFORE any state exists
        time.sleep(0.01)
        g.write_text(g.read_text(encoding="utf-8") + "\n**3 · appended via heredoc**\n机制：会咬人。\n", encoding="utf-8")
        rc, err = run({"cwd": str(parent), "tool_name": "Bash",
                       "tool_input": {"command": f"cat >> {repo}/docs/GOTCHAS.md <<'EOF'\n**3 · x**\nEOF"}})
        case("⭐ parent-cwd Bash heredoc on first run ⇒ RED (baseline from HEAD, not from the worktree)",
             rc == 2 and "entry 3" in err and "baseline = 2" in err, err)

        rc, err = run(inside)
        case("unchanged ⇒ silent", rc == 0 and "unchanged" in err, err)

        time.sleep(0.01)
        g.write_text(g.read_text(encoding="utf-8").replace("机制：会咬人。\n", "机制：会咬人。\n闸: 无 — 分类是判断，机器判不了\n"), encoding="utf-8")
        rc, err = run(inside)
        case("`闸: 无 — reason` ⇒ green", rc == 0 and "3: excuse" in err, err)

        # commit 3 without a declaration would NOT extend the baseline
        git(repo, "add", "."); git(repo, "commit", "-qm", "add 3")
        time.sleep(0.01)
        g.write_text(g.read_text(encoding="utf-8") + "\n**4 · committed-later**\nnothing\n", encoding="utf-8")
        git(repo, "add", "."); git(repo, "commit", "-qm", "add 4 undeclared")
        time.sleep(0.01)
        g.write_text(g.read_text(encoding="utf-8") + "\n**5 · another**\n闸: docs/gate_x.py（只管产物那半）\n", encoding="utf-8")
        rc, err = run(inside)
        case("an entry committed without declaring stays RED (baseline is frozen at first run)",
             rc == 2 and "entry 4" in err and "entry 5" not in err, err)
        time.sleep(0.01)
        g.write_text(g.read_text(encoding="utf-8").replace("**4 · committed-later**\nnothing\n", "**4 · committed-later**\n闸: 无 — 判断类，写清理由\n"), encoding="utf-8")
        run(inside)

        for name, value, want in [
            ("`闸: .` ⇒ RED (directory)", "闸: .", 2),
            ("absolute path outside repo ⇒ RED", "闸: /etc/hosts", 2),
            ("`../` escape ⇒ RED", "闸: ../outside/gate_x.py", 2),
            ("bold path `**docs/gate_x.py**` ⇒ green", "闸: **docs/gate_x.py**", 0),
            ("`闸: 无法做成闸，理由够长了吧` ⇒ green", "闸: 无法做成闸，理由够长了吧", 0),
            ("`闸: 没有 — 原因原因原因` ⇒ green", "闸: 没有 — 原因原因原因", 0),
            ("`闸: N/A — reason long enough` ⇒ green", "闸: N/A — reason long enough", 0),
            ("`闸: ` empty ⇒ RED, no crash", "闸: ", 2),
            ("`闸: 无` no reason ⇒ RED", "闸: 无", 2),
            ("legacy 已升级成闸 + in-repo backtick path ⇒ green", "⭐ 这条已升级成闸：`docs/gate_x.py`。", 0),
            ("legacy 做不成闸 ⇒ green", "⚠️ 这条做不成闸，理由要写下来。", 0),
        ]:
            time.sleep(0.01)
            body = g.read_text(encoding="utf-8")
            body = re.sub(r"\n\*\*9 · probe\*\*.*\Z", "", body, flags=re.S) + f"\n**9 · probe**\n{value}\n"
            g.write_text(body, encoding="utf-8")
            rc, err = run(inside)
            case(name, rc == want and ("entry 9" in err if want == 2 else "9:" in err or "every new" in err), err)
            if want == 0:   # reset ok so the next probe re-evaluates id 9
                sp = state_path(state, g.resolve()); st = json.loads(sp.read_text(encoding="utf-8")); st["ok"] = [x for x in st["ok"] if x != "9"]; sp.write_text(json.dumps(st), encoding="utf-8")
        time.sleep(0.01); g.write_text(re.sub(r"\n\*\*9 · probe\*\*.*\Z", "", g.read_text(encoding="utf-8"), flags=re.S), encoding="utf-8"); run(inside)

        # corrupt state ⇒ loud, never a silent re-baseline
        sp = state_path(state, g.resolve()); sp.write_text("{corrupt", encoding="utf-8")
        time.sleep(0.01); g.write_text(g.read_text(encoding="utf-8") + "\n", encoding="utf-8")
        rc, err = run(inside)
        case("corrupt state ⇒ exit 2 naming the file", rc == 2 and "state file unreadable" in err, err)
        sp.unlink()
        run(inside)

        # ── untracked file: fail-closed until seeded ──
        u = pathlib.Path(td) / "untracked"; (u / ".git").mkdir(parents=True)
        ug = u / "GOTCHAS.md"; ug.write_text("# G\n\n### 1. first\nbody\n\n### 2. second\n闸: 无 — reason long enough\n", encoding="utf-8")
        rc, err = run({"cwd": str(u), "tool_name": "Edit", "tool_input": {"file_path": str(ug)}})
        case("untracked, unseeded ⇒ existing undeclared entry is RED + seed hint", rc == 2 and "entry 1" in err and "--seed" in err, err)
        subprocess.run([sys.executable, str(me), "--state-dir", str(state), "--seed", str(ug)], capture_output=True)
        time.sleep(0.01); ug.write_text(ug.read_text(encoding="utf-8") + "\n### 3. third\nno decl\n", encoding="utf-8")
        rc, err = run({"cwd": str(u), "tool_name": "Bash", "tool_input": {"command": "echo x >> GOTCHAS.md"}})
        case("after --seed: old entries exempt, new `### 3.` entry RED (Bash with relative path)", rc == 2 and "entry 3" in err and "entry 1" not in err, err)

        # ── parsing ──
        ents = parse_entries("**G-01 · sample style**\nx\n\n**G-02 · next**\ny\n")
        case("`**G-01 ·` ids parsed", [e for e, _ in ents] == ["G-01", "G-02"], str(ents))
        fit = "# F\n\n## 改 schema 之前\n\n5. ⭐⭐ **bold title** —— body\n1. **`docs/a.md`** first step\n2. **`docs/b.py`** second\n闸: 无 — 写在条目末尾的理由\n\n9. **another** body\n"
        ents = parse_entries(fit)
        case("project E: bold sub-list after a non-blank line is NOT split; 闸 stays with entry 5",
             [e for e, _ in ents] == ["5", "9"] and "闸: 无" in ents[0][1], str([e for e, _ in ents]))
        mixed = "**23 · x**\nsteps:\n1. **`docs/a.md`** first\n\n**24 · y**\nbody\n"
        case("bold numbered list inside a `**N ·` file is NOT split", [e for e, _ in parse_entries(mixed)] == ["23", "24"])

        # ── reach & input ──
        rc, err = run({"cwd": "/", "tool_name": "Bash", "tool_input": {}})
        case("no GOTCHAS in reach ⇒ silent", rc == 0 and "no GOTCHAS" in err, err)
        rc, err = run({"cwd": str(repo), "tool_name": "Read", "tool_input": {}})
        case("Read tool ⇒ skipped", rc == 0 and err.strip() == "", err)
        cp = subprocess.run([sys.executable, str(me), "--state-dir", str(state)], input="{nope",
                            capture_output=True, encoding="utf-8", errors="replace", env=env)
        case("malformed JSON ⇒ exit 1, nothing checked", cp.returncode == 1 and "unreadable" in cp.stderr, cp.stderr)

    print("self-test: PASS" if not bad else f"self-test: {bad} FAILURE(S)")
    return 1 if bad else 0


def main(argv: list[str]) -> int:
    state_dir = DEFAULT_STATE
    if "--state-dir" in argv:
        state_dir = pathlib.Path(argv[argv.index("--state-dir") + 1]).expanduser()
    if "--self-test" in argv:
        return self_test()
    if "--audit" in argv:
        return audit(pathlib.Path(argv[argv.index("--audit") + 1]).expanduser().resolve())
    if "--seed" in argv:
        return seed(pathlib.Path(argv[argv.index("--seed") + 1]).expanduser().resolve(), state_dir)
    try:
        return hook(sys.stdin.buffer.read().decode("utf-8", "replace")
                    if not sys.stdin.isatty() else "", state_dir)
    except Exception:  # noqa: BLE001 — loud on purpose
        print("⛔ gotchas-contract hook crashed — it is NOT checking anything until fixed:", file=sys.stderr)
        traceback.print_exc()
        return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
