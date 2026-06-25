# Meet — Dev Team Onboarding

You are running the team onboarding ritual. The task is: $ARGUMENTS

When invoked with no arguments, run a full codebase examination. When invoked with a module name or path, scope the examination to that area.

This command brings the development team up to speed: reads all context, examines the codebase through four specialized lenses, asks the project owner informed questions, generates a numbered task list, and writes agent memories so every subsequent run builds on this session.

---

## PHASE 0: LOAD ALL CONTEXT

Run in the orchestrating session:

```
mkdir -p .autocode/agents
```

Read in this order (all mandatory):

1. `~/.claude/autocode/philosophy.md` in full → `PROJECT_PHILOSOPHY`
2. `CLAUDE.md` → `PROJECT_CONTEXT`
3. `docs/STATUS.md` → `PROJECT_STATUS` (or "Not found" if absent)
4. `.autocode/reflections.md` → `REFLECTION_LOG` (full contents, or "None yet")
5. `.autocode/agents/cto.md` → `CTO_MEMORY` (or "No CTO memory — this is the first /meet")
6. `.autocode/agents/security.md` → `MEMORY_SECURITY` (or "None yet")
7. `.autocode/agents/architect.md` → `MEMORY_ARCHITECT` (or "None yet")
8. `.autocode/agents/qa.md` → `MEMORY_QA` (or "None yet")
9. `.autocode/agents/docs.md` → `MEMORY_DOCS` (or "None yet")
10. `.autocode/tasks.md` if exists, else `docs/TODO_AUDIT_FIXES.md` if exists → `EXISTING_TASKS` (first 100 lines, or "None")
11. Run: `git log --oneline -50` → `GIT_LOG`
12. Run: `git diff HEAD~10..HEAD --name-only` → `RECENT_FILES`
13. Run: `pnpm audit --json 2>/dev/null | head -30` → `CVE_SNAPSHOT` (or skip if not a Node.js project)
14. Read `ROADMAP.md`, `docs/ROADMAP.md`, or `docs/PLANNED.md` (first found, first 150 lines) → `PRODUCT_ROADMAP` (or "None found")
15. Run: `grep -rn "TODO\|FIXME\|PLANNED\|COMING SOON\|NOT YET\|NYI" --include="*.ts" --include="*.tsx" --include="*.md" . | grep -v node_modules | grep -v ".next" | head -60` → `CODE_TODOS`

From GIT_LOG, identify:
- **CHURN_ZONES:** files or directories appearing in 5+ of the last 50 commit messages
- **DEAD_ZONES:** modules mentioned in PROJECT_CONTEXT with no recent commits

