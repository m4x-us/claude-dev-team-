# Task — CTO Orchestrator

You are the CTO orchestrating a complete task cycle. The task is: $ARGUMENTS

Parse TASK_NUM from $ARGUMENTS (e.g., "#003" or "3" → 3).
Execute every phase without pausing.

---

## PHASE 0: CTO CONTEXT

**Step 0.1 — Read task definition:**
Read `.autocode/tasks.md`. Find Task #TASK_NUM.
Extract: TASK_DEFINITION (full block), DONE_WHEN ("Done when:" line), TASK_FILES ("File:" line).
If not found: "Task #N not found in .autocode/tasks.md" → stop.

If task status is COMPLETE: "Task #N is already marked complete. Run /audit #N to re-audit, or /tasks reopen #N first." Stop.

**Step 0.2 — Read cycle log:**
Read `.autocode/agents/cto.md`. In `## Task Cycle Log`, find entry for Task #TASK_NUM.
CYCLE_HISTORY = all cycle entries found (or "None — first cycle").
CURRENT_CYCLE = count of existing cycle entries + 1.

**Step 0.3 — Read agent memories:**
MEMORY_SECURITY ← `.autocode/agents/security.md` (or "None")
MEMORY_ARCHITECT ← `.autocode/agents/architect.md` (or "None")
MEMORY_QA ← `.autocode/agents/qa.md` (or "None")
PROJECT_PHILOSOPHY ← `~/.claude/autocode/philosophy.md` (warn if missing)

**Step 0.4 — Escalation pre-check:**
If CURRENT_CYCLE > 5: trigger ESCALATION (reason: CYCLE_LIMIT_EXCEEDED).
If any finding in CYCLE_HISTORY is annotated "ESCALATE": trigger ESCALATION (reason: REPEATED_FINDING).
If severity trended UP in 3 consecutive prior cycles: trigger ESCALATION (reason: SEVERITY_ESCALATING).
If "New findings introduced" > "Fixed this cycle" for 2 consecutive prior cycles: trigger ESCALATION (reason: REGRESSION_PATTERN).
Otherwise proceed to Step 0.5.

**Step 0.5 — Failure mode diagnosis for code failures (skip if first cycle):**

If CYCLE_HISTORY = "None — first cycle": skip this step. Set `TARGETED_GUIDANCE_MAP = "None"`.

Note: "Appears To" Drift, Philosophy Drift, and Severity Rationalization are handled in /audit.md at Agent C output time — they never appear in the cycle log. This step handles only CODE-level failure modes detectable from the cycle log summary.

Parse CYCLE_HISTORY for structured finding lines. Format: `[Fid|sev:N|category|file:function:line|description|annotation]`

**For each finding whose annotation segment = `REPEATED FROM CYCLE N`** (extract N):

1. Locate the matching finding from Cycle N-1 — same `description` text (first 50 chars, case-insensitive) in the Cycle N-1 structured log.
2. Extract `file:function` from both the current entry and the Cycle N-1 entry (4th pipe-delimited segment, before the colon-separated line number).
3. Map to failure mode:

**Surface Fix** — `file` OR `function` changed between current cycle and Cycle N-1 (same description, different location → symptom moved, root cause untouched)

**Pseudocode Tests** — `category` = "tests" AND `description` segment contains any of: "toBeDefined / toBeTruthy / toBeNull / not.toBeNull / .exist( / existence" (test exists but asserts nothing real)

**For each finding in "New findings introduced:" field** (these are NEW findings in files outside TASK_FILES):
Extract `file` from `[Fid|...|file:function:line|...]` — take the portion before the first `:` in segment 4.
If that `file` is NOT in TASK_FILES → **Scope Creep Regression**

**Fallback for old-format cycle log entries** (written before this structured format was adopted):
If CYCLE_HISTORY contains no structured `[Fid|...]` lines at all, fall back to prose-scan:
- Surface Fix: same finding text but different file:line mentioned
- Pseudocode Tests: finding mentions tests + any of "defined/truthy/exist/toBeDefined"
- Scope Creep Regression: "New findings introduced" field names a file not in TASK_FILES

---

**For each Surface Fix finding** — spawn a diagnostic agent:

"You are a senior software architect. The same audit finding has appeared across multiple cycles despite developer fixes. Diagnose why.

PHILOSOPHY: [PROJECT_PHILOSOPHY]

REPEATED FINDING across N cycles: [finding text]
WHAT WAS TRIED each cycle: [build approach entries from CYCLE_HISTORY]
FILE:LINE IN PRIOR CYCLES: [extract from findings annotations if available]

