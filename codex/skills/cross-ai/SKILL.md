---
name: cross-ai
description: Get an independent second opinion from Claude (optionally a third Gemini lineage) while Codex forms its own view first, then reconcile agreements, unique findings, and genuine disagreements. Use for audits, security or code review, architecture and design proposals, high-stakes judgment calls, or requests such as "cross AI", "second opinion", "ask Claude", and "比较两个AI".
---

# Cross-AI: Codex + an independent model lineage

Produce two genuinely independent analyses before merging them. Do not turn a second model into
an echo of Codex's first impression.

## Non-negotiable principles

- **Zero preset.** Give Claude neutral context: task, scope, relevant paths, constraints, and the
  user's actual complaint. Do not seed suspected bugs, preferred solutions, or Codex findings.
- **Independent first pass.** Write Codex's own concrete view before reading Claude's result.
- **Verify unique findings.** Check every factual claim found by only one side against the real
  artifact before it reaches the synthesis.
- **Expose real forks.** Recommend a choice, but leave genuine value or architecture trade-offs to
  the user.

## Workflow

1. Create a scratch directory outside the repository. "Read-only review" means no writes to the
   reviewed project; scratch analysis files do not change its source. Use a repository archive only
   when the user explicitly requests or authorizes a durable audit artifact:

   ```bash
   KIT_REVIEW_DIR="$(mktemp -d "${TMPDIR:-/tmp}/claude-kit-cross-ai.XXXXXX")"
   D="$KIT_REVIEW_DIR"
   ```
2. Write Codex's independent analysis to `codex-take.md`. It must exist before Claude's report is
   read.
3. Write a lean, zero-preset brief to `prompt-claude.md`, then run Claude from the repository:

   ```bash
   claude -p --model opus --effort xhigh --permission-mode dontAsk \
     --tools "Read,Glob,Grep" --add-dir "$PWD" \
     < "$D/prompt-claude.md" > "$D/claude-report.md" 2> "$D/claude-stderr.log"
   ```

   Use the `opus` alias rather than a dated model id so Claude Code resolves its current frontier
   reviewer. If `xhigh` is unavailable, retry once with `high`. Do not grant Bash or write tools for
   a read-only review.
4. Check that the report is non-trivial, complete, and free of auth/tool errors. Verify cited paths,
   symbols, quotations, and numbers. A fabricated citation drops or downgrades that finding; it does
   not invalidate unrelated findings.
5. Write `SYNTHESIS.md` with:

   - agreed findings reached independently;
   - unique findings from each side, after factual verification;
   - genuine disagreements, their trade-offs, and Codex's recommendation;
   - the reviewer identity and model alias used.

6. Present the merged findings before implementing review fixes. If a genuine fork remains, ask the
   user to choose before proceeding.

## Optional third lineage

For unusually high-stakes decisions, run the existing Gemini wrapper with a separate neutral,
self-contained prompt:

```bash
~/claude-kit/skills/cross-ai/agy_clean.sh "$D/prompt-gemini.md" "$D/gemini-report.md"
```

Fact-check Gemini's numeric claims and unique findings exactly as above. If `claude` is unavailable
or unauthenticated, say so and use Gemini if available; otherwise label the result as a single-model
analysis rather than claiming a cross-check.