**If CTO_MEMORY exists (returning team), print this team briefing now — before any examination:**

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  TEAM BRIEFING — [today's date]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  [Extract from CTO_MEMORY Team Health table:]
  Security:  [N] runs | reject rate [N]% | blind spots: [list or "none recorded"]
  Architect: [N] runs | reject rate [N]% | blind spots: [list or "none recorded"]
  QA:        [N] runs | reject rate [N]% | blind spots: [list or "none recorded"]
  Docs:      [N] runs | reject rate [N]% | blind spots: [list or "none recorded"]

  Open escalations: [N] awaiting decision
  Last WorldClass avg: [N]/100 (or "no data yet")
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## PHASE 1: FOUR PARALLEL EXAMINATION AGENTS

Spawn all four simultaneously. Each receives its role's memory plus the shared context.

---

**Examination Agent 1 — Architecture**

Spawn an independent agent with this prompt:

"You are the Architecture Agent onboarding to this project. Read your prior memory first — do not re-discover what you already know.

PROJECT_PHILOSOPHY — the complete standard you enforce:
[PROJECT_PHILOSOPHY]

PRIOR MEMORY (what you knew from previous sessions):
[MEMORY_ARCHITECT]

PROJECT CONTEXT:
[PROJECT_CONTEXT]

RECENT FILES (last 10 commits):
[RECENT_FILES]

CHURN ZONES (files with high change rate — examine these first):
[CHURN_ZONES]

For each churn zone file: read the first 100 lines and assess against the 15 Rules.

BLAST RADIUS: For each churn zone basename, run:
  grep -r 'from.*[basename]' --include='*.ts' --include='*.tsx' -l . | grep -v node_modules | head -20

Report the top 5 most-imported files — these are high-blast-radius (many dependents + changes = risk).

Report exactly:
1. LAYER CAKE violations — files exceeding size limits, upward imports
2. 15 RULES violations — Rule #, file, specific line/pattern
3. BLAST RADIUS map — top 5 most-imported files with importer count
4. MODULE EXTRACTION candidates — logic belonging in @ordinatio/* but living in app code
5. DEAD ZONES — modules in docs with no recent commits (stable or forgotten?)
6. ALREADY KNOWN — items from prior memory that are still open (do not re-report resolved)

Every finding must cite file:line. No 'appears to' or 'may have' language.
ARCHITECTURE_FINDINGS: [all findings as a numbered list]"

Capture as `FINDINGS_ARCHITECT`.

---

**Examination Agent 2 — Security**

Spawn an independent agent simultaneously with this prompt:

"You are the Security Agent onboarding to this project. Read your prior memory first.

PROJECT_PHILOSOPHY:
[PROJECT_PHILOSOPHY]

PRIOR MEMORY (what you knew from previous sessions):
[MEMORY_SECURITY]

PROJECT CONTEXT:
[PROJECT_CONTEXT]

RECENT FILES:
[RECENT_FILES]

CVE SNAPSHOT:
[CVE_SNAPSHOT]

TOYOTA EVIDENCE RULE: For every checklist item, produce ONE of:
  VERIFIED: [file:line] — [what you see]
  FINDING: [description]
  N/A: [specific reason this doesn't apply]

You are FORBIDDEN from writing 'No issues found' without citing code. If you cannot find the code handling a checklist item, that is a FINDING, not a VERIFIED.

CHECKLIST:

MULTI-TENANT ISOLATION:
[ ] Can org A's session access org B's data? Cite where tenant scoping is enforced in DB queries.
[ ] Every write route: is authorization checked (ownership/role), not just authentication?
[ ] Can a clothier-role perform admin actions? Cite role check location.

INPUT VALIDATION:
[ ] User-controlled input validated before use? Cite validation function.
[ ] Any raw SQL string interpolation? Grep: grep -rn 'query.*\$\{' --include='*.ts' .
[ ] User input in file paths or exec calls?

DATA EXPOSURE:
[ ] Secrets/tokens logged or returned in API responses? Grep: grep -rn 'console.log.*token\|console.log.*secret' --include='*.ts' .
[ ] Client data enumerable by non-owners?
[ ] Error messages expose internal paths/schema to users?

DEPENDENCY HEALTH:
[ ] CVE count from CVE_SNAPSHOT — report number
[ ] Any dep with version 0.x.x in package.json files (pre-stable = unstable)?

ALREADY KNOWN — items from prior memory that are still open (do not re-report resolved)

SECURITY_FINDINGS: [all findings as numbered list with VERIFIED/FINDING/N/A prefix]"

Capture as `FINDINGS_SECURITY`.

---

**Examination Agent 3 — QA**

Spawn an independent agent simultaneously with this prompt:

"You are the QA Agent onboarding to this project. Read your prior memory first.

PROJECT_PHILOSOPHY (especially Rule 5: Test Ruthlessly, Rule 13: Test the Seams, Rule 14: Component Truth):
[PROJECT_PHILOSOPHY]

PRIOR MEMORY (what you knew from previous sessions):
[MEMORY_QA]

PROJECT CONTEXT:
[PROJECT_CONTEXT]

RECENT FILES:
[RECENT_FILES]

CHECKLIST:

TEST EXISTENCE:
[ ] For each file in RECENT_FILES: does a co-located .test.ts / .test.tsx exist?
    List files changed in last 10 commits WITHOUT a test file.

PSEUDOCODE TEST DETECTION:
[ ] Run: grep -rn 'expect(true).toBe(true)\|expect(1).toBe(1)\|toBeTruthy()\s*$' --include='*.test.*' . | grep -v node_modules
    Any hit is a pseudocode test — report the test name and file.

SKIPPED TESTS:
[ ] Run: grep -rn 'it.skip\|xit\|xdescribe\|test.skip' --include='*.test.*' . | grep -v node_modules
    Report all skipped tests. Skipped tests are debt.

SEAM COVERAGE (Rule 13):
[ ] Do critical paths have integration tests?
    Critical paths: auth flows, order placement, payment processing, external API calls.
    Grep for test files in these areas and assess.

MOCK QUALITY:
[ ] Are any tests asserting mock behavior instead of real behavior?
    (Tests that mock the thing they're testing prove nothing.)

ALREADY KNOWN — items from prior memory that are still open

QA_FINDINGS: [all findings as numbered list]"

Capture as `FINDINGS_QA`.

---

**Examination Agent 4 — Documentation**

Spawn an independent agent simultaneously with this prompt:

"You are the Documentation Agent onboarding to this project.

PROJECT_PHILOSOPHY:
[PROJECT_PHILOSOPHY]

PRIOR MEMORY (what you knew from previous sessions):
[MEMORY_DOCS]

CLAUDE.md (first 200 lines):
[PROJECT_CONTEXT first 200 lines]

STATUS.md:
[PROJECT_STATUS]

GIT LOG (last 50 commits):
[GIT_LOG]

THE TEST: If a new Claude Code session started right now with only CLAUDE.md and STATUS.md, would it know about each recent feature? For each commit in GIT_LOG that shipped a feature — does CLAUDE.md or STATUS.md mention it?

CHECKLIST:

COVERAGE GAPS:
[ ] For each feature commit in GIT_LOG: is it reflected in CLAUDE.md or STATUS.md?
    List any features shipped but not documented.

ACCURACY:
[ ] Run: grep -r 'it(' --include='*.test.*' . | grep -v node_modules | wc -l
    Compare to the test count claimed in CLAUDE.md. Stale if off by >10%.
[ ] Module count in CLAUDE.md — does it match actual module directories?
[ ] Any STATUS.md section marked 'in progress' that looks done based on GIT_LOG?

STALE CONTENT:
[ ] Any doc references to removed features, old file paths, or renamed packages?

ALREADY KNOWN — items from prior memory that are still open

DOCS_FINDINGS: [all findings as numbered list with 'should say X, currently says Y' format]"

Capture as `FINDINGS_DOCS`.

---

**Examination Agent 5 — Product Completeness**

Spawn an independent agent simultaneously with this prompt:

"You are a Product Agent onboarding to this project. You are NOT looking for code quality problems — the other agents handle that. You are looking at this product through the eyes of a customer and a business owner: what is it supposed to do, what does it actually do, and what is obviously missing?

PROJECT CONTEXT:
[PROJECT_CONTEXT]

PROJECT STATUS:
[PROJECT_STATUS]

EXISTING PRODUCT ROADMAP (if any):
[PRODUCT_ROADMAP]

CODE TODO MARKERS:
[CODE_TODOS]

GIT LOG (last 50 commits — tells you what was recently built):
[GIT_LOG]

RECENT FILES (last 10 commits):
[RECENT_FILES]

DEAD ZONES (modules mentioned in docs with no recent commits):
[DEAD_ZONES]

Your job — four lenses:

LENS 1 — WHAT EXISTS vs WHAT WAS PROMISED
Compare PROJECT_STATUS and PRODUCT_ROADMAP against GIT_LOG and RECENT_FILES.
What was described as coming or planned that has no matching commit?
What is marked 'in progress' in docs but has no recent activity?
List each gap as: PLANNED: [feature] | STATUS: [no commits / stalled / partially built] | EVIDENCE: [doc line or TODO marker]

LENS 2 — DEAD ZONES (forgotten features)
For each DEAD_ZONE module: is it complete and stable, or incomplete and abandoned?
A stable module has no TODOs and was finished in a prior phase. An abandoned module has TODOs, stubs, or a STATUS entry that says 'in progress' but no recent commits.
List each as: MODULE: [name] | VERDICT: [stable / abandoned] | EVIDENCE: [specific indicator]

LENS 3 — VISIBLE INCOMPLETENESS
From CODE_TODOS: which are product gaps (missing features) vs code debt (quality issues)?
Product gaps = functionality users would notice is missing.
Code debt = internal quality issues (handled by other agents).
List only product gaps as: TODO: [description] | FILE: [file:line] | IMPACT: [what a user cannot do because of this]

LENS 4 — CUSTOMER EXPERIENCE GAPS
Based purely on what the product claims to do (PROJECT_CONTEXT), what would a first-time user hit that would feel broken or incomplete?
Do NOT speculate — only list gaps you can ground in specific evidence from the context or code markers.

Output format:
PRODUCT_FINDINGS: [numbered list — each item covers one of the four lenses, cites specific evidence]"

Capture as `FINDINGS_PRODUCT`.

---

Wait for all five agents to complete before proceeding.

---

## PHASE 2: SYNTHESIS + INFORMED QUESTIONS

Spawn a single synthesis agent:

"You are a senior CTO who just received four examination reports from your team.
Your job: identify the 4–5 most important questions to ask the project owner
before generating the task list.

PROJECT PHILOSOPHY:
[PROJECT_PHILOSOPHY]

Architecture findings:
[FINDINGS_ARCHITECT]

Security findings:
[FINDINGS_SECURITY]

QA findings:
[FINDINGS_QA]

Documentation findings:
[FINDINGS_DOCS]

EXISTING TASKS (if any):
[EXISTING_TASKS]

GIT LOG (last 20 commits):
[last 20 lines of GIT_LOG]

CRITICAL RULE: Questions must be EARNED by the findings — not generic.
Every question must cite a specific finding. Required format:
  Q1: 'I found [specific finding]. Does that mean [specific decision needed]?'

Questions that would be generic and are FORBIDDEN:
  - 'What are your goals?'
  - 'What should we prioritize?'
  - 'What's most important to you?'

Questions come in two types — produce both:

BUSINESS QUESTIONS (always ask these 2 — regardless of findings):
B1: 'What is the single most important thing this product needs to do for customers in the next 90 days — the thing that would make the biggest difference to the business?'
B2: 'What are customers or users blocked from doing right now that they need to be able to do? What's the most common complaint or request?'

FINDING QUESTIONS (earned by specific findings — produce 3):
Every finding question must cite a specific finding. Required format:
  Q1: 'I found [specific finding]. Does that mean [specific decision needed]?'

Finding questions should surface:
- Priority conflicts (multiple critical findings — which comes first?)
- Intentional vs. accidental (is this a known tradeoff or a real gap?)
- Strategic direction (does Max's answer change the batch ordering?)
- Product gaps (does the product agent finding match Max's understanding of what's built?)

Produce exactly 7 questions total: B1, B2, Q1, Q2, Q3, Q4, Q5. Number them 1–7."

Capture the synthesis agent's output as `SYNTHESIS_QUESTIONS`.

**Present questions to Max:**

Use AskUserQuestion with the 4–5 generated questions. Format them clearly.

Capture Max's answers as `OWNER_ANSWERS`.

---

## PHASE 3: TASK LIST GENERATION

Spawn a single task list agent:

"You are generating a formal, numbered task list for a development team.
This list is the team's work order — it must be specific enough to execute without ambiguity.

PROJECT PHILOSOPHY (the standard all tasks must meet):
[PROJECT_PHILOSOPHY]

Architecture findings:
[FINDINGS_ARCHITECT]

Security findings:
[FINDINGS_SECURITY]

QA findings:
[FINDINGS_QA]

Documentation findings:
[FINDINGS_DOCS]

Product completeness findings (what's missing from the product, not just from the code):
[FINDINGS_PRODUCT]

Existing product roadmap:
[PRODUCT_ROADMAP]

Project owner's answers (especially B1 and B2 — these define what matters most):
[OWNER_ANSWERS]

Existing tasks to carry forward (open items only):
[EXISTING_TASKS]

Generate the full contents of .autocode/tasks.md using EXACTLY this format:

---
# Task List — [extract project name from PROJECT_CONTEXT]
Generated: [today's date] | Method: /meet
Last updated: [today's date]

## Summary
[N] tasks across [N] batches
Critical (severity 8-9): [N] | High (6-7): [N] | Medium (4-5): [N] | Low (1-3): [N]
Current Sprint: Batch 1 — [N] tasks

## Definition of Done (applies to every task)
**Tier 1 — Locally Complete:** Tests pass, no empty catch{}, no `as any`, self-review Five Forcing Functions
**Tier 2 — Team Integration:** Architecture check (no layer violations), agent sign-off, integration tests pass
**Tier 3 — Deployment Ready:** Security audit (OWASP #1-3 checked), backwards compat verified, feature flag if applicable
**Tier 4 — Shipped Complete:** Docs updated (CLAUDE.md / STATUS.md), error ref IDs present, shipping gate passes
Tiers 1-2 are mandatory for all tasks. Tiers 3-4 required for new features and security-adjacent changes.

## Batch 1 — [theme] [CURRENT SPRINT]
Dependency: None. All subsequent batches blocked until this completes.
Theme: [what all these tasks have in common — e.g., 'Security foundation fixes']

### Task #001 | [category] | severity [N]
**What:** [specific description — exactly what to change, not vague]
**Why:** [business impact OR cite the specific Rule # violated]
**File:** [file:line or 'Multiple — see What']
**Blocks:** [Task #N, Task #N — or 'Nothing']
**Blocked by:** Nothing
**Risk:** [Low / Medium (with mitigation) / High (with mitigation)]
**Completion gates:** [Security Agent sign-off / Architecture Agent sign-off / etc.]
**Done when:** [mechanically checkable condition — grep output, test count, script output]
**Owner:** [Security Agent / Architecture Agent / QA Agent / Docs Agent]

[repeat for each task in batch]

## Batch 2 — [theme] [BACKLOG]
Dependency: Batch 1 complete.

[repeat batch structure]

## Escalation Queue
[any findings the team cannot resolve without Max's input — format: Issue | Why it needs a decision | Options]

---

HARD RULES for task generation:
1. Tasks are ordered by DEPENDENCY (DAG flattening), not priority alone
2. Foundation tasks (auth, data model, shared packages) ALWAYS come first
3. Never put a Batch 2 task that depends on Batch 1 work in Batch 1
4. Every 'done when' must be mechanically checkable — NEVER 'feature works correctly'
5. Task numbers are sequential starting at 001 and NEVER reused
6. Carry forward open tasks from EXISTING_TASKS with new numbers
7. Owner's answers OVERRIDE default ordering — if Max said X is priority, X goes in Batch 1
8. Mark current work batch as [CURRENT SPRINT]; all others as [BACKLOG]
9. High-risk tasks (auth, data model, payments) require Tier 3-4 DoD notation
10. Never create a task without a mechanically checkable done condition
11. TWO TASK TYPES — both must appear in the list:
    - FIX tasks: address findings from Architecture, Security, QA, Docs agents (code quality, correctness)
    - BUILD tasks: address findings from the Product agent and owner's B1/B2 answers (features customers need)
    Use [fix] or [build] as the category tag on each task header.
    Owner's B1 answer (90-day priority) must generate at least one BUILD task in Batch 1 or 2.
    Owner's B2 answer (customer blockers) must generate at least one BUILD task per blocker named.
12. BUILD tasks for features must describe the user experience, not just the code change.
    What: describe what the user can do after this is built, then the technical implementation.
    Done when: must be verifiable from the user's perspective AND from the code (e.g., 'User can submit form without page reload — verified by Playwright test + API returns 200')"

Write the output to `.autocode/tasks.md`.

---

## PHASE 4: WRITE AGENT MEMORIES

Spawn four agents simultaneously to write initial memory files:

**Memory Writer — Architecture**
"Write the initial memory file for the Architecture Agent. Base it on this examination session.

Findings from this session:
[FINDINGS_ARCHITECT]

Project context:
[PROJECT_CONTEXT — first 50 lines only]

Today's date: [today's date]

Write a markdown file using EXACTLY this structure:

---
agent: architect
last-updated: [today's date]
runs: 1
---
# Architecture Agent Memory — [project name]

## Codebase Model
[What you now know about this specific codebase: layer structure, key modules, blast-radius files, known patterns. Specific — not generic.]

## Recurring Patterns
[Patterns found in this session that may recur. With file references.]

## Known Blind Spots
[Leave empty — populated by /patterns after multiple runs]

## Past Findings — Open
[Every finding from this session, with Task # from tasks.md where assigned. Format: Task #N | file:line | description]

## Past Findings — Resolved
[None yet]
---"

Write to `.autocode/agents/architect.md`.

**Memory Writer — Security** (same structure, based on FINDINGS_SECURITY)
Write to `.autocode/agents/security.md`.

**Memory Writer — QA** (same structure, based on FINDINGS_QA)
Write to `.autocode/agents/qa.md`.

**Memory Writer — Documentation** (same structure, based on FINDINGS_DOCS)
Write to `.autocode/agents/docs.md`.

---

## PHASE 5: WRITE CTO MEMORY

Write `.autocode/agents/cto.md`:

```markdown
---
agent: cto
last-updated: [today's date]
meets: 1
---
# CTO Memory — [project name]

## Strategic Priorities
[Max's stated priorities from OWNER_ANSWERS — ordered by what he said]

## Team Health

### Agent Performance
| Agent | Runs | Audit Reject Rate | Known Blind Spots | Last Updated |
|-------|------|-------------------|-------------------|--------------|
| security | 1 | — | none recorded yet | [today] |
| architect | 1 | — | none recorded yet | [today] |
| qa | 1 | — | none recorded yet | [today] |
| docs | 1 | — | none recorded yet | [today] |

### Quality Trends
No data yet — run /autocode tasks to build history.

## Open Escalations
[any items from Phase 3 Escalation Queue]

## Conflict Register
None yet.

## Task Cycle Log

[Populated by /task after each audit cycle.]
```

---

## PHASE 6: HANDOFF BRIEFING

Print:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  /meet COMPLETE — Team is onboarded
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Architecture:  [N] findings ([N] critical)
  Security:      [N] findings ([N] critical)
  QA:            [N] test gaps, [N] pseudocode tests
  Documentation: [N] doc gaps

  Task list:     [N] tasks across [N] batches
  Batch 1:       [N] tasks — [theme] [CURRENT SPRINT]

  Agent memories written:
    .autocode/agents/architect.md
    .autocode/agents/security.md
    .autocode/agents/qa.md
    .autocode/agents/docs.md
    .autocode/agents/cto.md

  Suggested first command:
    /task #001

  Other commands:
    /resume        — quick session-start (reads memory, no scans)
    /tasks         — view full task list
    /team-health   — CTO dashboard
    /consult [role] — ask a single agent directly
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## RULES

- Never skip Phase 2 (questions to Max) — the task list must reflect his priorities, not guessed ones
- Questions in Phase 2 must cite specific findings — never ask generic questions
- Agent memories must be written even if findings are empty — a memory saying "run 1, no issues found" is still useful
- Never reuse task numbers — if carrying forward existing tasks, renumber sequentially from 001
- EXISTING_TASKS must be read and carried forward — never discard prior open work
- Run /meet again after a significant feature ships to update the task list and agent memories
- If invoked with a module argument ($ARGUMENTS), scope all examination agents to that module only
