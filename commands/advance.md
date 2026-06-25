# Advance — Multi-CTO Parallel Orchestration

You are the parent CTO running `/advance`. The task is: $ARGUMENTS

This command analyzes the task list, groups open tasks into parallel streams that can run simultaneously, presents the plan to Max for approval, forks child CTOs to execute each stream in parallel, and consolidates the results.

---

## STREAM_ID check

If `STREAM_ID` is set in your context: you are a child CTO, not the parent.
- Read `.autocode/briefs/stream-[STREAM_ID].md`
- Execute the tasks listed in "Execution Order" using `Skill({ skill: "task", args: "#N" })` for each
- Write your completion summary to `.autocode/stream-[STREAM_ID]/completion.md`
- Stop after all your tasks complete. Do not continue to Phase 1.

If STREAM_ID is not set: you are the parent CTO. Continue below.

---

## Phase 1: Dependency Analysis

Read `.autocode/tasks.md`. Collect every open task (no `Status: COMPLETE` line).

For each open task, extract:
- `**File:**` — normalize to filename(s) only (strip `:line` suffix). If "Multiple — see What," extract all filenames from the `**What:**` description.
- `**Blocked by:**` — list of Task numbers. "Nothing" → empty list.
- `**Complexity:**` — Direct or Full.

**Algorithm — union-find clustering:**

Step A — File conflict graph:
Initialize each task as its own cluster. For every pair of tasks that share any normalized filename: `union(taskA, taskB)`. Tasks sharing a file cannot parallelize.

Step B — Dependency chains:
For every "Blocked by" relationship (task A is blocked by task B): `union(taskA, taskB)`. A blocked task must run in the same stream as its blocker (in topological order: blocker first).

Step C — Finalize:
Each union-find component = one stream candidate. Tasks within a stream execute in topological order (blockers before blocked).

Stream count = number of distinct components, capped at 4. If more than 4 components: merge the two smallest into one stream.

Exception: any task with `Complexity: Full` that touches more than 3 files gets its own stream unless a dependency chain forces merging.

Tasks with dependencies that cross component boundaries (one task blocked by tasks in two different streams) cannot parallelize. Move them to the **Sequential Queue** — they run after all parallel streams complete.

---

## Phase 2: Stream Assignment Presentation (MAX GATE 1)

Print:

```
╔═══════════════════════════════════════════════════════════════╗
║  ADVANCE PLAN — [N] streams · [N] parallel tasks             ║
║                                                               ║
║  Stream A — [N Direct / N Full] · exec order: #N → #N → #N  ║
║    Tasks: #001, #003, #007                                    ║
║    Files owned:                                               ║
║      [file path] (line N)                                     ║
║      [file path] (line N)                                     ║
║    Isolation check: no file overlap with other streams ✓     ║
╠═══════════════════════════════════════════════════════════════╣
║  Stream B — [N Direct / N Full] · exec order: #N → #N       ║
║    [same format]                                              ║
╠═══════════════════════════════════════════════════════════════╣
║  Sequential Queue (blocked by cross-stream dependencies):    ║
║    #009 — blocked by #003 (Stream A) + #004 (Stream B)       ║
║    #010 — blocked by #009                                     ║
║    These run after all streams complete.                      ║
║  — or —                                                       ║
║  No sequential queue — all dependencies are within-stream.   ║
╚═══════════════════════════════════════════════════════════════╝

Rationale:
  Stream A: [one sentence — why these tasks are domain-coherent and safe to parallelize]
  Stream B: [one sentence]
  Sequential: [one sentence explaining the cross-stream dependency if any]

Approve this plan? [yes / adjust / no]
```

Rules:
- Every stream must show "Isolation check: no file overlap with other streams ✓"
- If any overlap exists: do not present the plan. Re-run Phase 1 with those tasks merged.
- "Rationale" is mandatory — never omit it.
- If all dependencies are within-stream: explicitly print "No sequential queue."

Wait for Max input.
- `adjust`: Max describes what to change. Re-cluster with the manual override, re-present.
- `no`: Print "Advance aborted." Stop.
- `yes`: Proceed to Phase 3.

---

## Phase 3: Brief Generation (MAX GATE 2 — optional inspect)

For each stream, create `.autocode/briefs/` directory if it doesn't exist, then write `.autocode/briefs/stream-[X].md`:

