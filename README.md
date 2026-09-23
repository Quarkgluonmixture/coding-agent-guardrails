# coding-agent-guardrails

Rules, hooks, skills and a delegation role that make AI coding agents
(Claude Code and OpenAI Codex CLI) behave more reliably across projects.
I built and maintained this as my own day-to-day harness. Each rule and hook
here was added after a specific failure I actually hit.

Internally the tool is called **`claude-kit`**. The installer and hooks expect
the checkout at `~/claude-kit`. The rule and skill text is written mostly in
**Chinese**, the language I work in. Code, hook messages, tests and this README
are in English. [`README.zh.md`](README.zh.md) is the original, more detailed
design note.

## What problems it targets

| Failure mode | What catches it |
|---|---|
| **Silent degradation**: an `except` falls back to a worse path on every call, and logs still look fine | `rules/global/coding-practice.md` (fallback paths must log loudly; probe capability by *using* it), plus a case file in `references/silent-degradation-cases.md` |
| **Claiming "done / passing / empty" without evidence**: a 4-second CI run, `Executed 0 tests`, an allow-list that matched nothing | `rules/global/work-discipline.md`: before giving a verdict, show the check ran on the right object and reached its assertion; measure every number instead of estimating it |
| **Destructive git misuse**: `git add -A` sweeping in someone else's files, `--no-verify`, force-push, `reset --hard` | `hooks/git-guard.sh`, a PreToolUse hook with two tiers (below) |
| **Concurrent sessions on one working tree** | A rule that treats unexplained uncommitted changes as another session's work and leaves them alone, plus `references/concurrency-and-worktrees.md` |
| **Session handover rot**: status copied into several docs that then drift apart | `skills/checkpoint` (CHECKPOINT / TODO / LOG / GOTCHAS, one question per file), plus a UserPromptSubmit hook that reliably invokes it |
| **Rules that nobody loads**: declared in a manifest, never actually in the model's context | `kit state`, which reports rules *observed loading* (from host hook events), not what the config says should load |
| **Second copies of facts drifting**: README inventories, frozen counts in tests | The README inventory is generated and checked in CI (`kit docs-sync --check`); tests assert relationships instead of snapshots |

## Layout

```
rules/global/     always-on rules (the "kernel"), injected into every session and subagent
rules/optin/      off by default; enabled per project (`kit add`) or per machine (`kit config`)
references/       not resident; a rule has a one-line pointer + trigger, the model reads on demand
skills/           checkpoint, cross-ai, deep-dive, memory-audit, refine-propose, report-dashboard, skill-creator
agents/executor   a delegation role: exactly one authorized step, compact report, no self-authorization
hooks/            git-guard, instructions-loaded, wrap-up-trigger, gotchas-contract, Codex adapters
codex/            the assets that need a different shape on Codex (skill variant, agent TOML)
bin/kit, lib/     helper CLI and the single asset registry shared with install.sh
tests/            13 bash suites (run-all.sh) + one manual canary that spends real model sessions
```

## Key design decisions

- **Discipline lives in the rules layer, not in memory.** Claude Code custom
  subagents load `CLAUDE.md` and rules but not the main session's auto-memory.
  So anything every executor must obey goes into `rules/`. On Codex the same
  files are injected by `SessionStart` and `SubagentStart` hooks
  (`hooks/codex-rules.py`). There is one source text per rule and a thin
  loader per host.
- **Resident rules have a hard byte budget.** Every resident rule is paid for
  in every session and subagent, and too many rules dilute each other.
  `tests/test-rules-budget.sh` sets a 20,000-byte ceiling on `rules/global/`.
  It is currently at 18,230 bytes (`cat rules/global/*.md | wc -c`). To add a
  rule you first compress or demote another. Demoted material goes into
  `references/`, and the rule keeps a pointer that says when to read it.
- **The page-in assumption was tested, not assumed.** `tests/canary-page-in.sh`
  runs real headless sessions to check whether the model follows a pointer in
  a trigger situation, and ignores it otherwise. Claude followed it; Codex did
  not. So each pointer line is written as a complete instruction that still
  works if the reference is never read.
- **Hooks for what must never happen, rules for judgment.** git-guard is
  deliberately two-tiered, because a guard that blocks normal work ends up
  switched off:
  - **DENY**: `add -A/-u/.`, `commit -a`, `--no-verify`, `clean -f`, `push --force`.
    `--force-with-lease` is allowed.
  - **ASK**: `reset --hard`, `checkout .`, bare `git stash`, `stash clear`.

  It parses shell text with regexes. That makes it a guardrail against slips
  under pressure, not a security boundary, and its header says so.
- **Declared ≠ effective.** `kit status` shows what is configured. `kit state`
  shows what the host actually loaded, from InstructionsLoaded / SessionStart
  records with SHA-256 per rule. It flags rules that were declared but never
  observed, and rules edited after the session loaded them.
- **Fail loudly on internal errors.** Hooks exit non-zero on unreadable input
  or state. For example, `gotchas-contract` refuses to silently re-create a
  baseline from a corrupt state file.

## Install

```bash
git clone <this-repo-url> ~/claude-kit
~/claude-kit/install.sh                  # Claude Code + Codex; or --target claude|codex
kit config                               # which assets are on for this machine
kit doctor                               # health check for both hosts
```

The installer is idempotent. It symlinks rules, skills and agents into
`~/.claude/` and `~/.agents/` / `~/.codex/`, and it merges hook registrations
into existing `settings.json` / `hooks.json` without dropping other entries.
Codex requires you to trust new hooks via `/hooks` afterwards.

Platforms: macOS and Linux (CI runs both). On Windows use WSL. In Git Bash,
symlinks degrade to copies unless `MSYS=winsymlinks:nativestrict` and
Developer Mode are enabled.

## Running the tests

```bash
bash tests/run-all.sh          # 13 suites; prints ALL SUITES PASS or SUITE FAILURES
python3 hooks/gotchas-contract.py --self-test
python3 hooks/wrap-up-trigger.py --self-test
```

The suites use a throwaway `HOME` and a copy of the checkout.
`tests/lib-testkit.sh` refuses to operate on a path that resolves to the real
checkout. An earlier version of the tests deleted their own `.git` through a
symlink alias and still printed "ALL SUITES PASS". The tests cover:

- git-guard decisions for each tier
- installer idempotency and settings merging
- a fresh-machine simulation: clone to a new path, install, then move the
  whole checkout and reinstall
- Codex hook injection, including fault injection before and after injection
- the generated-inventory gate
- the rules byte budget

Dependencies: bash, python3, git. `cross-ai` also needs the `codex` or `claude`
CLI (and optionally `agy`); without them the skill labels its output as a
single-model analysis.

## Acknowledgements

The executor role and the list of destructive git operations draw on ideas from
[PrimeIntellect-ai/prime-agent](https://github.com/PrimeIntellect-ai/prime-agent)
(MIT). No code was copied.

## License

MIT, see [LICENSE](LICENSE).
