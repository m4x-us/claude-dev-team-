#!/usr/bin/env bash
# Checks if any finding category in patterns.md crossed the graduation threshold.
# Threshold: 3+ occurrences AND average severity >= 6.
# Usage: bash scripts/check-patterns-threshold.sh [patterns-file]
# Exit 0 = no threshold crossed (or file not found). Exit 1 = threshold crossed.
set -euo pipefail

PATTERNS_FILE="${1:-.autocode/patterns.md}"

if [[ ! -f "$PATTERNS_FILE" ]]; then
  echo "check-patterns-threshold: $PATTERNS_FILE not found — skipping"
  exit 0
fi

python3 - "$PATTERNS_FILE" << 'PYEOF'
import sys, re, collections

patterns_file = sys.argv[1]
content = open(patterns_file).read()

# Bullet format: "- category description — severity N | file:fn:line | annotation"
# Category and severity are on the same line — parse them together.
# Also handles SYNTHESIS entries: "- category description — severity N | CROSS-CUTTING | SYNTHESIS"
BULLET_PATTERN = r'^-\s+(\S+)\s+.+—\s+severity\s+(\d+)\s*\|'

category_data = collections.defaultdict(list)

for line in content.split('\n'):
    m = re.match(BULLET_PATTERN, line)
    if m:
        category_data[m.group(1)].append(int(m.group(2)))

OCCURRENCE_THRESHOLD = 3
SEVERITY_THRESHOLD = 6.0

crossed = []
for cat, severities in category_data.items():
    if len(severities) >= OCCURRENCE_THRESHOLD:
        avg = sum(severities) / len(severities)
        if avg >= SEVERITY_THRESHOLD:
            crossed.append((cat, len(severities), round(avg, 1)))

if crossed:
    print("check-patterns-threshold: THRESHOLD CROSSED — run /patterns to graduate findings:")
    for cat, count, avg in crossed:
        print(f"  - {cat}: {count} occurrences, avg severity {avg}")
    sys.exit(1)
else:
    print("check-patterns-threshold: no category has crossed graduation threshold")
    sys.exit(0)
PYEOF
