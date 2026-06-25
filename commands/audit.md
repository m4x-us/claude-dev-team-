# Audit — Independent Review Team

You are running an independent code review. The task is: $ARGUMENTS

Review the full scope of everything built for this task — not just the most recent fixes. This command does NOT write code. It finds problems and emits a verdict.

---

## PHASE 0: SETUP

Before starting, run in the orchestrating session:

```
mkdir -p .autocode
```

**Invocation mode detection:**
If $ARGUMENTS contains `TASK_DEFINITION:`, extract:
- `TASK_DEFINITION` — the task text
- `FULL_DIFF_OVERRIDE` — specific diff range from /task (use this instead of auto-detecting)
- `CYCLE_HISTORY` — prior cycle log from cto.md (or "None")
- `DONE_WHEN_FINDING` — if present, inject as a severity-6 finding into Agent C (Done When verification failed)
Set `MODE = "orchestrated"`

In standalone mode (no `TASK_DEFINITION:` prefix): `CYCLE_HISTORY = "None"`. Set `MODE = "standalone"`.

Read `~/.claude/autocode/philosophy.md` in full. Capture the entire contents as `PROJECT_PHILOSOPHY`. This is the standard every audit agent will work against. If the file doesn't exist, print a warning and continue — but note that agents will be working without the philosophy standard.

Extract primary terms from $ARGUMENTS (nouns, verbs, domain concepts — e.g. "audit SMS inbound flow" → terms: sms, inbound, flow).

Read `.autocode/reflections.md`. Search for entries whose task description contains any of the extracted terms. Take the 2 most recent matching entries verbatim. Capture as `REFLECTION_LOG`. If no matches found or file doesn't exist: `REFLECTION_LOG = "None yet."`

Read `.autocode/agents/security.md` → `MEMORY_SECURITY` (or "None").
Read `.autocode/agents/architect.md` → `MEMORY_ARCHITECT` (or "None").
Read `.autocode/agents/qa.md` → `MEMORY_QA` (or "None").
Read `.autocode/agents/cto.md` → `CTO_MEMORY` (or "None").
Extract known blind spots per agent from CTO_MEMORY as `CTO_INTELLIGENCE`.

**Step A — FULL_DIFF (history-aware diff)**

Run: `git log --oneline -10`

Check each commit message for terms matching $ARGUMENTS.
- If 1+ commits match: note the commit hash immediately BEFORE the first matching commit.
  Run: `git diff [that-hash]..HEAD`
  Note in context: "Diff spans N commits back to [hash]."
