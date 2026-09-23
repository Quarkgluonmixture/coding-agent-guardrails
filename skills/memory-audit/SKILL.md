---
name: memory-audit
description: 'Periodic reality-check of the auto-loaded memory. Walk the memory index line by line, probe every load-bearing claim against the real world (paths, symbols, flags, model ids, "X is pending/unbuilt" statements), then update/supersede/delete per the memory write rules. A rotten memory is worse than none — future sessions trust it at face value. Triggers: "memory audit", "审计memory", "查看所有memory", "做实际探测", "check my memories", after a big pivot or roughly monthly.'
---

# /memory-audit — 逐条实测，别信字面

Write-time rules can't prevent **post-write drift** (reality changing after a correct write).
This audit is the catch-net. The founding run (2026-07-02) found 10 of 18 memories rotten —
expect real findings, not a rubber stamp.

## Steps

1. **Inventory.** Read the memory index (`MEMORY.md`), then each memory file. Note
   index-line-vs-body contradictions as findings too (hook drift is rot).
2. **Extract verifiable claims** per memory: file/dir paths, function/export names, CLI flags,
   line numbers, model/deploy ids, "X doesn't exist yet / is pending / is unverified" statements,
   and any number that something else depends on.
3. **Probe cheaply.** `ls` / `grep` / `git log --oneline` / `which` / reading the named file's
   head. Do NOT launch expensive runs (evals, builds, deploys) just to verify — mark those
   UNVERIFIABLE-cheaply and list the command that WOULD verify.
4. **Classify** each memory: **CONFIRMED** · **STALE**（现实变了：写明现在的真相与证据）·
   **UNVERIFIABLE**（说明缺什么）。
5. **Fix per the write rules** (`memory-hygiene`):
   - Stale claim → edit the memory in place（supersede；点结果不删就补日期 "as of <date>"）。
   - Duplicated fact → merge into the canonical file, link `[[name]]` from the other.
   - Index line out of sync → fix in the same turn as the body edit.
   - **Deleting an entire memory file → list it and get the user's confirmation first**;
     body edits and supersedes are autonomous.
6. **Report** a compact table: memory / verdict / what changed / action taken. Lead with the
   count ("N audited, K stale fixed, M unverifiable").

## Calibration

- Prioritize memories that gate behavior (feedback/reference with ⭐, anything a session would
  act on without checking) over narrative project memories.
- Live state found squatting in a memory → move the pointer to the project's CHECKPOINT flow
  (`/checkpoint`), don't refresh it in place — refreshing live state in memory just re-arms the rot.
- Don't churn: a memory that is merely *incomplete* but correct needs no edit; only wrongness
  and staleness do.