```markdown
# Stream [X] Brief — /advance [today's date]

## Your Role
You are a child CTO executing Stream [X] of a parallel /advance session.
Work exclusively on the files listed below. You MUST NOT modify any other file.

## STREAM_ID
Your STREAM_ID is: [X]
The task command will automatically redirect all .autocode/ writes to
.autocode/stream-[X]/ when STREAM_ID is set in your context.

## Execution Order
Run these tasks in this exact order:
1. Skill({ skill: "task", args: "#[NUM]" })  — [task title]
2. Skill({ skill: "task", args: "#[NUM]" })  — [task title]
[continue for each task in topological order]

## Files You Own (edit ONLY these)
[Exact file paths from the task definitions for this stream]

## Off-Limits Files (DO NOT MODIFY — owned by other streams)
[Exact file paths owned by other streams]

## Task Definitions
[Full verbatim task blocks from .autocode/tasks.md for each task in this stream]

## Agent Memories
[First 150 lines of the most relevant agent memory file for this stream's domain:
 tasks in security/auth categories → .autocode/agents/security.md
 tasks in async/error-handling/data-loss categories → .autocode/agents/architect.md
 tasks in tests/edge-case categories → .autocode/agents/qa.md
 If stream spans multiple domains: include both relevant files]

## Done When
All tasks in this stream are complete when each /task command confirms its done-when
condition is met and writes COMPLETE status to .autocode/stream-[X]/tasks.md.
Write a completion summary to .autocode/stream-[X]/completion.md with:
- Number of tasks closed
- Number of debt entries logged
- Number of carry-forward tasks generated
- Any tasks where done-when was NOT met (be explicit)
```

After writing all briefs, print:
```
Briefs written to .autocode/briefs/. Inspect before launching?
  [A] Stream A  [B] Stream B  [no] Launch now
```

Wait for input. If a stream letter (A, B, C...): print that brief in full, then ask again. If `no`: proceed to Phase 4.

---

## Phase 4: Fork Execution (parallel streams)

**Step 4a — Create stream state directories:**
```bash
mkdir -p .autocode/stream-A
mkdir -p .autocode/stream-B
[one per stream]
```

**Step 4b — Spawn all child CTOs in parallel:**

In a single message, launch one Agent (fork) per stream. Each fork gets this directive:

```
STREAM_ID=[X]

You are executing the /advance stream brief at .autocode/briefs/stream-[X].md.

Read that file now. Then execute the "Execution Order" exactly as written.

After all tasks complete, write your completion summary to .autocode/stream-[X]/completion.md.
```

Launch all forks in one message (multiple Agent tool calls in a single response) so they run in parallel. Do not stagger them.

**Step 4c — After all forks complete, read completion summaries and report:**

```
Stream A — [content of .autocode/stream-A/completion.md]
Stream B — [content of .autocode/stream-B/completion.md]
[etc.]
```

If any stream reported incomplete tasks, list them. Proceed to Step 4d.

**Step 4d — Incomplete task handling:**

For each incomplete task:
```
Stream [X] task #[N] was not completed.
Done when: [condition from task definition]

Options:
  [retry] — re-run this stream (fresh fork, same brief)
  [manual] — mark for manual completion; continue with consolidation
  [skip]   — carry forward as a new task in the next batch
```

Wait for Max input for each incomplete task before proceeding. If `retry`: spawn a new fork for that stream only. After it completes: continue.

---

## Phase 5: Consolidation (MAX GATE 3)

**Step 5a — Merge autocode state:**

For each stream X:

**Tasks:** Read `.autocode/stream-[X]/tasks.md`. Find all lines containing `Status: COMPLETE`. For each matching task, update the same task in main `.autocode/tasks.md` to add the same COMPLETE status line.

**Debt:** Read `.autocode/stream-[X]/debt.md`. Extract all non-header rows. Append to main `.autocode/debt.md`. (Create main file with header if it doesn't exist.)

**Carry-forward:** Read `.autocode/stream-[X]/carry-forward-log.md` if it exists. Extract any new task definitions. Append to the end of the current batch in main `.autocode/tasks.md`, assigning the next available sequential task numbers.

**Step 5b — Sequential queue execution:**

If there were tasks in the Sequential Queue from Phase 1:
```
Parallel streams complete. Now running sequential queue:
  Task #[N] — [title]  (blocked by: [streams that needed to complete first])
  Task #[N] — [title]  (blocked by: Task #[N])
```

Run them in topological order using `Skill({ skill: "task", args: "#N" })` in the main session. These run one at a time, not in parallel.

**Step 5c — Final report (MAX GATE 3):**

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ADVANCE COMPLETE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Parallel streams: [A ✓  B ✓  C ✓  (or ⚠ for incomplete)]
  Sequential queue: [N tasks · all ✓  or  list incomplete]

  Tasks closed: [N]
  Carry-forward tasks added to Batch [N]: [N]
  Debt entries logged: [N]

  New carry-forward tasks:
    #[NUM] — [title] | severity [N] | [Direct/Full]
    [repeat]

  Incomplete tasks requiring manual attention:
    [list, or "None"]

  Commit all changes? [yes / review changes first]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

If `review changes first`: print git diff summary (file names and line counts changed). Then ask again.

Only commit after Max confirms `yes`. The commit message format:
```
/advance: close [N] tasks across [N] streams

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
```

---

## Rules

- Never spawn child CTOs without Max approving the stream plan first (MAX GATE 1)
- Never launch streams without Max having the option to inspect briefs (MAX GATE 2)
- Never commit without Max approving the final consolidated state (MAX GATE 3)
- Never put tasks with shared files in different streams — verify mechanically in Phase 1
- Never declare a sequential queue empty without explicitly checking for cross-stream dependencies
- Stream rationale is not optional — every stream must have one sentence explaining domain coherence
- A child CTO that fails its done-when condition is never silently marked complete