- If no commits match OR no `.git` directory exists:
  Run: `git diff HEAD` (uncommitted changes)
  If that is empty: `git diff HEAD~1` (last commit's changes)

Capture result as `FULL_DIFF`.

**Step B — TASK_SCOPE (full file contents)**

If `FULL_DIFF_OVERRIDE` is set (orchestrated mode): use that diff range instead of auto-detecting.

Run: `git diff [FULL_DIFF range] --name-only`

If `TASK_DEFINITION` includes a `File:` field, always include those files in TASK_SCOPE regardless of whether they appear in the diff. These are the task-anchored files.

Filter out: `node_modules/`, `.git/`, `dist/`, `build/`, `*.min.js`, `*.d.ts`, `*.map`

Cap at 10 files. If more than 10: prioritize task-anchored files first → files named after task terms → files with most changed lines.

For each file:
- ≤300 lines: read in full
- >300 lines: read first 200 lines + last 50 lines. Insert at the break point: `[FILE TRUNCATED — N total lines. Showing first 200 + last 50.]`

Capture as:
```
TASK_SCOPE:
=== [filepath] (N lines[, TRUNCATED]) ===
[contents]
=== [filepath] ===
[contents]
[...repeat...]
```

If FULL_DIFF is empty and no files are identified: `TASK_SCOPE = "No changed files detected."`

**Step C — CALLER_CONTEXT (files that call into the changed code)**

For each changed file: extract the basename without extension (e.g., `sms-sender` from `apps/worker/src/sms-sender.ts`).

Run for each basename:
```
grep -r "from '.*[basename]'" --include="*.ts" --include="*.tsx" -l .
grep -r "require.*[basename]" --include="*.ts" --include="*.tsx" -l .
```

Exclude from results: `node_modules/`, `.git/`, `.autocode/`, the changed file itself. Take the 3 closest results per file (prefer same directory, then parent, then sibling directories).

Deduplicate across all changed files. Cap total at 10 caller files. For each caller file: read the first 100 lines only.

If no callers found: `CALLER_CONTEXT = "No direct callers identified in codebase."`

Capture as:
```
CALLER_CONTEXT:
=== [filepath] (caller of [changed-file]) ===
[first 100 lines]
[...repeat...]
```

Do not spawn any audit agent until FULL_DIFF, TASK_SCOPE, and CALLER_CONTEXT are all captured.

---

## PHASE 1: AUDIT LOOP

Run up to 5 audit cycles. Use a different lens each cycle (rotate 1 → 2 → 3 → 1 → 2).

Each audit cycle uses three independent agents: Agent A and Agent B audit independently, Agent C merges and scores from scratch.

**Audit Lens 1:**
"Where did we cut corners? What's not world-class? What's not enterprise-grade? Are our tests pseudocode or real? Are we testing the right things?"

**Audit Lens 2:**
"Fresh eyes. What's not world-class? What's not enterprise-grade? Where's the pseudocode? Where are the flaws? What are our vulnerabilities?"

**Audit Lens 3:**
"Step back and truly understand the purpose of what we built. What's not world-class? What's not enterprise-grade? Find the vulnerabilities and security flaws."

**Audit Agent A**

Spawn an independent agent with this prompt:

"You are an independent code auditor. Review the following code changes for this task: $ARGUMENTS

SLOW-CODING TOYOTA SYSTEM PHILOSOPHY — This is the standard you are auditing against. Every rule is mandatory:
[PROJECT_PHILOSOPHY]

TASK SCOPE — Full current state of every file this task touched. Audit the complete result, not just the delta:
[TASK_SCOPE]

CODE DIFF — What specifically changed (use this to understand intent and the boundary of the change):
[FULL_DIFF]

CALLER CONTEXT — Files that import or call into the changed code. Not changed themselves, but may be affected:
[CALLER_CONTEXT]

PRIOR CYCLE HISTORY — What was attempted in previous cycles on this exact task:
[CYCLE_HISTORY — or "None — first cycle / standalone invocation"]

If CYCLE_HISTORY is not "None": for each finding from a prior cycle, do NOT check only whether code exists in the area. Trace the specific root cause named in the finding and verify it was resolved at that root cause level. A new catch block does not fix a missing auth check. A new test file does not fix pseudocode assertions. A route-level change does not fix a middleware-layer problem. For any prior-cycle finding: call it REPEATED unless you can cite the specific line that addresses the root cause — not the symptom.

[Current audit lens]

List every problem you find. Do not score — just find and describe every issue. Call out any violation of the philosophy above explicitly."

Capture Agent A's findings.

**Audit Agent B**

Spawn a second independent agent with this prompt:

"You are an independent code auditor. Review the following code changes for this task: $ARGUMENTS

SLOW-CODING TOYOTA SYSTEM PHILOSOPHY — This is the standard you are auditing against. Every rule is mandatory:
[PROJECT_PHILOSOPHY]

TASK SCOPE — Full current state of every file this task touched. Audit the complete result, not just the delta:
[TASK_SCOPE]

CODE DIFF — What specifically changed (use this to understand intent and the boundary of the change):
[FULL_DIFF]

CALLER CONTEXT — Files that import or call into the changed code. Not changed themselves, but may be affected:
[CALLER_CONTEXT]

PRIOR CYCLE HISTORY — What was attempted in previous cycles on this exact task:
[CYCLE_HISTORY — or "None — first cycle / standalone invocation"]

If CYCLE_HISTORY is not "None": for each finding from a prior cycle, do NOT check only whether code exists in the area. Trace the specific root cause named in the finding and verify it was resolved at that root cause level. A new catch block does not fix a missing auth check. A new test file does not fix pseudocode assertions. A route-level change does not fix a middleware-layer problem. For any prior-cycle finding: call it REPEATED unless you can cite the specific line that addresses the root cause — not the symptom.

[Current audit lens]

List every problem you find. Do not score — just find and describe every issue. Call out any violation of the philosophy above explicitly."

Capture Agent B's findings.

**Security Agent S**

Spawn a third independent agent with this prompt:

"You are a dedicated security auditor. You do NOT review code quality, architecture,
or test coverage — other agents handle those. Your ONLY job: find security flaws.

Task: $ARGUMENTS

SLOW-CODING TOYOTA SYSTEM PHILOSOPHY:
[PROJECT_PHILOSOPHY]

TASK SCOPE:
[TASK_SCOPE]

CODE DIFF:
[FULL_DIFF]

CALLER CONTEXT:
[CALLER_CONTEXT]

SECURITY AGENT MEMORY — Your accumulated knowledge of this codebase from prior runs. Read this before reviewing — do not re-discover what you already know:
[MEMORY_SECURITY]

PRIOR SECURITY FINDINGS FROM CYCLE HISTORY — if any security-category findings appeared in prior cycles, listed here. Do not let these recur without explicit root-cause evidence they were fixed:
[Any security-category findings from CYCLE_HISTORY, or 'None — first cycle / standalone']

KNOWN BLIND SPOTS — Categories you have historically missed. For each: explicitly state CHECKED or FINDING. You are FORBIDDEN from silently skipping these:
[Extract Security Agent row from CTO_INTELLIGENCE — or 'No blind spots recorded yet']

TOYOTA EVIDENCE RULE: For every checklist item below, you must produce ONE of these outputs:
  VERIFIED: [file:line-range] — [what you see in the code that handles this]
  FINDING: [description of the vulnerability]
  N/A: [why this checklist item doesn't apply to this specific task]

You are FORBIDDEN from writing:
  - 'No issues found' without citing specific code
  - 'Appears to be secure'
  - 'Not applicable' without explaining why
  - Skipping any checklist item

If you cannot find the code that handles a checklist item, that is a FINDING,
not a VERIFIED. Absence of evidence is not evidence of absence.

---

CHECKLIST — review every item, no exceptions:

AUTH:
[ ] Every route that reads user data: authentication checked?
    → Cite the auth middleware or guard function and where it's applied
[ ] Every route that writes or deletes: authorization checked (role/ownership), not just authentication?
    → Cite the authorization check and what it verifies
[ ] Multi-tenant isolation: can org A's session access org B's data?
    → Cite where tenant context is enforced in query scope
[ ] Role escalation: can a clothier-role perform admin actions on these routes?
    → Cite where role is checked

INPUT/OUTPUT:
[ ] Every user-controlled input: validated before use?
    → Cite the validation function and what schema it applies
[ ] HTML output: user strings escaped or sanitized?
    → Cite the sanitization mechanism (not just 'React does it by default' — show it's not bypassed)
[ ] SQL injection: no raw query string interpolation?
    → Cite any database calls that take user input and confirm they use parameterized queries
[ ] Path traversal / command injection: no user input in file paths or exec calls?
    → Cite or confirm N/A

SECRETS AND DATA:
[ ] Secrets or tokens: logged anywhere? Returned in API response?
    → Cite the response shape or confirm no secret field is included
[ ] Client data enumeration: can user see IDs/emails/phones of OTHER clients?
    → Cite how queries are scoped to the authenticated user's data
[ ] Error messages: do they expose internal paths, stack traces, or DB schema to end users?
    → Cite the error response shape

EXTERNAL INTEGRATIONS (if this task touches webhooks, external APIs, or Twilio/GoCreate):
[ ] Webhook signatures validated before trusting payload?
    → Cite the signature check
[ ] Outbound API calls rate-limited or guarded?
    → Cite the guard or confirm N/A
[ ] User-controlled URLs fetched by server (SSRF)?
    → Cite or confirm N/A"

Capture Agent S's findings.

**Spawn Red Agent R — Adversarial Reviewer (unprimed, diff-only):**

Red Agent R receives NO philosophy, NO cycle history, NO caller context. Priming is
deliberately withheld. R catches what A, B, and S pattern-matched past.

Spawn an independent agent with this prompt:

"You are a hostile code reviewer. You have NOT been briefed on project rules, philosophy,
or history. You see only what changed.

RAW DIFF:
[FULL_DIFF]

Three lenses. Review each independently.

ATTACKER: How would a malicious actor exploit this exact change?
- New parameters that bypass existing guards?
- New auth paths that can be circumvented?
- New data returned that should be private?
For each: state the exact file:function:line and the attack vector.

CHAOS: How does this exact change fail under bad conditions?
- What if this runs 100x concurrently?
- What if a required field is null/undefined at the line you added?
- What if an external call times out mid-execution here?
- What if this is called twice in rapid succession?
For each: state the exact file:function:line and the failure mode.

DECAY: What does this exact change make worse over time?
- Does this duplicate logic that exists elsewhere?
- Does this hardcode something that will be wrong in 6 months?
- Does this create a hidden coupling that will surprise the next developer?
For each: state the exact file:function:line and the long-term cost.

Output format — one line per finding, no hedging:
FINDING: [ATTACKER|CHAOS|DECAY] | [file:function:line] | [precise description — no 'appears to', 'likely', 'may', 'should']

If you find nothing in a lens:
FINDING: [LENS] | NONE | no issues found in this lens"

**Convert Red Agent R output to FINDINGS_JSON (FINDINGS_R):**
Parse each `FINDING:` line from R's output. For each non-NONE line:
- Lens ATTACKER → category: "security"
- Lens CHAOS → category: "error-handling"
- Lens DECAY → category: "code-quality"
- Severity: default 6 — this is a placeholder pending Agent C's final score
- Extract the middle pipe-segment as file:function:line (split on `:`, last element is line number)
- Set `severity_note`: "Red Agent R — unscored, pending Agent C"
- Set `annotation`: "NEW"

Build FINDINGS_R as a FINDINGS_JSON-compatible array:
[{"id":"R001","severity":6,"category":"[derived]","file":"[file]","function":"[fn]","line":N,"description":"[text]","annotation":"NEW","severity_note":"Red Agent R — unscored, pending Agent C"}]

If R output has all NONE lines: FINDINGS_R = [].

**Conflict Detection (before spawning Agent C):**

Before merging, scan Agent A's findings and Agent B's findings for direct contradictions: where both agents examined the same file and function but reached opposite verdicts (one says compliant, one says violation). If any contradiction is found, spawn a conflict resolution agent FIRST:

"You are an arbitration agent. Two code reviewers disagree on the same code.

PHILOSOPHY (the binding authority):
[PROJECT_PHILOSOPHY]

Agent A finding: [contradicting finding with file:line]
Agent B finding: [contradicting finding on same code]

Step 1: Is this a genuine conflict (two valid interpretations) or a mistake (one is factually wrong)?
  - If one is factually wrong: identify which one and explain why. Adopt the correct finding.
  - If genuine conflict: proceed to Step 2.

Step 2: Apply the philosophy. Which interpretation is more consistent with the relevant Rule (cite Rule #), the Prime Directive (built to last 10 years), and production risk?

Step 3: Produce a binding decision:
  CONFLICT RESOLVED: [finding A / finding B / new synthesis]
  RATIONALE: [cite specific Rule # and code evidence]
  SEVERITY: [1-10]

You are FORBIDDEN from:
  - 'Both agents make valid points' without resolving
  - Deferring without a decision
  - Splitting the difference to avoid controversy"

Replace the contradicting findings in the merged list with the resolved finding. Then proceed to Agent C.

**Audit Agent C — Merge and Score**

Spawn a fifth independent agent with this prompt:

"You are a senior code quality judge. Four independent auditors have reviewed the same code and produced the following findings. Your job is to merge them into one master list and score the overall result from scratch.

SLOW-CODING TOYOTA SYSTEM PHILOSOPHY — This is the standard you are scoring against. Every rule is mandatory:
[PROJECT_PHILOSOPHY]

Auditor A findings:
[Agent A's findings — with any conflict-resolved findings already replaced]

Auditor B findings:
[Agent B's findings — with any conflict-resolved findings already replaced]

Security Auditor S findings:
[Agent S's findings]

Red Adversarial Auditor R findings (unprimed — diff only, no philosophy or history):
[FINDINGS_R]

DONE_WHEN FINDING (if any — inject as severity-6 item):
[DONE_WHEN_FINDING or 'None']

CYCLE HISTORY (if provided):
[CYCLE_HISTORY — or 'None — standalone invocation']

Task: $ARGUMENTS

ANTI-RATIONALIZATION RULES — These are MANDATORY. Violating any of these is grounds for the entire output being rejected:
1. FORBIDDEN from using hedging language: 'appears to / likely / may / should' — every finding must cite file:function:line or it is removed from the list entirely.
2. FORBIDDEN from reducing a finding's severity below its first-cycle score unless you can cite specific code evidence that the root cause (not just the symptom) was fixed. If you reduce a severity, annotate: [SEVERITY_REDUCTION: N→M, root cause evidence: file:line].
3. FORBIDDEN from describing a philosophy violation without citing the specific Rule #. 'This is not best practice' is not a finding. 'Violates Rule 8 — no error ref ID at apps/web/src/api/orders/route.ts:47' is a finding.
4. FORBIDDEN from marking a 'REPEATED FROM CYCLE N' finding as resolved unless you can cite the specific commit or line that addressed the root cause from the TARGETED_GUIDANCE.
5. For findings from Red Agent R (severity_note "Red Agent R — unscored, pending Agent C"): re-score these based on your full analysis. The default severity 6 is a placeholder, not a judgment. Under-scoring a CHAOS or ATTACKER finding because it "probably won't happen" is Severity Rationalization and will be rejected.
6. FORBIDDEN from using TASK_DEFINITION, task intent, or task scope to rationalize a severity reduction. Whether a finding was "expected" given what the task was trying to do is irrelevant. The standard is the philosophy rubric — not the task's goal. A missing auth check is severity 8 whether or not this task was about auth.

CYCLE ANNOTATIONS — if CYCLE_HISTORY is present, annotate every finding with one of:
- NEW — not seen in prior cycles
- REPEATED FROM CYCLE N — appeared in a previous cycle (cite the cycle number)
- ESCALATE — appeared in 3 or more consecutive cycles (triggers CTO escalation)

Merge all findings — do not drop anything. Then score the combined picture using this rubric:

| Score | Level | What it means |
|-------|-------|---------------|
| 1 | Trivial | Style, formatting, naming preference |
| 2 | Trivial | Minor cleanup, unnecessary code, small DRY violation, confusing comments |
| 3 | Low | Non-critical missing edge case, slightly confusing logic |
| 4 | Low | Missing tests for unlikely scenarios, minor performance issue |
| 5 | Medium | Incomplete error handling, fragile logic that works but could break |
| 6 | Medium | Pseudocode tests, missing feature flag, inconsistent behavior |
| 7 | High | Bug affecting real users, race condition, data could be silently lost |
| 8 | Critical | Missing auth check, security vulnerability, data loss in normal use |
| 9 | Severe | Auth bypass, data corruption, system could go down |
| 10 | Catastrophic | Mass data loss, complete security breach |

- `critical`: count of issues scoring 7 or above
- `major`: count of issues scoring 5–6
- `minor`: count of issues scoring 1–4
- `verdict`: PASS only if severity ≤ 3 AND critical = 0

Output findings in this EXACT schema — no prose findings list. Structured data only.

FINDINGS_JSON:
[
  {
    "id": "F001",
    "severity": N,
    "category": "[one of: error-handling|tests|auth|security|data-loss|feature-flag|async|edge-case|code-quality|performance|requirements]",
    "file": "[filepath — required. Use 'unknown' ONLY if the finding is an architectural gap with no single file owner, not as a shortcut]",
    "function": "[function or method name — required. Use 'module-level' for top-level code outside any function]",
    "line": N,
    "description": "[precise description of the defect — FORBIDDEN: 'appears to / likely / may / should / probably / seems'. FORBIDDEN: pipe character |. Philosophy violations MUST cite 'Rule N:']",
    "annotation": "[NEW | REPEATED FROM CYCLE N | ESCALATE]",
    "severity_note": "[OMIT this field entirely unless severity was reduced from a prior cycle. If reduced: SEVERITY_REDUCTION: N→M, root cause evidence: file:function:line]"
  }
]

Rules for FINDINGS_JSON output:
1. Sequential ids: F001, F002, F003... No gaps, no duplicates.
2. `file` and `function` may NOT both be 'unknown' — if you do not know the location, that is a finding about missing observability.
3. `severity_note` must be OMITTED (not null, not empty string) unless severity was reduced from a prior-cycle score.
4. Philosophy violation descriptions MUST cite the Rule # — format: 'Violates Rule N: [what the rule requires] at file:function:line'.
5. Descriptions must NOT contain pipe characters (|) — use semicolons instead.
6. Produce the complete array — do not truncate.

Then, if you detected cross-cutting architectural patterns spanning 2+ findings (not just individual bugs), produce:
SYNTHESIS_PATTERNS: [{"id":"SP001","category":"[same category vocab as FINDINGS_JSON]","severity":[1-10 — the systemic risk level],"description":"[one precise sentence — the architectural observation, not a restatement of any single finding]","evidence_findings":["F001","F002",...]}]

Rules for SYNTHESIS_PATTERNS:
- `evidence_findings` MUST contain ≥2 finding IDs from this cycle's FINDINGS_JSON. No fabricated IDs.
- `description` must name the systemic pattern, not restate individual findings. "Three auth boundary functions share a root: caller identity is never validated before returning sensitive data" is correct. "Multiple security issues found" is not.
- `severity` is the systemic risk — may be higher than any single finding's severity.
- `id` uses SP prefix: SP001, SP002, ...
- OMIT the SYNTHESIS_PATTERNS line entirely if you see no cross-cutting patterns. Do NOT emit an empty array.
- SYNTHESIS_PATTERNS does NOT affect the AUDIT_RESULT verdict — it is architectural intelligence only.

Then this line exactly:
AUDIT_RESULT: {\"severity\":N,\"critical\":N,\"major\":N,\"minor\":N,\"verdict\":\"PASS or FAIL\",\"escalate\":true/false,\"findings_count\":N}"

(Set `escalate: true` if any finding is annotated ESCALATE. Set `findings_count` to the array length.)

Capture Agent C's master findings list and AUDIT_RESULT.

**Agent C Output Validation (machine-enforced where available, prose-fallback otherwise):**

Extract FINDINGS_JSON from Agent C's output (the JSON array between `FINDINGS_JSON:` and the `AUDIT_RESULT:` line).

**If `scripts/validate-findings.sh` exists** (project has machine enforcement):

Write FINDINGS_JSON to `/tmp/findings_validate_$$.json`, then run:
```
bash scripts/validate-findings.sh "$(cat /tmp/findings_validate_$$.json)"
```

- Exit code 0: FINDINGS_JSON is valid. Proceed.
- Exit code 1: Capture all `SCHEMA_ERROR:` lines as VALIDATION_ERRORS. Do NOT proceed to patterns.md logging.

**If `scripts/validate-findings.sh` does NOT exist** (different project, graceful fallback):

Perform prose scan manually:
1. Check each description for hedging words: "appears to / likely / may / should be / probably / seems to / might"
2. Check each description that mentions a philosophy concept for a "Rule N:" citation
3. Check for pipe characters (|) in any description
4. Capture any violations found as VALIDATION_ERRORS.

**If VALIDATION_ERRORS is non-empty (from either path above):**

Re-spawn Agent C with this exact re-request prompt:

"Your FINDINGS_JSON output was REJECTED. Fix every error below and re-produce the complete FINDINGS_JSON array.

VALIDATION_ERRORS:
[VALIDATION_ERRORS — one per line]

SCHEMA RULES — non-negotiable:
1. Every finding must have id, severity (1-10), category (from allowed list), file, function, line, description, annotation.
2. description FORBIDDEN from: hedging words (appears to / likely / may / should be / probably / seems) — cite specific code behavior instead.
3. description for a philosophy violation MUST cite 'Rule N:' — 'This is not best practice' is FORBIDDEN.
4. description MUST NOT contain pipe characters (|) — use semicolons (;) instead.
5. severity_note field must be OMITTED unless severity was reduced from a prior cycle.
6. Both file AND function cannot be 'unknown' on the same finding.
7. This is your ONE re-request. If re-submitted FINDINGS_JSON still fails validation, this cycle is marked MAX_CYCLES with trigger: AUDIT_QUALITY_FAILURE."

Run validation again on re-submitted output (script if available, prose scan if not).
- Valid: proceed as if original output.
- Still invalid: set verdict = "MAX_CYCLES". Escalation brief: "AUDIT_QUALITY_FAILURE — Agent C produced invalid FINDINGS_JSON twice in this cycle." Emit AUDIT_RESULT_FINAL with verdict MAX_CYCLES. Stop.

**After Agent C Output Validation passes, log findings to `.autocode/patterns.md`:**

Iterate over FINDINGS_JSON. For each finding where `finding.severity >= 4`:

Append to `.autocode/patterns.md`:
```
## [today's date] | Task: $ARGUMENTS
- [finding.category] [finding.description] — severity [finding.severity] | [finding.file]:[finding.function]:[finding.line] | [finding.annotation]
```

If `.autocode/patterns.md` does not exist, create it with `# AutoCode Patterns Log` header first.

Note: Agent C no longer produces a prose findings list — only FINDINGS_JSON. Always read category, description, severity, and location from the structured array, never from a narrative text block.

**Also log SYNTHESIS_PATTERNS entries (if Agent C produced them):**

If Agent C produced a `SYNTHESIS_PATTERNS:` line, attempt to parse the JSON array. If JSON is malformed (parse error): print a warning and skip SYNTHESIS logging — do NOT abort the audit cycle. For each entry in SYNTHESIS_PATTERNS, append to `.autocode/patterns.md` under the same `## [date] | Task: $ARGUMENTS` header (plain bullet, no code fence):

    - [sp.category] [sp.description] — severity [sp.severity] | CROSS-CUTTING | SYNTHESIS

If `.autocode/patterns.md` does not exist, create it with `# AutoCode Patterns Log` header first (same condition as FINDINGS_JSON logging — if both create, only one header is written).

SYNTHESIS entries count toward the graduation threshold in `check-patterns-threshold.sh` identically to individual findings — same category grouping, same severity math. The `| SYNTHESIS` annotation is for human readability only.

---

## AUDIT DECISION LOGIC

**After capturing Agent C's output, log findings to `.autocode/patterns.md` (already logged above — do not double-log).**

**If verdict = FAIL:**

Append to `.autocode/trends.md`:
```
| [today's date] | [first 60 chars of $ARGUMENTS] | [N cycles] | [final severity] | FAIL |
```

Emit and stop:
```
AUDIT_RESULT_FINAL: {"verdict":"FAIL","findings":[...FINDINGS_JSON array verbatim from Agent C output...],"cycles_run":N,"escalate":[true/false]}
```

If `MODE = "orchestrated"`: stop here. /task handles the fix cycle and retry.
If `MODE = "standalone"`:
  Print the findings list.
  If $ARGUMENTS contains a task number (matches `#\d+` or a bare integer):
    Extract TASK_NUM (e.g. "#001" → 1 → zero-padded to match tasks.md format).
    Print:
    ```
    ─────────────────────────────────────────────────────────────
      Found [findings_count] issues ([critical] critical, [major] major, [minor] minor).
      Send to the dev team to fix?

        yes → /task #[TASK_NUM] starts a fix cycle now
        no  → stop here, review findings above first
    ─────────────────────────────────────────────────────────────
    ```
    Wait for user input.
    If yes: run `/task #[TASK_NUM]`. Stop.
    If no: stop.
  If no task number detected in $ARGUMENTS: stop.

**If verdict = PASS:**
Append to `.autocode/trends.md`:
```
| [today's date] | [first 60 chars of $ARGUMENTS] | [N cycles] | [final severity] | PASS |
```
If `.autocode/trends.md` does not exist, create it with this header first:
```
# AutoCode Severity Trends
| Date | Task | Cycles | Final Severity | Verdict |
|------|------|--------|---------------|---------|
```

```
AUDIT_RESULT_FINAL: {"verdict":"PASS","findings":[...FINDINGS_JSON array verbatim from Agent C output...],"cycles_run":N,"escalate":false}
```

If `MODE = "standalone"`: print `✅ Audit passed.` then run `/worldclass $ARGUMENTS`.
If `MODE = "orchestrated"`: print `✅ Audit passed.` and stop. /task handles /worldclass.

**If 5 cycles are reached without PASS:**
Append to `.autocode/trends.md`:
```
| [today's date] | [first 60 chars of $ARGUMENTS] | 5 | [final severity] | MAX_CYCLES |
```

```
AUDIT_RESULT_FINAL: {"verdict":"MAX_CYCLES","findings":[...FINDINGS_JSON array verbatim from Agent C output...],"cycles_run":5,"escalate":true}
```

Print:
```
⚠️ Max cycles reached without a clean audit.
Outstanding issues:
[list them]
```

If `MODE = "standalone"`: run `/reflect $ARGUMENTS`. Then proceed to POST-AUDIT REORDER below.
If `MODE = "orchestrated"`: stop here. /task handles escalation.

---

## POST-AUDIT: Task List Reorder (standalone mode only)

After every standalone audit — regardless of verdict — the CTO re-evaluates the task order now that new findings are known.

Read all non-COMPLETE tasks from `.autocode/tasks.md`.

Apply the same priority logic as Step 4.4 in `/task`:

**Elevation triggers** (move task to an earlier batch):
- A finding from this audit directly implicates the file or module a task addresses → move that task up
- Any finding with severity ≥ 7 in a category (security, error-handling) → elevate tasks of that same category
- A finding is marked ESCALATE → elevate all tasks touching that file

**Demotion triggers** (move task to a later batch):
- A module the audit found completely clean → tasks touching only that module can move later
- Task has severity ≤ 3, blocks nothing, and no audit finding implicates it → move later

**Hard constraint:** Never move a task before any task it is "Blocked by."

Update `.autocode/tasks.md` if any tasks moved. Add a one-line note on each moved task:
`**Moved:** Batch [from] → Batch [to] — [finding that triggered the move] — [today's date]`

Print only if something moved:
```
─────────────────────────────────────────────────────────────
  PRIORITY REORDER — [N] task(s) moved after audit
  Task #NNN: Batch X → Batch Y — [reason]
─────────────────────────────────────────────────────────────
```

If nothing moved: silent.

---

## RULES

- FORBIDDEN from writing code
- FORBIDDEN from spawning planning agents
- FORBIDDEN from calling /worldclass in orchestrated mode
- FORBIDDEN from calling /reflect in orchestrated mode
- Always emit AUDIT_RESULT_FINAL before stopping
- Agent C scores the full combined picture — never drop findings from any auditor (A, B, S, or R)
- All agents except Red Agent R receive PROJECT_PHILOSOPHY — Red Agent R is intentionally unprimed (diff-only) to catch what primed reviewers pattern-match past
- Never spawn audit agents without TASK_SCOPE and CALLER_CONTEXT captured — full file context is mandatory
- Agent C ANTI-RATIONALIZATION RULES are mandatory — output that uses hedging language or omits file:line citations is invalid and must be re-requested
