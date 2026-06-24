# Patterns — Audit Pattern Analysis

Read `.autocode/patterns.md` in the current project and analyze recurring findings to suggest improvements to the plan prompts.

---

## STEP 1: READ THE DATA

Read `.autocode/patterns.md`. If it doesn't exist or is empty, print:
"No pattern data yet. Run /autocode on a few tasks first."
Then stop.

---

## STEP 2: PRINT THE RAW DATA

Print the full contents of `.autocode/patterns.md` so the user can see everything that has been logged.

---

## STEP 3: ANALYZE PATTERNS

Group all findings by category. For each category, count:
- How many times it appeared
- Which tasks it appeared in
- The severity range (lowest to highest)

Print a summary table like this:

```
PATTERN SUMMARY
───────────────────────────────────────────────────────
Category          | Occurrences | Tasks                | Severity Range
error-handling    | 6           | #103, #104, #106     | 5–8
tests             | 4           | #103, #105, #106     | 5–7
auth              | 2           | #104, #107           | 8–8
───────────────────────────────────────────────────────
```

Highlight any category that has appeared in 3 or more tasks — these are systemic patterns, not one-off mistakes.

---

## STEP 4: INTELLIGENT RECOMMENDATIONS

For each systemic pattern (3+ occurrences), produce a specific recommendation:

1. **Explain the pattern** — what keeps going wrong and why it likely keeps happening
2. **Suggest specific language** to add to the initial plan prompt that would catch this before code gets written
3. **Suggest a checklist item** Agent 4 (the final revision) should always verify before accepting the plan

Format each recommendation like this:

```
PATTERN: error-handling (6 occurrences across #103, #104, #106)
─────────────────────────────────────────────────────────────────
What keeps going wrong:
[explanation]

Suggested addition to the Initial Plan prompt:
"[specific language to add]"

Suggested checklist item for Revision 3:
"[specific verification question]"
```

Be specific. Vague recommendations like "handle errors better" are not useful.
Good recommendations name the exact scenario, function type, or pattern that keeps failing.

---

## STEP 5: OVERALL HEALTH SCORE

Print a simple health score based on the data:

- 0–2 systemic patterns: 🟢 Healthy — your plan prompts are catching most issues
- 3–4 systemic patterns: 🟡 Needs attention — refine your prompts in the areas above
- 5+ systemic patterns: 🔴 Significant drift — your plan prompts need a major revision

---

## STEP 6: ARCHIVE COMPARISON (if archives exist)

Check if any `.autocode/patterns-archive-*.md` files exist.

If they do, scan them for categories that also appear in the current batch. For each match, print:

```
⚠️ RECURRING PATTERN: error-handling
   Also appeared in: patterns-archive-2026-06-23.md
   This pattern survived a prompt update — needs stronger guardrails.
```

This tells you immediately if a fix you made after the last batch didn't actually hold.

If no archives exist, skip this step.

---

## STEP 7: SEVERITY TREND ANALYSIS

**Audit severity (trends.md):**

Read `.autocode/trends.md`. If it doesn't exist or has fewer than 3 data rows, print:
"Not enough audit trend data yet. Need at least 3 completed runs."
Then skip the audit trend section.

If it has 3 or more rows:

1. Print the last 10 rows of the trends table so individual data points are visible — do not hide them behind averages.

2. Flag any run with Final Severity ≥ 7:
```
⚠️ High-severity outlier: [date] — [task] — severity [N]
```

3. For trend direction — requires 6+ rows. Compare average severity of the most recent 3 runs vs the 3 before that:
   - If fewer than 6 rows: print "Need 6+ runs for trend direction. Showing individual data points above."
   - If recent 3 avg is lower by >0.5: IMPROVING 🟢 — severity is trending down
   - If recent 3 avg is higher by >0.5: DEGRADING 🔴 — severity is trending up. Cross-reference with pattern summary above.
   - Otherwise: STABLE 🟡 — no significant change

