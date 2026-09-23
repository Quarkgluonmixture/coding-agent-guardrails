---
name: cross-ai
description: 'Get an independent second opinion from another AI (Codex / the current frontier GPT; optionally a third lineage, Gemini via agy) and reconcile it with your own thinking. Both sides reason independently FIRST (zero-preset — no seeded conclusions), then merge: state where they agree (high confidence), list what each found alone, and surface the GENUINE disagreements as explicit choices for the user to decide. Use for audits, security/code review, design or architecture proposals, or any high-stakes judgment call where an independent cross-check adds confidence. Triggers: "cross ai", "cross-AI", "second opinion", "ask codex", "have another model check/review this", "比较两个AI".'
---

# Cross-AI: two independent thinkers → merge → surface the real disagreements

The point is a genuine independent cross-check, NOT an echo chamber. You (Claude) **and** Codex
each reason about the task on your own; then you reconcile and hand the user the *real* forks to
decide.

## Non-negotiable principles

- **Zero preset.** Codex's brief contains only neutral context: the task/question, where the
  code/data lives, the constraints, and (if there is one) the user's actual complaint. **Never**
  seed your own findings, suspected bugs, or proposed solutions. A biased brief yields confirmation,
  not a second opinion. Tell Codex explicitly: "there is no predefined answer — find/propose what
  you find; it's fine to disagree."
- **Lean brief.** Persona (matched to the domain: backend / data-pipeline / ML / stats / frontend /
  security / infra) + scope + output format — and do NOT enumerate attack vectors or checklist
  items: a list creates a list-shaped blind spot that misses everything off the list. Ask for at
  least one finding a typical first-read reviewer would miss.
- **You think too.** "Cross-AI" means *you* produce your own independent analysis — do not just run
  Codex and relay it. Form your view **before** reading Codex's output so it stays genuinely
  independent.
- **The user decides the genuine disagreements.** After merging, isolate the real divergences,
  explain each trade-off, give a recommendation — but let the **user** pick. Do not silently resolve
  a true fork.

## Steps

1. **Scope.** Identify the task to cross-check (from the invocation args or the current conversation),
   the repo/dir, and the sandbox. Default Codex to `read-only` (audit / design / review). Use a
   writable sandbox only if the cross-check genuinely needs to run or modify code — and say so.
   (`danger-full-access` is a machine-specific fallback for hosts whose sandbox is broken — e.g.
   a shared GPU box with stripped bwrap caps — never the general default.)

