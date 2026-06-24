#!/usr/bin/env bash
# Validates FINDINGS_JSON against the required schema.
# Usage: bash scripts/validate-findings.sh '<json_string>'
# Exit 0 = valid. Exit 1 = invalid (SCHEMA_ERROR lines on stderr).

set -euo pipefail

FINDINGS_JSON="${1:-}"

if [[ -z "$FINDINGS_JSON" ]]; then
  echo "SCHEMA_ERROR: No FINDINGS_JSON argument provided" >&2
  exit 1
fi

python3 - "$FINDINGS_JSON" << 'PYEOF'
import json, sys, re

try:
    findings = json.loads(sys.argv[1])
except json.JSONDecodeError as e:
    print(f"SCHEMA_ERROR: FINDINGS_JSON is not valid JSON — {e}", file=sys.stderr)
    sys.exit(1)

if not isinstance(findings, list):
    print("SCHEMA_ERROR: FINDINGS_JSON must be a JSON array, not an object or scalar", file=sys.stderr)
    sys.exit(1)

REQUIRED_FIELDS = ["id", "severity", "category", "file", "function", "line", "description", "annotation"]
VALID_CATEGORIES = {
    "error-handling", "tests", "auth", "security", "data-loss",
    "feature-flag", "async", "edge-case", "code-quality", "performance", "requirements"
}
HEDGING_PATTERNS = [
    r"\bappears to\b", r"\blikely\b", r"\bmay\b", r"\bshould be\b",
    r"\bprobably\b", r"\bseems to\b", r"\bmight\b"
]
# Philosophy violation keywords — any of these without a Rule # citation = drift
PHILOSOPHY_VIOLATION_KEYWORDS = [
    "not best practice", "poor practice", "bad practice",
    "violates the principle", "not following", "should follow",
    "doesn't follow", "does not follow", "against convention"
]

errors = []
ids_seen = set()

for i, f in enumerate(findings):
    fid = f.get("id", f"finding[{i}]")

    if fid in ids_seen:
        errors.append(f"{fid}: duplicate id — each finding must have a unique id")
    ids_seen.add(fid)

    for field in REQUIRED_FIELDS:
        if field not in f:
            errors.append(f"{fid}: missing required field '{field}'")

    sev = f.get("severity")
    if sev is not None:
        try:
            sev_int = int(sev)
            if not (1 <= sev_int <= 10):
                errors.append(f"{fid}: severity {sev} out of range — must be 1-10")
        except (ValueError, TypeError):
            errors.append(f"{fid}: severity '{sev}' is not an integer")

    cat = f.get("category", "")
    if cat and cat not in VALID_CATEGORIES:
        errors.append(f"{fid}: invalid category '{cat}' — must be one of {sorted(VALID_CATEGORIES)}")

    ann = f.get("annotation", "")
    if ann:
        valid_ann = (
            ann == "NEW" or
            ann == "ESCALATE" or
            re.match(r"^REPEATED FROM CYCLE \d+$", ann)
        )
        if not valid_ann:
            errors.append(f"{fid}: invalid annotation '{ann}' — must be NEW, REPEATED FROM CYCLE N, or ESCALATE")

    desc = f.get("description", "")

    # Check hedging language
    for pattern in HEDGING_PATTERNS:
        if re.search(pattern, desc, re.IGNORECASE):
            errors.append(
                f"{fid}: description contains hedging language '{pattern}' — "
                f"cite specific behavior at file:function:line or remove this finding"
            )
            break

    # Check philosophy violations without Rule # citation
    desc_lower = desc.lower()
    for phrase in PHILOSOPHY_VIOLATION_KEYWORDS:
        if phrase in desc_lower:
            # Must contain "Rule" followed by a number
            if not re.search(r"\bRule\s+\d+", desc, re.IGNORECASE):
                errors.append(
                    f"{fid}: description mentions a philosophy violation ('{phrase}') "
                    f"without citing the specific Rule number — "
                    f"required format: 'Violates Rule N: [what rule says] at file:function:line'"
                )
            break

    # Pipe characters corrupt the structured cycle log format
    if "|" in desc:
        errors.append(
            f"{fid}: description contains '|' which corrupts the structured cycle log format — "
            f"replace '|' with ';' or rephrase"
        )

    # Both file and function cannot be 'unknown'
    if f.get("file") == "unknown" and f.get("function") == "unknown":
        errors.append(
            f"{fid}: both file and function are 'unknown' — findings must cite a specific location. "
            f"If this is an architectural gap with no single owner, name the most relevant entry point."
        )

    # severity_note: only allowed when reducing severity; must have proper prefix
    note = f.get("severity_note", "")
    if note and "SEVERITY_REDUCTION" not in note:
        errors.append(
            f"{fid}: severity_note present but missing required prefix "
            f"'SEVERITY_REDUCTION: N→M, root cause evidence: file:function:line' — "
            f"omit severity_note entirely if severity was not reduced from a prior cycle"
        )

if errors:
    for e in errors:
        print(f"SCHEMA_ERROR: {e}", file=sys.stderr)
    sys.exit(1)

print(f"OK: {len(findings)} findings validated")
PYEOF
