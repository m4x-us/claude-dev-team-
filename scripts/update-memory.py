#!/usr/bin/env python3
"""
Machine-enforced deduplication and update for agent memory files.

Usage:
  python3 scripts/update-memory.py --findings '<JSON array>' --memory-file .autocode/agents/security.md

Exit 0 = success (prints summary).
Exit 1 = error (prints MEMORY_ERROR to stderr).

No resolved sweep: a finding absent from this audit may simply not have been in scope
for this task. Automatic resolution would corrupt memory for findings from other tasks.
"""
import json, sys, re, argparse
from pathlib import Path
from datetime import date
from typing import Optional

TODAY = date.today().isoformat()

SECTION_OPEN = "## Past Findings — Open"
SECTION_RESOLVED = "## Past Findings — Resolved"
SECTION_PATTERNS = "## Recurring Patterns"

MEMORY_TEMPLATE = """---
agent: {agent}
last-updated: {today}
meets: 1
---
# {title} Agent Memory

## Past Findings — Open

## Past Findings — Resolved

## Recurring Patterns
"""

def dedup_key(file_: str, function_: str, description: str) -> str:
    """Stable dedup key: file + function + first 50 chars of lowercased description."""
    return f"{file_}|{function_}|{description[:50].lower().strip()}"

def parse_finding_block(text: str) -> Optional[dict]:
    """
    Parse a finding block from memory file. Expected format:
    ### [F] category | file | function
    Description: ...
    Severity: N | First-seen: DATE | Last-seen: DATE | Occurrences: N
    """
    header_match = re.match(
        r"### \[([FR])\] ([^|]+) \| ([^|]+) \| (.+)",
        text.split("\n")[0].strip()
    )
    if not header_match:
        return None
    status = "open" if header_match.group(1) == "F" else "resolved"
    category = header_match.group(2).strip()
    file_ = header_match.group(3).strip()
    function_ = header_match.group(4).strip()

    desc_match = re.search(r"Description: (.+)", text)
    sev_match = re.search(r"Severity: (\d+)", text)
    fs_match = re.search(r"First-seen: ([0-9-]+)", text)
    ls_match = re.search(r"Last-seen: ([0-9-]+)", text)
    occ_match = re.search(r"Occurrences: (\d+)", text)

    return {
        "status": status,
        "category": category,
        "file": file_,
        "function": function_,
        "description": desc_match.group(1).strip() if desc_match else "",
        "severity": int(sev_match.group(1)) if sev_match else 0,
        "first_seen": fs_match.group(1) if fs_match else TODAY,
        "last_seen": ls_match.group(1) if ls_match else TODAY,
        "occurrences": int(occ_match.group(1)) if occ_match else 1,
        "raw": text,
    }

def format_finding(f: dict) -> str:
    status_char = "F" if f["status"] == "open" else "R"
    lines = [
        f"### [{status_char}] {f['category']} | {f['file']} | {f['function']}",
        f"Description: {f['description']}",
        f"Severity: {f['severity']} | First-seen: {f['first_seen']} | Last-seen: {f['last_seen']} | Occurrences: {f['occurrences']}",
    ]
    if f.get("recurrence_note"):
        lines.append(f"RECURRED: {f['recurrence_note']}")
    return "\n".join(lines)

def split_sections(content: str) -> dict:
    sections = {}
    current = "header"
    current_lines = []
    for line in content.split("\n"):
        if line.startswith("## "):
            sections[current] = "\n".join(current_lines)
            current = line.strip()
            current_lines = []
        else:
            current_lines.append(line)
    sections[current] = "\n".join(current_lines)
    return sections

def parse_findings_from_section(section_text: str) -> list[dict]:
    blocks = re.split(r"\n(?=### \[)", section_text)
    findings = []
    for block in blocks:
        block = block.strip()
        if block:
            f = parse_finding_block(block)
            if f:
                findings.append(f)
    return findings

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--findings", required=True, help="JSON array of findings")
    parser.add_argument("--memory-file", required=True, help="Path to memory file")
    args = parser.parse_args()

    try:
        new_findings = json.loads(args.findings)
    except json.JSONDecodeError as e:
        print(f"MEMORY_ERROR: Invalid findings JSON — {e}", file=sys.stderr)
        sys.exit(1)

    memory_path = Path(args.memory_file)

    # Create memory file if missing
    if not memory_path.exists():
        agent_name = memory_path.stem.replace("_", " ").title()
        memory_path.parent.mkdir(parents=True, exist_ok=True)
        memory_path.write_text(MEMORY_TEMPLATE.format(
            agent=agent_name, today=TODAY, title=agent_name
        ))

    content = memory_path.read_text()
    sections = split_sections(content)

    open_findings = parse_findings_from_section(sections.get(SECTION_OPEN, ""))
    resolved_findings = parse_findings_from_section(sections.get(SECTION_RESOLVED, ""))

    # Build index by dedup_key
    open_index = {dedup_key(f["file"], f["function"], f["description"]): f for f in open_findings}
    resolved_index = {dedup_key(f["file"], f["function"], f["description"]): f for f in resolved_findings}

    added = 0
    updated = 0
    recurred = 0

    for nf in new_findings:
        key = dedup_key(nf.get("file", ""), nf.get("function", ""), nf.get("description", ""))

        if key in open_index:
            # Already tracked as open — update last-seen and increment occurrences
            existing = open_index[key]
            existing["last_seen"] = TODAY
            existing["occurrences"] += 1
            updated += 1

        elif key in resolved_index:
            # Was resolved but recurred — move back to open
            existing = resolved_index.pop(key)
            existing["status"] = "open"
            existing["last_seen"] = TODAY
            existing["occurrences"] += 1
            existing["recurrence_note"] = f"{TODAY}: {nf.get('description', '')}"
            open_index[key] = existing
            recurred += 1

        else:
            # New finding — append
            open_index[key] = {
                "status": "open",
                "category": nf.get("category", "unknown"),
                "file": nf.get("file", "unknown"),
                "function": nf.get("function", "unknown"),
                "description": nf.get("description", ""),
                "severity": nf.get("severity", 0),
                "first_seen": TODAY,
                "last_seen": TODAY,
                "occurrences": 1,
            }
            added += 1

    # NOTE: No resolved sweep. A finding absent from this audit may simply not have been in
    # scope for this task. Automatic resolution would corrupt memory for findings from other tasks.
    # Findings accumulate until a task explicitly confirms they are fixed across multiple audit cycles.

    # Update Recurring Patterns
    patterns_lines = []
    for f in open_index.values():
        if f["occurrences"] >= 2:
            patterns_lines.append(
                f"- {f['category']}: {f['occurrences']} occurrences — {f['description']}. "
                f"Last seen: {f['last_seen']}"
            )

    # Reconstruct file
    header = sections.get("header", "").strip()
    open_section = SECTION_OPEN + "\n\n" + "\n\n".join(format_finding(f) for f in open_index.values())
    resolved_section = SECTION_RESOLVED + "\n\n" + "\n\n".join(format_finding(f) for f in resolved_index.values())
    patterns_section = SECTION_PATTERNS + "\n" + "\n".join(patterns_lines)

    new_content = "\n\n".join([header, open_section, resolved_section, patterns_section]).strip() + "\n"
    memory_path.write_text(new_content)

    print(f"OK: {added} added, {updated} updated, {recurred} recurred")

if __name__ == "__main__":
    main()