Print the verdict clearly:
```
AUDIT TREND: IMPROVING / STABLE / DEGRADING
Recent 3 avg: X.X | Prior 3 avg: X.X
```

**WorldClass scores (worldclass-trends.md):**

Read `.autocode/worldclass-trends.md`. If it doesn't exist or has fewer than 3 data rows, print:
"Not enough WorldClass data yet. Need at least 3 completed runs."
Then skip the worldclass trend section.

If it has 3 or more rows:

1. Print the last 10 rows of the worldclass trends table.

2. Flag any run with Final Score ≤ 80:
```
⚠️ Low-quality outlier: [date] — [task] — score [N]/100
```

3. For trend direction — requires 6+ rows. Compare average score of the most recent 3 runs vs the 3 before that. For worldclass, higher is better (opposite of audit severity):
   - If fewer than 6 rows: print "Need 6+ runs for trend direction. Showing individual data points above."
   - If recent 3 avg is higher by >2: IMPROVING 🟢 — quality is trending up
   - If recent 3 avg is lower by >2: DEGRADING 🔴 — quality is trending down
   - Otherwise: STABLE 🟡 — no significant change

Print the verdict clearly:
```
WORLDCLASS TREND: IMPROVING / STABLE / DEGRADING
Recent 3 avg: X.X | Prior 3 avg: X.X
```

---

## STEP 8: ARCHIVE PROMPT

After printing everything, ask:

"Archive this batch and start fresh? (y/n)"

**If yes:**
1. Rename `.autocode/patterns.md` to `.autocode/patterns-archive-[today's date].md`
2. Create a fresh empty `.autocode/patterns.md` with just the header:
   ```
   # AutoCode Patterns Log
   ```
3. Print: "✅ Batch archived to patterns-archive-[date].md. Starting fresh."

**If no:**
Print: "Keeping current data. Run /patterns again after your next 5 tasks."

Note: trends.md and reflections.md are NOT archived — they are permanent longitudinal records.

---

## STEP 9: REFLECTIONS SUMMARY

Read `.autocode/reflections.md`. If it doesn't exist, print:
"No reflections yet. Complete a task with /autocode to generate the first one."
Then stop.

If it exists:

1. Count total logged reflections.

