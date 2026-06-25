# Patterns — Health Report Generator

Read `.autocode/patterns.md` in the current project, analyze recurring findings, and generate a visual HTML health report. Then run the interactive philosophy graduation steps in the terminal.

---

## PHASE 0: READ ALL DATA (silent — do not print yet)

Read `.autocode/patterns.md` → `PATTERNS_RAW`. If it doesn't exist or is empty: print "No pattern data yet. Run /task on a few tasks first." Stop.

Read `.autocode/trends.md` → `TRENDS_RAW` (or "None").
Read `.autocode/worldclass-trends.md` → `WORLDCLASS_RAW` (or "None").
Read `.autocode/reflections.md` → `REFLECTIONS_RAW` (or "None").

---

## PHASE 1: ANALYZE (silent — build all variables before generating HTML)

**1A — Parse patterns.md:**

Parse every bullet line matching: `^-\s+(\S+)\s+(.+)—\s+severity\s+(\d+)\s*\|`
Group by category. For each category compute:
- `occurrences` — count of matching lines
- `tasks` — unique task identifiers extracted from the `## [date] | Task: [...]` header above each bullet
- `avg_severity` — mean of all severity values in that category
- `max_severity` — highest severity seen
- `last_seen_task` — task identifier from the most recent entry

Systemic patterns = categories where `occurrences >= 3` AND the entries span `>= 2` different tasks.

**1B — Parse trends.md:**

Parse each data row (skip header). Extract: date, task (first 40 chars), cycles, final_severity, verdict (PASS / FAIL / MAX_CYCLES).
- `pass_rate` = PASS count / total × 100 (round to 1 decimal)
- `avg_severity_recent` = mean of last 5 final_severity values
- `trend_direction` = compare avg of last 3 vs prior 3 (need 6+ rows): IMPROVING / STABLE / DEGRADING / "Not enough data"
- `audit_rows` = array of {date, task, cycles, severity, verdict} for chart

**1C — Parse worldclass-trends.md:**

Parse each data row. Extract: date, task, cycles, score, verdict.
- `avg_score_recent` = mean of last 5 scores (PASS rows only)
- `wc_trend_direction` = compare avg of last 3 vs prior 3 PASS rows: IMPROVING / STABLE / DEGRADING / "Not enough data"
- `wc_rows` = array of {date, task, score, verdict} for chart

**1D — Plain English translations:**

Use this mapping for every category name displayed to the user:
- `error-handling` → "Error Protection"
- `tests` → "Test Quality"
- `auth` → "Access Control"
- `security` → "Security"
- `data-loss` → "Data Safety"
- `feature-flag` → "Feature Switches"
- `async` → "Background Tasks"
- `edge-case` → "Edge Cases"
- `code-quality` → "Code Organization"
- `performance` → "Speed & Efficiency"
- `requirements` → "Feature Completeness"
- `documentation` → "Documentation"
- Any unmapped category → title-case the raw name

Business impact per category (one sentence, non-technical):
- `error-handling` → "The app may crash silently or show confusing error messages to customers."
- `tests` → "Bugs may go undetected until customers find them in production."
- `auth` → "The wrong users may be able to access data they shouldn't see."
- `security` → "The system may be exposed to outside attacks or data breaches."
- `data-loss` → "Customer data could be permanently lost or corrupted."
- `feature-flag` → "New features may not be safely controllable after launch."
- `async` → "Background tasks may fail silently or complete in the wrong order."
- `edge-case` → "The app may behave unexpectedly in unusual but real situations."
- `code-quality` → "The codebase becomes harder and slower to change over time."
- `performance` → "The app may become slow or unresponsive as usage grows."
- `requirements` → "Finished features may not fully match what was originally requested."
- `documentation` → "The team loses context and makes avoidable mistakes on existing code."

Severity badge (based on `avg_severity`):
- 1.0–3.4 → label: "Low Priority", color: #3b82f6
- 3.5–5.4 → label: "Worth Fixing", color: #f59e0b
- 5.5–6.9 → label: "Fix Soon", color: #f97316
- 7.0–8.4 → label: "Fix Now", color: #ef4444
- 8.5–10 → label: "Critical", color: #7f1d1d

Overall health (based on systemic pattern count):
- 0–2 → "HEALTHY", color: #22c55e, emoji: ✅
- 3–4 → "NEEDS ATTENTION", color: #f59e0b, emoji: ⚠️
- 5+ → "SIGNIFICANT DRIFT", color: #ef4444, emoji: 🔴

**1E — Executive summary bullets (3 sentences, plain English, no jargon):**

Compose from the data:
1. Pass rate sentence: "Your dev team has passed [pass_rate]% of recent audits" — or if no data "No audit history yet."
2. Most recurring issue: "The most common issue is [plain English category] — it has appeared [N] times across [N] tasks." — or "No recurring issues yet."
3. Trend sentence: "Quality is [IMPROVING → getting better / STABLE → holding steady / DEGRADING → getting worse]." Combine both audit and worldclass trends. If not enough data: "Not enough history yet to show a trend."