Diagnose the root cause — which of these patterns applies:
- Surface Fix: symptom addressed but root cause layer missed (e.g., route-level fix for middleware-layer problem)
- Scope Miss: fix applied at wrong architectural boundary
- Pseudocode Test Fix: test file added but assertions check existence not behavior
- Regression: prior fix broke adjacent code that re-introduces the issue

Output exactly:
DIAGNOSIS: [Surface Fix | Scope Miss | Pseudocode Test Fix | Regression]
ROOT_CAUSE: [one sentence — name specific file and function if determinable]
TARGETED_GUIDANCE: [file:function:line — specific change required. If location cannot be determined, write CONFIDENCE: LOW and explain why]
CONFIDENCE: HIGH / MEDIUM / LOW"

---

**For each Pseudocode Tests finding** — spawn a diagnostic agent:

"You are a test quality specialist. An audit cycle found tests that are pseudocode — they exist but assert existence rather than behavior.

REPEATED FINDING: [finding text]
CYCLE HISTORY — what test changes were made: [build approach entries from CYCLE_HISTORY that mention tests]

For each test identified as pseudocode:
1. State the weak assertion pattern (expect(x).toBeDefined() / expect(x).toBeTruthy() / expect(x).not.toBeNull() — without asserting a specific value)
2. State what MUST be asserted instead — the specific return value, state change, error thrown, or side effect that proves the behavior works
3. Produce the corrected assertion:

PSEUDOCODE_FINDING: [test name] in [file:line]
  Weak assertion: [current assertion]
  Required behavioral assertion: [what must change]
  Corrected THEN clause: [exact assertion code — this test MUST FAIL if the behavior is broken]

TARGETED_GUIDANCE: Rewrite [test name]::[assertion] to [exact behavioral check]. This test must fail when [specific condition that represents the bug being absent]."

---

**For Scope Creep Regression** — no diagnostic agent. Inject directly into TARGETED_GUIDANCE_MAP:

```
SCOPE_LOCK_MANDATE — Prior cycle introduced regressions outside TASK_FILES. Hard lock active for this cycle.
LOCKED FILES (changes ONLY permitted here): [TASK_FILES from task definition]
Any change to a file outside LOCKED FILES requires this exact line at the TOP of the plan, before any implementation steps:
  SCOPE_EXPANSION_REQUEST: [file] — [why the finding's root cause cannot be fixed within LOCKED FILES] — [specific finding this addresses]
The CTO will evaluate scope expansions. A plan that changes files outside LOCKED FILES without this line is REJECTED.
```

---

Capture all diagnostic agent outputs as TARGETED_GUIDANCE_MAP. Each entry replaces the generic ANTI-LOOP MANDATE for its specific finding in the next build cycle.

Print:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  /task #[TASK_NUM] — Cycle [CURRENT_CYCLE]
  [TASK_DEFINITION first line]
  [If diagnoses ran]: CTO diagnosis: [N] failure modes mapped — targeted guidance ready
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## PHASE 1: BUILD

**Step 1.1 — Assemble build context and call /autocode:**
Run `/autocode` with $ARGUMENTS set to:

```
TASK_DEFINITION:
[TASK_DEFINITION full block]

CYCLE_HISTORY:
[CYCLE_HISTORY]

DONE_WHEN:
[DONE_WHEN verbatim]

AGENT_MEMORIES:
Security: [MEMORY_SECURITY first 200 lines]
Architect: [MEMORY_ARCHITECT first 200 lines]
QA: [MEMORY_QA first 100 lines]

TARGETED_GUIDANCE_MAP:
[TARGETED_GUIDANCE_MAP entries, or "None — first cycle"]
```

**Step 1.2 — Read BUILD_RESULT:**
If BUILD_RESULT.status = "FAIL":
- Write CYCLE LOG ENTRY (see section below) with Scripts: FAIL
- Increment CURRENT_CYCLE. If > 5: trigger ESCALATION.
- Return to Step 1.1.

If BUILD_RESULT.status = "PASS": proceed to Step 1.3.

**Step 1.3 — Done When verification:**
Run DONE_WHEN mechanically:
- Contains a grep command: run it, check exit code
- References a test name: run the test
- Describes file state: check the file
- Describes UI behavior that genuinely cannot be verified in a terminal (visual layout, animation, hover state): mark DEFERRED, proceed. Note: "the feature works" is NOT UI behavior — run any grep, test, or file check that can prove it mechanically.

If DONE_WHEN FAILS: treat as severity-6 finding labeled "DONE_WHEN_FAIL: [condition] — [evidence]".
Inject into /audit via DONE_WHEN_FINDING.

If DONE_WHEN PASSES or DEFERRED: proceed to Phase 2.

---

## PHASE 2: AUDIT

