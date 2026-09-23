#!/usr/bin/env python3
"""Inject enabled claude-kit rules into Codex sessions and record what was injected.

⭐ TWO PHASES WITH DIFFERENT FAILURE CONTRACTS — the whole point of this file:

  injection   the control plane. If it fails, the session must NOT look normal.
              Loud on stderr, nonzero exit, and a marker on stdout so the MODEL
              also knows its resident discipline is absent.
  observation the kit-state log. Best-effort: a read-only HOME must never be able
              to cost a session its rules.

It used to be one phase under a blanket `except Exception: exit 0` justified as
"observability must never prevent a session from starting". That swallowed the
injection half too — and because the per-rule sha256 was computed BEFORE anything
was printed, one unreadable rule file produced ZERO injected rules, exit 0, and a
Codex session that started perfectly. Precisely the silent degradation the kit's
own coding-practice rule is about.
"""

from __future__ import annotations

import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import traceback


def read_payload() -> dict:
    # Bytes + explicit decode: the payload carries paths, and the locale must not
    # decide whether they survive. A malformed payload is not fatal (cwd falls back
    # to os.getcwd()), but it must not be confused with an unreadable RULE.
    try:
        raw = sys.stdin.buffer.read().decode("utf-8", "replace")
        value = json.loads(raw) if raw.strip() else {}
        return value if isinstance(value, dict) else {}
    except (ValueError, OSError):
        return {}


def project_root(cwd: Path) -> Path:
    try:
        result = subprocess.run(
            ["git", "-C", str(cwd), "rev-parse", "--show-toplevel"],
            capture_output=True,
            check=True,
            text=True,
            timeout=3,
        )
        return Path(result.stdout.strip()).resolve()
    except (OSError, subprocess.SubprocessError):
        # Not a git repo (or no git) is legitimate — the project opt-in manifest is
        # then looked up from cwd. Narrow on purpose: a real bug in here must raise.
        return cwd.resolve()


class SelectionError(Exception):
    """A file that DECIDES which rules are selected exists but could not be read.

    ⭐ The distinction that matters: **absent is legitimate** (no kit.conf means all
    defaults; no manifest means no project opt-in), **present-but-unreadable is not**.
    Both used to collapse into `except OSError: pass`, and both directions were
    silent — measured 2026-09-05:
      · manifest unreadable  ⇒ exit 0, 0 bytes stderr, the opt-in rule just gone;
      · kit.conf unreadable  ⇒ exit 0, and a rule configured OFF was injected anyway.
    A selection input we cannot read means we do not know what the answer is, and
    "we do not know" must never be rendered as a confident default.
    """


def _read_selection_file(path: Path) -> str | None:
    """None = absent (fine). Raises SelectionError = present but unreadable (not fine)."""
    try:
        return path.read_bytes().decode("utf-8")
    except FileNotFoundError:
        return None
    except (OSError, UnicodeDecodeError) as exc:
        raise SelectionError(f"{path}: {exc.__class__.__name__}: {exc}") from exc


def overrides(path: Path) -> dict[tuple[str, str], str]:
    result: dict[tuple[str, str], str] = {}
    raw_text = _read_selection_file(path)
    if raw_text is None:
        return result
    for raw in raw_text.splitlines():
        fields = raw.split()
        if len(fields) != 2 or fields[0] not in {"on", "off"} or ":" not in fields[1]:
            continue
        kind, name = fields[1].split(":", 1)
        result[(kind, name)] = fields[0]
    return result


def manifest(path: Path) -> list[str]:
    raw_text = _read_selection_file(path)
    if raw_text is None:
        return []
    return [
        line.strip()
        for line in raw_text.splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    ]


def sha256(text: str) -> str:
    # Hashes the text that was ACTUALLY injected, not a second read of the file.
    # Two reads can disagree (the file may change between them), and this value's
    # only job is to let `kit state codex` say "the rule changed since injection".
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def kit_commit(root: Path) -> str | None:
    try:
        result = subprocess.run(
            ["git", "-C", str(root), "rev-parse", "--short", "HEAD"],
            capture_output=True,
            check=True,
            text=True,
            timeout=3,
        )
        return result.stdout.strip() or None
    except (OSError, subprocess.SubprocessError):
        return None


def trim_log(path: Path, keep: int = 1000, limit: int = 2000) -> None:
    # Explicit encoding + replace: a log line with a stray byte is an OBSERVATION
    # problem. It used to raise UnicodeDecodeError past `except OSError`, escape to
    # the outermost handler, and make a session whose rules had ALREADY been printed
    # report "RULE INJECTION FAILED" — with the six injected rules sitting right above
    # the banner on stdout. Measured 2026-09-05.
    try:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
        if len(lines) > limit:
            path.write_text("\n".join(lines[-keep:]) + "\n", encoding="utf-8")
    except OSError:
        pass


# Set the moment the rules have actually been written to stdout. After that point
# NOTHING may claim the injection failed — the model can see the rules.
INJECTED = False


def fail(detail: str) -> None:
    """Injection failed. Say so on BOTH channels: stderr for the human and the
    hook log, stdout because that is the model's context — a Codex session must
    not proceed believing the resident rules are present when they are not."""
    banner = ("\u26d4 claude-kit RULE INJECTION FAILED — the kit's resident rules are "
              "NOT in this context. Treat none of them as active until this is fixed.")
    print(banner)
    print(f"# reason: {detail}")
    print(f"codex-rules: {banner}\n  {detail}", file=sys.stderr)


