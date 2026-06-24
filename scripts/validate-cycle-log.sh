#!/usr/bin/env bash
# Validates a cycle log entry file has required fields with correct format.
# Usage: bash scripts/validate-cycle-log.sh /path/to/cycle_entry.txt
# Exit 0 = valid. Exit 1 = invalid (CYCLE_LOG_ERROR lines on stderr).

set -euo pipefail

ENTRY_FILE="${1:-}"

if [[ -z "$ENTRY_FILE" ]]; then
  echo "CYCLE_LOG_ERROR: No file path provided. Usage: bash scripts/validate-cycle-log.sh /path/to/entry.txt" >&2
  exit 1
fi

if [[ ! -f "$ENTRY_FILE" ]]; then
  echo "CYCLE_LOG_ERROR: File not found: '$ENTRY_FILE'" >&2
  exit 1
fi

ERRORS=()

REQUIRED_FIELDS=(
  "Build approach:"
  "Scripts:"
  "Audit findings"
  "Fixed this cycle:"
  "Still open:"
  "New findings introduced:"
  "Regression signal:"
  "CTO diagnosis run:"
)

for field in "${REQUIRED_FIELDS[@]}"; do
  if ! grep -qF "$field" "$ENTRY_FILE"; then
    ERRORS+=("Missing required field: '$field'")
  fi
done

# Build approach must contain file:function pattern (e.g. apps/web/src/api/route.ts:GET)
BUILD_LINE=$(grep "Build approach:" "$ENTRY_FILE" | head -1)
if [[ -n "$BUILD_LINE" ]]; then
  if ! echo "$BUILD_LINE" | grep -qE "[A-Za-z0-9_/.-]+\.[A-Za-z]{1,5}:[A-Za-z_][A-Za-z0-9_]*"; then
    ERRORS+=("Build approach must include file:function (e.g. apps/web/src/api/route.ts:GET) — found: '$BUILD_LINE'")
  fi
fi

# Scripts must be PASS or FAIL
SCRIPTS_LINE=$(grep "Scripts:" "$ENTRY_FILE" | head -1)
if [[ -n "$SCRIPTS_LINE" ]]; then
  if ! echo "$SCRIPTS_LINE" | grep -qE "\b(PASS|FAIL)\b"; then
    ERRORS+=("Scripts: field must contain PASS or FAIL — found: '$SCRIPTS_LINE'")
  fi
fi

# Structured finding lines must conform to format if present
# Format: [Fid|sev:N|category|file:function:line|description|annotation]
FINDING_LINES=$(grep -E "^\s+\[F[0-9]+" "$ENTRY_FILE" 2>/dev/null || true)
if [[ -n "$FINDING_LINES" ]]; then
  while IFS= read -r line; do
    if ! echo "$line" | grep -qE "^\s+\[F[0-9]+\|sev:[0-9]+\|[a-z-]+\|[^|]+:[^|]+:[0-9]+\|[^|]+\|(NEW|REPEATED FROM CYCLE [0-9]+|ESCALATE)\]$"; then
      ERRORS+=("Malformed structured finding: expected [Fid|sev:N|category|file:fn:line|desc|annotation] — got: $(echo "$line" | tr -d '\n')")
    fi
  done <<< "$FINDING_LINES"
fi

if [[ ${#ERRORS[@]} -gt 0 ]]; then
  for err in "${ERRORS[@]}"; do
    echo "CYCLE_LOG_ERROR: $err" >&2
  done
  exit 1
fi

echo "OK: cycle log entry validated"
exit 0