**Step 2.1 — Call /audit:**
Run `/audit #[TASK_NUM]` with $ARGUMENTS set to:

```
TASK_DEFINITION:
[TASK_DEFINITION]

FULL_DIFF_OVERRIDE: [BUILD_RESULT.changed_files]

CYCLE_HISTORY:
[CYCLE_HISTORY — full prior log for this task, including this cycle's build approach]

[if Done When failed: DONE_WHEN_FINDING: DONE_WHEN_FAIL: [condition] — [evidence]]
```

**Step 2.2 — Read AUDIT_RESULT_FINAL:**
If verdict = "PASS":
- Capture as `FINAL_AUDIT_RESULT` in session context — hold this variable through Phase 3 and Phase 4 for memory writes. Do not discard it.
- Proceed to Phase 3.

If verdict = "FAIL" or "MAX_CYCLES":
- Check escalation triggers: any finding annotated "ESCALATE"? CURRENT_CYCLE ≥ 5? Severity trending UP 3 cycles? Regression pattern 2 consecutive cycles?
  → Yes to any: trigger ESCALATION.
- Write CYCLE LOG ENTRY (see section below).
- Increment CURRENT_CYCLE. Return to Phase 1 Step 1.1.

---

## CYCLE LOG WRITE

After each failed cycle, append to `.autocode/agents/cto.md` `## Task Cycle Log`.

Find or create task header:
```
### Task #[TASK_NUM] | [TASK_DEFINITION first line]
Status: In Progress | Cycle [CURRENT_CYCLE] | Started: [date of first cycle]
```

Compose cycle entry text:
```
#### Cycle [CURRENT_CYCLE] — [today's date]
Build approach: [specific file:function:line from /autocode planning summary — "added error handling" is REJECTED]
Scripts: [PASS / FAIL]
Audit findings (structured):
  [F{id}|sev:{severity}|{category}|{file}:{function}:{line}|{description}|{annotation}]
  [repeat one line per finding from AUDIT_RESULT_FINAL.findings — emit every finding]
Fixed this cycle: [comma-separated ids — findings from prior cycle no longer in AUDIT_RESULT_FINAL.findings, e.g. "F002, F003"]
Still open: [comma-separated ids — findings present this cycle AND in a prior cycle, e.g. "F001"]
New findings introduced: [comma-separated ids with file — findings annotated NEW whose file is NOT in TASK_FILES, e.g. "F004 (apps/web/src/lib/other.ts)"]
Regression signal: [YES if count(New findings introduced) > count(Fixed this cycle), else NO]
CTO diagnosis run: [YES with failure modes: [list], or NO — first cycle]
```

**Before appending to cto.md, validate the entry:**
Write the cycle entry text to `/tmp/cycle_entry_$$.txt`, then:

If `scripts/validate-cycle-log.sh` exists:
```
bash scripts/validate-cycle-log.sh /tmp/cycle_entry_$$.txt
```
- Exit 0: valid — append to cto.md.
- Exit 1: Cycle log entry is malformed. Print every `CYCLE_LOG_ERROR:` line. Fix all errors before writing. Do NOT write an invalid cycle log — an unvalidated log corrupts Step 0.5 failure mode detection in the next cycle.

If `scripts/validate-cycle-log.sh` does NOT exist: manually verify all 8 required fields are present and Build approach contains file:function before writing.

Then append the validated entry to `.autocode/agents/cto.md` `## Task Cycle Log`.

**Precision requirement:** "Build approach" MUST name specific file:function. Vague entries like "added error handling" are invalid and must be re-requested from /autocode planning output.

**Structured findings format — one line per finding:**
`[F001|sev:7|auth|apps/web/src/app/api/orders/route.ts:GET:47|Missing tenant isolation|NEW]`
Fields: id | severity with sev: prefix | category | file:function:line | description | annotation
This format is machine-parseable by Step 0.5 in the NEXT cycle. Descriptions with `|` chars were already blocked by validate-findings.sh (or prose fallback) so no escaping is needed.

---

## PHASE 3: WORLDCLASS

Run: `/worldclass Task #[TASK_NUM]: [TASK_DEFINITION first line]`
Wait for WORLDCLASS_RESULT.
Whether PASS or MAX_CYCLES: proceed to Phase 4.

---

## PHASE 4: COMPLETE

**Step 4.0 — Write agent memories (using FINAL_AUDIT_RESULT from Phase 2.2):**

Route FINAL_AUDIT_RESULT.findings to the correct memory file by `category`:
- category in ["security", "auth"] → `.autocode/agents/security.md`
- category in ["code-quality", "async", "error-handling", "feature-flag", "performance"] → `.autocode/agents/architect.md`
- category in ["tests", "requirements", "edge-case"] → `.autocode/agents/qa.md`