---

## PHASE 2: GENERATE HTML REPORT

Create directory: `mkdir -p .autocode/reports`

Generate a complete self-contained HTML file and write it to `.autocode/reports/patterns-[today's date].html`.

The file must be entirely self-contained — no external file dependencies except CDN links (Chart.js and Google Fonts, both loaded via HTTPS). All data is embedded as JavaScript variables. The file must render correctly when opened directly in a browser via `open`.

**PAGE STRUCTURE:**

The HTML page has the following sections in order. Use a dark theme throughout: background #0f172a, card background #1e293b, primary text #f1f5f9, secondary text #94a3b8, border color #334155. Font: Inter from Google Fonts (`https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap`). Load Chart.js from `https://cdn.jsdelivr.net/npm/chart.js`.

**HEADER SECTION:**
- Left side: "Codebase Health Report" in large bold text (28px), below it the date in secondary color
- Right side: large health badge — pill shape, background = health color at 20% opacity, border = health color, text = health emoji + " " + health label in health color (e.g. "✅ HEALTHY"). Font size 16px, padding 8px 20px, border-radius 999px.
- Full-width horizontal rule below

**EXECUTIVE SUMMARY SECTION:**
- Section heading: "At a Glance" (18px, medium weight, secondary color, uppercase, letter-spacing)
- Three cards in a row (or stacked on narrow screens). Each card: white icon on left (use simple Unicode: 📊 📋 📈), plain English sentence on right. Card background #1e293b, border-radius 12px, padding 16px 20px.

**HABITS TO FIX SECTION:**
Show only if systemic patterns exist (occurrences >= 3 AND spans >= 2 tasks). Heading: "Habits to Fix" with count badge.
One card per systemic pattern, sorted by avg_severity descending. Each card contains:
- Top row: plain English category name (600 weight, 17px) on left, severity badge pill on right
- Business impact sentence in secondary color (14px), italic
- Stats row: "Appeared [N] times" · "Across [N] tasks: [task list]" · "Last seen: [task]"
- Thin colored left border = severity badge color

If no systemic patterns: show a green card "No repeating habits — every issue so far has been a one-off."

**CHARTS SECTION — "By the Numbers":**

Four charts in a 2×2 grid (2 columns on wide screens, 1 column on narrow). Each chart in its own card with a plain English title and subtitle.

Chart 1 — "Issues by Type" (horizontal bar chart):
- Title: "Issues by Type", subtitle: "How many times each problem category appeared"
- Data: all categories from patterns.md, sorted by occurrences descending
- X axis: count (integers), Y axis: plain English category names
- Bar color: severity badge color for that category's avg_severity
- Show value labels at end of each bar

Chart 2 — "Audit Pass Rate" (doughnut chart):
- Title: "Audit Results", subtitle: "Pass vs fail across all runs"
- Data: PASS count, FAIL count, MAX_CYCLES count
- Colors: #22c55e for PASS, #ef4444 for FAIL, #f97316 for MAX_CYCLES
- Center text (plugin or CSS): large pass_rate% number, "pass rate" below it in secondary color
- If no trend data: show placeholder "No audit history yet"

Chart 3 — "Audit Severity Over Time" (line chart):
- Title: "Audit Quality Over Time", subtitle: "Lower severity = fewer serious issues found (better)"
- Data: audit_rows array — X axis dates, Y axis final_severity values
- Line color: #3b82f6, fill below line at 10% opacity
- Points colored by verdict: green for PASS, red for FAIL, orange for MAX_CYCLES
- Y axis: 0–10, label each tick (1=Trivial, 5=Medium, 8=Critical)
- Horizontal dashed reference line at y=5 labeled "Concern threshold"
- If fewer than 2 rows: show placeholder "Need more runs to show trend"

Chart 4 — "WorldClass Scores" (line chart):
- Title: "WorldClass Scores Over Time", subtitle: "Target: 95/100 — are we getting there?"
- Data: wc_rows — X axis dates, Y axis score values
- Line color: #a855f7, fill below at 10% opacity
- Points colored: green if score >= 95, yellow if 80-94, red if < 80
- Y axis: 0–100
- Horizontal dashed line at y=95 labeled "World-class threshold" in #22c55e
- If fewer than 2 rows: show placeholder "Need more runs to show trend"

**TASK BREAKDOWN TABLE:**
- Heading: "Task History"
- Table columns: Task | Date | Issues Found | Highest Severity | Verdict | WorldClass Score
- Populate from audit_rows joined with wc_rows on task name (fuzzy match first 40 chars)
- Row background: #1e293b, alternating slightly lighter #243044
- Verdict cell: colored pill badge (green/red/orange)
- Sort: most recent first
- If no data: "No task history yet."

