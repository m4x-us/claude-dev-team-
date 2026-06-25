# Tasks — Task List Management

Manage the development team's task list. The task is: $ARGUMENTS

---

## USAGE

- `/tasks` — print the full task list
- `/tasks #N` — print a specific task with full context
- `/tasks done #N` — mark a task complete
- `/tasks reopen #N` — re-open a completed task and notify the CTO log
- `/tasks update` — regenerate the task list using existing agent memories (lighter than /meet)
- `/tasks batch N` — print all tasks in a specific batch
- `/tasks open` — print only open tasks from the current sprint
- `/tasks debt` — display the full debt register (deferred WorldClass gaps)

---

## STEP 1: DETERMINE MODE

Parse $ARGUMENTS:
- Empty → MODE = list
- Matches `#[number]` → MODE = detail, TASK_NUM = [number]
- Starts with `done #` → MODE = complete, TASK_NUM = [number after #]
- Starts with `reopen #` → MODE = reopen, TASK_NUM = [number after #]
- Equals `update` → MODE = update
- Starts with `batch` → MODE = batch, BATCH_NUM = [number]
- Equals `open` → MODE = open
- Equals `debt` → MODE = debt

---

## MODE: list

Read `.autocode/tasks.md`. If not found:
```
No task list found. Run /meet to generate one.
```

Parse each `## Batch N` section and every `### Task #` entry within it. For each task extract: number, title (first line of description), Complexity field, Owner, Status.

Print a Unicode box-drawing table, one table per batch. Use these exact border characters: `─ │ ┌ ┐ └ ┘ ├ ┤ ┬ ┴ ┼`. Pad every cell with spaces so columns are consistent width across all rows.

Column widths (minimum — expand to fit longest value if needed):
- `#`: 6 chars
- `Complexity`: 13 chars
- `Title`: 48 chars (truncate to 45 + `...` if longer)
- `Owner`: 18 chars
- `Status`: 12 chars

Format:

```
Batch N — [theme]
┌────────┬───────────────┬──────────────────────────────────────────────────┬────────────────────┬──────────────┐
│ #      │ Complexity    │ Title                                            │ Owner              │ Status       │
├────────┼───────────────┼──────────────────────────────────────────────────┼────────────────────┼──────────────┤
│ #001   │ ⚡ Direct     │ Fix typo in lockout error message                │ QA Agent           │ open         │
│ #002   │ 🔧 Full       │ Add rate limiting to login route                 │ Security Agent     │ ✓ Complete   │
│ #003   │ ❓ No label   │ Refactor session middleware                      │ Architecture Agent │ open         │
└────────┴───────────────┴──────────────────────────────────────────────────┴────────────────────┴──────────────┘

Batch N+1 — [theme]
┌────────┬───────────────┬──────────────────────────────────────────────────┬────────────────────┬──────────────┐
│ #      │ Complexity    │ Title                                            │ Owner              │ Status       │
├────────┼───────────────┼──────────────────────────────────────────────────┼────────────────────┼──────────────┤
│ #004   │ 🔧 Full       │ ...                                              │ ...                │ open         │
└────────┴───────────────┴──────────────────────────────────────────────────┴────────────────────┴──────────────┘

[total open] open · [total complete] complete · [total] total
[N] tasks missing Complexity label — run /task #N to classify
```

Rules:
- Every table must have the same column widths — do not let columns vary between batches
- Every row padded to the same width — no ragged right edges
- Batch label appears on the line immediately above each table, not inside it
- Icons: `⚡ Direct` = no full dev team needed · `🔧 Full` = full team · `❓ No label` = unclassified

---

## MODE: detail (#N)

Read `.autocode/tasks.md`. Find the task with number matching TASK_NUM.

Also read the relevant agent memory for the task's Owner field:
- Owner = Security Agent → read `.autocode/agents/security.md`
- Owner = Architecture Agent → read `.autocode/agents/architect.md`
- Owner = QA Agent → read `.autocode/agents/qa.md`
- Owner = Docs Agent → read `.autocode/agents/docs.md`

Print:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Task #[N] — [title]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[full task block from tasks.md]

AGENT CONTEXT ([owner] memory on this area):
[extract from the agent's memory file any entries referencing the task's file or category]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Run: /autocode Task #[N]: [task description]
```

---

## MODE: complete (done #N)

Read `.autocode/tasks.md`. Find Task #TASK_NUM.

Verify the task's **Done when** condition is mechanically checkable. Ask the user to confirm it's been verified — do not silently mark done without confirmation.

Print:
```
Task #[N]: [description]
Done when: [condition]

Has this condition been verified? (confirm before marking complete)
```

If confirmed, edit `.autocode/tasks.md` to add `**Status: COMPLETE — [today's date]**` below the task's **Owner** line.

Also update CTO memory if open:
- Read `.autocode/agents/cto.md`
- Find the task in `## Open Escalations` if present and remove it
- Write updated file

---

## MODE: update

Re-generate the task list using existing agent memories. Lighter than full /meet — no fresh codebase scan, no Q&A.

Read:
1. `.autocode/agents/architect.md`, `security.md`, `qa.md` → `AGENT_MEMORIES`
2. `.autocode/tasks.md` → `EXISTING_TASKS`
3. `~/.claude/autocode/philosophy.md` → `PROJECT_PHILOSOPHY`
4. Run: `git log --oneline -20` → `GIT_LOG`

Spawn a single agent:

"You are updating a development task list. New work may have been completed since the list was generated.

PROJECT_PHILOSOPHY:
[PROJECT_PHILOSOPHY]

CURRENT TASK LIST:
[EXISTING_TASKS]

AGENT MEMORIES (open findings that may warrant new tasks):
[AGENT_MEMORIES]

RECENT GIT LOG:
[GIT_LOG]

Do the following:
1. Mark any tasks where the Done When condition is now met as COMPLETE
2. Add any new tasks for findings in AGENT_MEMORIES that have no corresponding task
3. Reorder batches if new tasks have changed the dependency graph

Produce the updated full contents of .autocode/tasks.md. Do not change task numbers for existing tasks — only add new ones sequentially."

Write updated content to `.autocode/tasks.md`.
Print: "✅ Task list updated."

---

## MODE: batch (batch N)

Read `.autocode/tasks.md`. Extract all tasks in Batch N. Print using the same formatted summary as MODE: list, scoped to that batch only.

---

## MODE: open

Read `.autocode/tasks.md`. Find all tasks WITHOUT a `Status: COMPLETE` line across all batches. Print using the same formatted summary as MODE: list, open tasks only.

---

## MODE: reopen (reopen #N)

Read `.autocode/tasks.md`. Find Task #TASK_NUM.

If task is not COMPLETE: print "Task #N is not marked complete — nothing to reopen." Stop.

If task is COMPLETE:
1. Edit `.autocode/tasks.md`: change `**Status: COMPLETE — [date]**` → `**Status: REOPENED — [today's date]**`
2. Read `.autocode/agents/cto.md`
3. In `## Task Cycle Log`, find or create task header for Task #TASK_NUM. Append:
   ```
   #### Reopened — [today's date]
   Status: Reopened | Reason: Re-audit requested via /tasks reopen
   ```
4. Write updated cto.md
5. Print:
   ```
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
     Task #[TASK_NUM] reopened. CTO cycle log updated.
     Run: /task #[TASK_NUM]  or  /audit #[TASK_NUM]
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   ```

---

## MODE: debt

Read `.autocode/debt.md`. If not found or contains no data rows:
```
No debt items recorded yet.
Debt items are auto-logged when WorldClass deductions appear — severity 1-3 silently,
severity ≥ 4 when explicitly accepted at the carry-forward gate.
```
Stop.

Parse each data row: date, source_task, category, description, severity, complexity, reason.

Print a box-drawing table (same column widths across all rows — pad with spaces, never let columns vary):

```
Debt Register — [N] item(s)
┌────────────┬──────────────┬───────────────┬──────────────────────────────────────────┬──────────┬─────────────┬──────────────────────────────┐
│ Date       │ Source Task  │ Category      │ Description                              │ Severity │ Complexity  │ Reason                       │
├────────────┼──────────────┼───────────────┼──────────────────────────────────────────┼──────────┼─────────────┼──────────────────────────────┤
│ 2026-06-25 │ Task #003    │ tests         │ Missing edge case for expired token      │ 2        │ ⚡ Direct   │ auto — minor WorldClass      │
│ 2026-06-25 │ Task #003    │ code-quality  │ Hardcoded timeout value                  │ 3        │ ⚡ Direct   │ auto — minor WorldClass      │
│ 2026-06-24 │ Task #001    │ async         │ No timeout on external API call          │ 5        │ 🔧 Full     │ not blocking — revisit Q3    │
└────────────┴──────────────┴───────────────┴──────────────────────────────────────────┴──────────┴─────────────┴──────────────────────────────┘

By category:
  tests: 1 item · avg severity 2.0
  code-quality: 1 item · avg severity 3.0
  async: 1 item · avg severity 5.0

⚡ Direct items: [N]  (batchable into nearby tasks — surfaced automatically at Step 0.0b)
🔧 Full items: [N]   (require a dedicated task — consider adding to the next batch)
```

Truncate Description to 40 chars + `...` if longer. Truncate Reason to 28 chars + `...` if longer.

---

## RULES

- Never delete a task — mark it COMPLETE, never remove it
- Never change a task number once assigned
- The Done When condition is mandatory for marking complete — never skip the verification step
- /tasks update does not replace /meet — it only incorporates memory findings, not fresh scans