2. If 3 or more reflections exist, scan all paragraphs for recurring themes:
   - Plan assumptions that kept being wrong
   - Categories of surprise (things the audit caught that the plan didn't anticipate)
   - Patterns in what caused the most rework

   For each theme appearing in 2+ reflections, print:
   ```
   🔍 RECURRING INSIGHT: [theme description]
      Appeared in [N] reflections — systemic blind spot in the planning process
   ```

3. If fewer than 3 reflections: print "Need 3+ reflections to surface themes."

4. Print the most recent reflection verbatim:
```
MOST RECENT REFLECTION:
[date] | [task]
──────────────────
[paragraph]
```

---

## STEP 10: PHILOSOPHY UPDATE

This step identifies findings severe enough to graduate into the philosophy — not just a prompt improvement, but a permanent new rule or anti-pattern that all future agents will be held to.

**Criteria for graduation:** A pattern qualifies if it meets EITHER of:
- 3+ occurrences in patterns.md AND average severity ≥ 6
- Appeared as a 🔍 RECURRING INSIGHT in Step 9 (meaning it showed up in post-task reflections, not just audit findings — a deeper signal)

For each qualifying pattern, spawn a single independent agent with this prompt:

"You are a senior software architect deciding whether a recurring code quality problem deserves a permanent place in a project's coding philosophy.

Here is the recurring pattern:
[category, description, occurrence count, severity range]

Here is the current philosophy document:
[full contents of ~/.claude/autocode/philosophy.md]

Your job: propose the exact text to add to the philosophy to prevent this pattern from recurring. Be specific about:
1. Which section it belongs in (Anti-Patterns That Are Always Wrong, The 15 Rules, 15 Rules Compliance Checklist, The Shipping Gate, or a new section if none fit)
2. The exact text to add — written in the same voice and format as the existing document
3. Why this rises to the level of philosophy (not just a prompt tip) — what makes it a permanent standard rather than a one-time fix

Do not suggest vague guidance. 'Handle errors properly' is useless. 'Never return undefined from a function that the caller treats as always-present — use a Result type or throw explicitly' is useful.

Output:
SECTION: [which section]
TEXT TO ADD:
[the exact text]
WHY THIS IS PHILOSOPHY-LEVEL: [one sentence]"

Capture the agent's proposal.

Print the proposal clearly:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  PHILOSOPHY UPDATE CANDIDATE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Pattern: [category] — [N] occurrences, avg severity [N]
  Section: [proposed section]

  Proposed addition:
  [TEXT TO ADD]

  Why philosophy-level: [reason]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Ask: "Add this to philosophy.md? (y/n)"

**If yes:**
1. Read `~/.claude/autocode/philosophy.md`
2. Insert the proposed text into the correct section
3. Append a new row to the `## CHANGELOG` table at the bottom of the file:
   ```
   | [today's date] | [section updated] | [one-line summary of what was added] | [pattern: N occurrences, avg severity N] |
   ```
4. Write the updated file
5. Print: "✅ Philosophy updated. Added to [section]. Changelog entry written."

**If no:**
Print: "Skipped. Run /patterns again after more data if this keeps recurring."

If multiple patterns qualify, present each proposal one at a time and ask y/n for each before moving to the next.

If no patterns qualify: print "No patterns meet the graduation threshold yet (need 3+ occurrences at severity ≥ 6, or a recurring reflection insight)."

---

## STEP 10.5: AGENT MEMORY FEEDBACK LOOP

After the philosophy update step, map systemic patterns back into agent memory files so agents explicitly watch for their own historical blind spots on the next run.

**Pattern-to-agent mapping:**
| Pattern Category | Target Agent(s) |
|-----------------|-----------------|
| `error-handling` | architect.md |
| `tests` | qa.md |
| `auth` | security.md |
| `security` | security.md |
| `data-loss` | security.md, architect.md |
| `feature-flag` | architect.md |
| `async` | architect.md |
| `edge-case` | qa.md |
| `code-quality` | architect.md |
| `performance` | architect.md |
| `documentation` | docs.md |
| `requirements` | qa.md |

**For each systemic pattern (3+ occurrences, severity ≥ 5) found in Step 3:**

1. Read the target agent's memory file at `.autocode/agents/[agent].md`
2. If file doesn't exist: print "No memory file for [agent] — run /meet to initialize" and skip
3. Find or create the `## Known Blind Spots` section
4. Add or update the entry for this category:
   ```
   - [category]: [N] occurrences, avg severity [N] — [specific watch-for from patterns analysis]
     Last seen: [most recent task where it appeared] | Updated: [today's date]
   ```
5. Write the updated memory file

**Also update CTO memory:**

Read `.autocode/agents/cto.md`. Update the Known Blind Spots column for the affected agent row in the Team Health table. Write the updated file.

**Print after all updates:**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  AGENT MEMORIES UPDATED
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  [list each memory file updated and what was written]
  Effect: Agents will explicitly check these patterns next run.
  Run /team-health to see updated blind spot catalog.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Log the update to `.autocode/patterns.md`:
```
## [today's date] | /patterns feedback — [N] blind spots written to agent memories
[list: agent | category | occurrences]
```

If no patterns meet the threshold (3+ occurrences, severity ≥ 5): print "No agent memory updates — patterns below threshold." and skip this step.

---

## RULES

- Never fabricate patterns — only report what is actually in the log
- Be direct and specific in recommendations — the goal is actionable prompt improvements
- If a pattern only appeared once, mention it briefly but do not recommend prompt changes for it yet
- Always check archives before prompting to archive (Step 6 before Step 8)
- Never archive trends.md or reflections.md — they are permanent
- Philosophy updates are permanent — never propose an addition that is vague, redundant with existing rules, or could apply to any codebase generically
- Read philosophy.md fresh before every proposed update — never work from a cached version
