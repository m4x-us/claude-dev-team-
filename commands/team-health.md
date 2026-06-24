# Team Health — CTO Dashboard

You are generating the CTO dashboard. No scans. No agents. Pure reporting from existing `.autocode/` files.

---

## STEP 1: READ ALL SOURCES

Read silently:
1. `.autocode/agents/cto.md` → `CTO_MEMORY`
2. `.autocode/agents/security.md` → `MEMORY_SECURITY`
3. `.autocode/agents/architect.md` → `MEMORY_ARCHITECT`
4. `.autocode/agents/qa.md` → `MEMORY_QA`
5. `.autocode/agents/docs.md` → `MEMORY_DOCS`
6. `.autocode/tasks.md` → `TASK_LIST`
7. `.autocode/worldclass-trends.md` → `WORLDCLASS_TRENDS` (last 10 rows, or "No data")
8. `.autocode/trends.md` → `AUDIT_TRENDS` (last 10 rows, or "No data")
9. `.autocode/patterns.md` → `PATTERNS` (count occurrences per category)

If `.autocode/agents/cto.md` does not exist:
```
No team memory found. Run /meet to initialize the development team.
```
Stop.

---

## STEP 2: COMPUTE METRICS

From WORLDCLASS_TRENDS (last 5 PASS rows):
- Average WorldClass score = sum of scores / count
- Score trend: compare avg of last 3 vs prior 3 (if 6+ rows): IMPROVING / STABLE / DEGRADING

From AUDIT_TRENDS (last 5 rows):
- PASS rate = PASS count / total count × 100%
- MAX_CYCLES rate = MAX_CYCLES count / total count × 100%

From PATTERNS:
- Most frequent category (count all occurrences per category label)
- Any category with 3+ occurrences = systemic pattern

From TASK_LIST:
- Find [CURRENT SPRINT] batch, count open vs. done tasks
- Count total backlog tasks
- Extract any tasks with severity 8-9 that are still open

From CTO_MEMORY `## Task Cycle Log`:
- For each in-progress task (Status: In Progress), extract task number, description, and current cycle number
- Flag any task at Cycle 4+ as approaching escalation threshold

---

## STEP 3: PRINT DASHBOARD

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  TEAM HEALTH DASHBOARD — [today's date]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

AGENT PERFORMANCE
  Security:  [runs from memory frontmatter] runs | blind spots: [## Known Blind Spots content or "none"]
  Architect: [runs] runs | blind spots: [list or "none"]
  QA:        [runs] runs | blind spots: [list or "none"]
  Docs:      [runs] runs | blind spots: [list or "none"]

QUALITY TRENDS
  WorldClass avg (last 5): [N]/100  [↑ IMPROVING / → STABLE / ↓ DEGRADING / "—" if <3 runs]
  Audit PASS rate (last 5): [N]%  [↑ / → / ↓ / "—"]
  Most frequent deduction:  [category] ([N] occurrences)
  Systemic patterns:        [list categories with 3+ occurrences, or "None yet"]

TASK STATUS
  Current sprint: Batch [N] — [N open] open | [N done] done | [N total] total
  Total backlog:  [N] tasks across [N] batches
  Critical open (severity 8-9): [list Task #N with description, or "None"]
  In-progress tasks (active cycles):
    [Task #N — [description] — Cycle N/5]
    [or: "No tasks in active cycles"]
    [⚠️ Task #N at Cycle N/5 — approaching escalation threshold (for any task at Cycle 4+)]

OPEN ESCALATIONS
  [list from CTO_MEMORY ## Open Escalations — Task # | issue | days since logged]
  [or "None — all tasks resolved or within cycle limits"]

CONFLICT REGISTER
  [list from CTO_MEMORY ## Conflict Register — file | agents | status]
  [or "None — no unresolved agent conflicts"]

RECOMMENDED ACTIONS
  [1-3 concrete next steps based on the data above]
  [Example: "Run /patterns — [category] has appeared 4 times, may warrant philosophy update"]
  [Example: "Task #N at Cycle 4/5 — escalation threshold approaching. Run /task #N to continue or /findings #N to inject owner guidance."]
  [Example: "Security agent has 2 unresolved open findings — run /consult security"]
  [If any task is at Cycle 4+: always include the escalation warning as a recommended action]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## RULES

- Never spawn agents — this command reads only
- Never fabricate metrics — if data is missing, print "—" not a number
- Recommended actions must be based on actual data, not generic advice
- If no tasks exist, print the task status section as "No task list — run /meet to generate one"