def main() -> int:
    global INJECTED
    payload = read_payload()
    cwd = Path(payload.get("cwd") or os.getcwd())
    kit_root = Path(__file__).resolve().parent.parent
    project = project_root(cwd)
    if os.environ.get("CODEX_RULES_FAULT") == "pre-injection":
        raise RuntimeError("injected fault: pre-injection")
    try:
        conf = overrides(kit_root / "kit.conf")
        opted = set(manifest(project / ".claude" / "kit-rules"))
    except SelectionError as exc:
        fail(f"a file that decides which rules apply is unreadable — {exc}")
        return 3
    selected: list[tuple[Path, str]] = []
    seen: set[str] = set()

    for path in sorted((kit_root / "rules" / "global").glob("*.md")):
        name = path.stem
        if conf.get(("rule", name), "on") == "on":
            selected.append((path, "global"))
            seen.add(name)

    for path in sorted((kit_root / "rules" / "optin").glob("*.md")):
        name = path.stem
        globally_on = conf.get(("rule", name), "off") == "on"
        if name not in seen and (globally_on or name in opted):
            selected.append((path, "optin"))
            seen.add(name)

    # ── injection ────────────────────────────────────────────────────────────
    # Read EVERY selected rule before printing anything: all-or-loud, never a
    # half-injected context that reads as a complete one.
    bodies: list[tuple[Path, str, str]] = []
    for path, tier in selected:
        try:
            bodies.append((path, tier, path.read_text(encoding="utf-8")))
        except OSError as exc:
            fail(f"cannot read the selected rule {path}: {exc.__class__.__name__}: {exc}")
            return 3

    if bodies:
        print("# claude-kit rules injected for Codex")
        print("These files are the canonical rule source; later project instructions remain more specific.")
        for path, tier, body in bodies:
            print(f"\n<!-- kit/{tier}: {path.name} -->")
            print(body.rstrip())
    sys.stdout.flush()
    INJECTED = True          # ⭐ the control plane has done its job; nothing below may deny it

    # Test seam. The INJECTED guard protects code added BETWEEN this point and the
    # observation block — today there is none, so the guard has no natural trigger and
    # would be an untested claim. This gives it one, and nothing else: it only raises,
    # only for these two exact values, and the same var exercises the pre-injection
    # path in main()'s caller. (What it catches: a future edit puts fallible code here
    # and the hook goes back to reporting a successful injection as a failed one.)
    if os.environ.get("CODEX_RULES_FAULT") == "post-injection":
        raise RuntimeError("injected fault: post-injection")

    # ── observation (best-effort from here down) ──────────────────────────────
    # ⛔ This except is DELIBERATELY broad, and that is the one place in this file
    # where it is correct: past the line above, an observability bug must not be able
    # to change the exit code, the stdout the model already has, or the story told
    # about it. Anything raising here is reported as what it is — a logging failure.
    rules = [
        {"name": path.stem, "tier": tier, "path": str(path), "sha256": sha256(body)}
        for path, tier, body in bodies
    ]
    try:
        log_dir = Path.home() / ".codex" / "kit-state"
        log_dir.mkdir(parents=True, exist_ok=True)
        log_path = log_dir / "instructions.jsonl"
        record = {
            "ts": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"),
            "session_id": payload.get("session_id"),
            "turn_id": payload.get("turn_id"),
            "agent_id": payload.get("agent_id"),
            "event": payload.get("hook_event_name"),
            "cwd": str(cwd.resolve()),
            "project": str(project),
            "kit_commit": kit_commit(kit_root),
            "rules": rules,
        }
        with log_path.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(record, ensure_ascii=False) + "\n")
        trim_log(log_path)
    except Exception as exc:  # noqa: BLE001 — see the contract note above
        print(f"codex-rules: rules WERE injected; only the kit-state log failed "
              f"({exc.__class__.__name__}: {exc})", file=sys.stderr)
    return 0


if __name__ == "__main__":
    for _s in (sys.stdout, sys.stderr):
        try:
            _s.reconfigure(encoding="utf-8", errors="replace")   # type: ignore[union-attr]
        except (AttributeError, OSError):
            pass
    try:
        raise SystemExit(main())
    except Exception as exc:          # noqa: BLE001 — loud on purpose
        # ⛔ This used to `raise SystemExit(0)` in the name of "observability must
        # never block a session". Observation is already contained above. Anything
        # reaching HERE before INJECTED is the injection path, and a silent exit 0 is
        # the one outcome we must never produce.
        traceback.print_exc(file=sys.stderr)
        if INJECTED:
            # ⛔ Do NOT print the injection banner: the rules are on stdout and the
            # model can read them. Claiming otherwise would put a "treat none of these
            # as active" line directly underneath six correctly injected rules.
            print(f"codex-rules: rules WERE injected; a post-injection step failed "
                  f"({exc.__class__.__name__}: {exc})", file=sys.stderr)
            raise SystemExit(0)
        fail(f"unhandled {exc.__class__.__name__}: {exc}")
        raise SystemExit(3)