**PHILOSOPHY CANDIDATES SECTION:**
Show only if any systemic patterns qualify for graduation (occurrences >= 3, avg severity >= 6, spans >= 2 tasks).
Heading: "Ready to Become Rules" with subtitle "These issues have appeared enough times that the dev team should add them as permanent coding standards."
One card per qualifying pattern, plain English, with a "→ See terminal for approval" note.
If none qualify: omit this section entirely.

**TECHNICAL DETAIL SECTION (collapsible):**
- A collapsed `<details><summary>` block: "Technical Detail (for developers)"
- Inside: raw patterns.md contents in a `<pre>` block with monospace font, secondary color, smaller font size
- Not expanded by default

**FOOTER:**
- "Generated by /patterns on [date]" in small secondary text, centered
- "Open .autocode/reports/ to find previous reports"

---

## PHASE 3: OPEN REPORT

Run: `open .autocode/reports/patterns-[today's date].html`

Print in terminal:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  HEALTH REPORT GENERATED
  Opened in your browser.
  Saved: .autocode/reports/patterns-[date].html
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## PHASE 4: INTERACTIVE STEPS (terminal)

**Step 4A — Archive prompt:**

Ask in terminal: "Archive this batch and start fresh? (y/n)"

If yes:
1. Rename `.autocode/patterns.md` → `.autocode/patterns-archive-[today's date].md`
2. Create fresh `.autocode/patterns.md` with header: `# AutoCode Patterns Log`
3. Print: "✅ Archived to patterns-archive-[date].md. Starting fresh."

If no: print "Keeping current data."

---

**Step 4B — Philosophy graduation:**

For each pattern that qualifies (occurrences >= 3 AND avg_severity >= 6 AND spans >= 2 tasks):

Spawn a single independent agent:

"You are a senior software architect deciding whether a recurring code quality problem deserves a permanent place in a project's coding philosophy.

Recurring pattern: [category, plain English name, occurrence count, avg severity, task list]

Current philosophy document:
[full contents of ~/.claude/autocode/philosophy.md]

Propose the exact text to add to prevent this pattern from recurring. Be specific:
1. Which section it belongs in
2. The exact text to add — same voice and format as the existing document
3. Why this rises to the level of philosophy (not just a one-time fix)

Do not suggest vague guidance. 'Handle errors properly' is useless. Cite the specific scenario, function type, or pattern.

Output:
SECTION: [which section]
TEXT TO ADD:
[exact text]
WHY PHILOSOPHY-LEVEL: [one sentence]"

Print proposal in terminal:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  PHILOSOPHY CANDIDATE: [plain English name]
  [N] occurrences · avg severity [N] · [N] tasks
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Section: [proposed section]

  [TEXT TO ADD]

  Why: [reason]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Ask: "Add this to philosophy.md? (y/n)"

If yes:
1. Read `~/.claude/autocode/philosophy.md`
2. Insert text into correct section
3. Append to `## CHANGELOG` table: `| [date] | [section] | [one-line summary] | [N occurrences, avg severity N] |`
4. Write the updated file
5. Print: "✅ Added to [section]."

If no: print "Skipped."

Present each candidate one at a time. If none qualify: print "No patterns meet the graduation threshold (need 3+ occurrences at avg severity ≥ 6 across 2+ tasks)."

---

**Step 4C — Agent memory updates:**

For each systemic pattern (occurrences >= 3, severity >= 5, spans >= 2 tasks), update the target agent memory:

Category → agent mapping:
- error-handling, feature-flag, async, edge-case, code-quality, performance, data-loss → architect.md
- tests, requirements → qa.md
- auth, security → security.md
- documentation → docs.md

For each target agent file `.autocode/agents/[agent].md`:
1. If file doesn't exist: skip (print warning)
2. Find or create `## Known Blind Spots` section
3. Add or update entry:
   `- [plain English name]: [N] occurrences, avg severity [N] — [specific watch-for]`
   `  Last seen: [last_seen_task] | Updated: [today's date]`

Update `.autocode/agents/cto.md` Known Blind Spots column for affected agents.

Print:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  AGENT MEMORIES UPDATED
  [list each file updated]
  Agents will now explicitly watch for these patterns.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Log to `.autocode/patterns.md`:
`## [today's date] | /patterns feedback — [N] blind spots written to agent memories`

---

## RULES

- Never fabricate data — only use what is in the log files
- Plain English translations are mandatory — never show raw category names in the HTML
- The HTML file must be self-contained and open without a server
- CDN links (Chart.js, Google Fonts) are the only external dependencies allowed
- Charts show "Need more runs" placeholders if data is insufficient — never show empty axes
- Philosophy updates require the agent's proposal — never write to philosophy.md without spawning the agent
- Archive prompt always runs before philosophy step
- Cross-task diversity required for systemic patterns — 3 occurrences on the same task is NOT a systemic pattern
- Previous report files in .autocode/reports/ are never deleted — accumulate over time