2. **Your independent pass — do this first.** Write your own analysis or proposals, concretely and
   opinionatedly. Save to the archive as `claude-take.md`. (You may kick off step 3 in the background
   first, but commit your own view before reading Codex's.)

3. **Codex zero-preset pass.** Write a neutral brief to `prompt.md`, then run it in the background
   (it takes minutes):
   ```bash
   D="docs/cross-ai-audits/<YYYY-MM-DD>-<slug>"   # or this repo's conventional local notes folder
   mkdir -p "$D"
   eval "$(~/.claude/skills/cross-ai/codex_model.sh)"   # resolves current flagship + effort
   codex exec -C "$PWD" -m "$CODEX_MODEL" -c model_reasoning_effort="$CODEX_EFFORT" -s read-only \
     --skip-git-repo-check -o "$D/codex-report.md" < "$D/prompt.md" > "$D/codex-transcript.md" 2>&1
   ```
   - `-o` = clean final report (read this); the `>` redirect keeps the full transcript.
   - Use `-s workspace-write` or `-s danger-full-access` only when the task truly requires it.
   - Pass the date in via the command (scripts can't call `date` themselves if reused in a workflow).
   - **No hand-edited model pin.** `codex_model.sh` reads codex's own server-fetched
     `~/.codex/models_cache.json` and takes the current flagship (lowest `priority` among visible,
     API-capable models), so a 5.5 → 5.6 generation change needs no edit here. It prints its pick to
     stderr — **report that model name to the user with the findings**; auto-resolution must never
     change the reviewer silently. If `$CODEX_MODEL` is empty the resolver found nothing: drop `-m`
     and let codex use its default. See the script header for the full fallback chain.

4. **Post-flight verification — before trusting any lineage's report.**
   - **I/O sanity**: report is non-trivial in size, not truncated mid-sentence, no tool errors
     embedded in it.
   - **Runtime sanity**: a substantive audit that returned in under ~1 minute did not do the work
     (auth / quota / early-exit) → retry, max 2; never silently accept a shallow pass as the
     requested depth.
   - **Fact-check citations**: verify cited `file:line`, symbols, quoted text, and numbers actually
     exist (`sed -n` / `grep`). **Anything only ONE side found gets a 100% check** — agreement
     between independent lineages is a natural hallucination filter; a unique finding has none, and
     it is exactly the "nobody else saw it" finding most likely to drive a decision. A fabricated
     citation downgrades/drops that finding (per-finding trust), it does not retry the whole run.

5. **Merge.** Read `$D/codex-report.md`; compare against `claude-take.md`. Write `$D/SYNTHESIS.md` with:
   - **Agreed (both reached independently)** → high confidence; state briefly.
   - **Unique to each side** → the additive value. **Verify any novel factual claim** before trusting
     it (run the check; don't just believe it — this is where the cross-check earns its keep).
   - **Genuine disagreements** → the crux: both positions, the trade-off, and what the choice hinges on.
   - Any size/count/latency/cost number that survives into the synthesis must trace to a real
     measurement (`wc -c`, `grep -c`, timing, the actual config value) — not a mental model.

6. **Hand the forks to the user.** Present agreements + unique points briefly, then put the REAL
   disagreements to the user as explicit choices — use the **AskUserQuestion** tool for clean forks.
   Recommend, but let them decide. **In review/audit runs, present the merged findings list and get
   the user's fix-scope confirmation BEFORE any Edit/Write** — never start fixing from one side's
   report alone. Then proceed on their decision.

## Optional third lineage (Google — Gemini via `agy`)

When the stakes justify a third independent perspective, add the Antigravity CLI (`agy`) as a
Google-lineage reviewer, in parallel with step 3 (same `$D`, own prompt file):

```bash
timeout 40 agy --model "Gemini 3.1 Pro (Low)" -p "Reply exactly OK"   # smoke test first
~/.claude/skills/cross-ai/agy_clean.sh "$D/prompt-gemini.md" "$D/gemini-report.md"
```

- The bundled `agy_clean.sh` wrapper locks the model to a Gemini tier (agy's palette also lists
  Claude/GPT entries — those would break the independent-lineage premise), uses plain `-p` print
  mode (the yolo flag forces a slow agent tool-loop), and runs from a neutral cwd so the repo's
  `AGENTS.md`/`GEMINI.md`/`CLAUDE.md` never leak into the cold read. Consequence: the brief must be
  **self-contained** — inline the material under review into the prompt; don't ask agy to open files.
- Lineage profile: strong on framing / design / external validity; weak on code depth and it
  hallucinates numbers — weight it accordingly in the merge (its numeric claims always get the
  step-4 fact-check).
- Smoke-test output containing "Please sign in" = OAuth not done → the user must run bare `agy`
  once interactively; skip the lineage and say so.
- Same rules as Codex: zero-preset brief, post-flight verification, unique findings 100% fact-checked.

## Notes

- Model/effort come from `codex_model.sh` (current flagship, `xhigh` when supported, else `high`) —
  no pin to maintain. `CROSS_AI_CODEX_MODEL` / `CROSS_AI_CODEX_EFFORT` override it: use them to
  reproduce an old audit on the model it was actually run with, or to reach `max`/`ultra` on models
  that offer them. The methodology here is model-agnostic; only the announcement matters — the run
  must always say which model spoke.
- ⚠️ Codex/OpenAI **cyber gate**: the frontier GPT models abort mid-run on offensive-security / red-team ATTACK briefs ("flagged for cybersecurity risk"). For such topics, abstract the brief to a pure systems/design/serialization question with NO attack semantics, or fall back to own analysis + a decisive experiment.
- The archive folder is often gitignored (local working notes) — fine; don't commit unless asked.
- Scale the panel when the stakes justify it: run Codex on 2–3 different framings of the question,
  or add the third lineage above, then merge all of them the same way.
- If `codex` isn't installed/authed, say so and fall back to presenting only your own analysis,
  clearly labeled as a single opinion (not a cross-check).