For each memory file M with at least one routed finding:

**If `scripts/update-memory.py` exists** (machine-enforced deduplication):

Build the JSON array of findings routed to M. Run:
```
python3 scripts/update-memory.py \
  --findings '[JSON array of findings routed to this memory file]' \
  --memory-file [M path]
```
- Exit 0: prints "OK: N added, N updated, N recurred" — memory file updated.
- Exit 1: prints MEMORY_ERROR — investigate and fix before proceeding.

**If `scripts/update-memory.py` does NOT exist** (graceful fallback):

For each finding F routed to M:
1. Read M. Search for existing entry where description[:50].lower() matches F.description[:50].lower() AND file = F.file AND function = F.function.
2. Match found (status: open) → update last-seen + increment occurrences.
3. Match found (status: resolved) → move back to open, add RECURRED note.
4. No match → append new entry.

Note: No resolved sweep. A finding absent from this audit may simply not have been in scope for this task. Automatic resolution would corrupt memory for findings from other tasks. Findings accumulate until a task explicitly confirms they are fixed across multiple audit cycles.

Print: "Agent memories updated — security ([N] open), architect ([N] open), qa ([N] open)."

**Step 4.1 — Run /reflect:**

Run: `/reflect Task #[TASK_NUM]: [TASK_DEFINITION first line]`

Edit `.autocode/tasks.md`: add `**Status: COMPLETE — [today's date]**` below Task #TASK_NUM Owner line.

Update cto.md Task Cycle Log for this task: change `Status: In Progress | Cycle N` → `Status: COMPLETE | Cycle N | Completed: [today's date]`

Print:
```
─────────────────────────────────────────────────────────────
  Task #[TASK_NUM] complete. WorldClass: [score]/100 | Cycles: [N]
  Review the diff and verify the result.

  Satisfied?       /tasks done #[TASK_NUM]
  Want re-audit?   /audit #[TASK_NUM]
─────────────────────────────────────────────────────────────
```

**Step 4.2 — Patterns graduation check:**
If `scripts/check-patterns-threshold.sh` exists:
Run: `bash scripts/check-patterns-threshold.sh .autocode/patterns.md`
- Exit 0: no threshold crossed — task cycle complete.
- Exit 1: one or more finding categories have crossed the graduation threshold (3+ occurrences, avg severity ≥ 6).
  Print to Max:
  ```
  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    PATTERNS THRESHOLD CROSSED
    [paste script output verbatim]

    Recurring findings are ready to become Rules.
    Run: /patterns   (you decide yes/no on each proposed Rule)
  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ```
  Do NOT auto-run /patterns. Signal to Max, let Max decide.
- Script not found: skip silently.

---

## ESCALATION

Append to `.autocode/agents/cto.md` `## Open Escalations`:
```
### [today's date] | Task #[TASK_NUM]: [TASK_DEFINITION first line]
Trigger: [CYCLE_LIMIT_EXCEEDED / REPEATED_FINDING: "[text]" in cycles N,N-1,N-2 / SEVERITY_ESCALATING / REGRESSION_PATTERN]
Cycles run: [N]
Unresolved findings (severity ≥ 5):
[list from most recent audit]

Cycle history summary:
[one line per cycle: what was tried, what audit found]

Options:
A) Continue with focused fix on [specific blocker] — estimated N more cycles
B) Accept current state with monitoring: [specific monitoring plan for unresolved finding]
C) Redesign [specific component that unresolved finding lives in]

Recommendation: [A/B/C] — [one sentence rationale]
Decision needed from: Max
```

Print:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ESCALATION — Task #[TASK_NUM]
  Trigger: [reason]
  Cycles run: [N]
  Unresolved: [top 3 findings]

  Escalation brief written to .autocode/agents/cto.md
  Run /team-health to see the full escalation queue.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Stop. Do not call /reflect on escalated tasks.

---

## RULES

- FORBIDDEN from writing code directly — all code changes go through /autocode
- FORBIDDEN from making code quality judgments — that is /audit's job
- FORBIDDEN from skipping the BUILD GATE — BUILD_RESULT PASS required before calling /audit
- FORBIDDEN from skipping Done When verification — run it or mark DEFERRED, never omit
- FORBIDDEN from closing a cycle log without "Fixed this cycle" and "Still open" fields
- FORBIDDEN from calling /reflect on escalated tasks
- Escalate on trigger conditions — do not absorb and keep cycling
- Cycle log is permanent — write it honestly even when nothing was fixed
- "Build approach" in the cycle log MUST include specific file:function:line — reject vague entries
