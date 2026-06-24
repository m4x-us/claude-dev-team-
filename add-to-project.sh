#!/usr/bin/env bash
# Copies the dev team scripts into a project's scripts/ directory.
# Run from repo root: bash add-to-project.sh /path/to/your/project
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $# -eq 0 ]]; then
  echo "Usage: bash add-to-project.sh /path/to/your/project"
  exit 1
fi

PROJECT_DIR="$(realpath "$1")"

if [[ ! -d "$PROJECT_DIR" ]]; then
  echo "Error: $PROJECT_DIR is not a directory"
  exit 1
fi

SCRIPTS_DIR="$PROJECT_DIR/scripts"
mkdir -p "$SCRIPTS_DIR"

echo "Installing dev team scripts → $SCRIPTS_DIR"
echo ""

for src in "$REPO_DIR/scripts/"*.sh "$REPO_DIR/scripts/"*.py; do
  [[ -f "$src" ]] || continue
  name="$(basename "$src")"
  dest="$SCRIPTS_DIR/$name"

  if [[ -f "$dest" ]]; then
    if cmp -s "$src" "$dest"; then
      echo "  ✓ $name (unchanged)"
      continue
    fi
    echo "  ↺ $name (updated)"
  else
    echo "  → $name"
  fi

  cp "$src" "$dest"
  chmod +x "$dest"
done

echo ""
echo "Done. Scripts are in $SCRIPTS_DIR"
echo ""
echo "These scripts expect to be run from the project root:"
echo "  bash scripts/deep-audit.sh <changed-files>"
echo "  bash scripts/shipping-gate.sh <directory>"
echo "  bash scripts/mutation-gate.sh [changed-files]"
echo "  bash scripts/check-patterns-threshold.sh .autocode/patterns.md"
