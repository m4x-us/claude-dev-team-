#!/usr/bin/env bash
# Runs Stryker mutation testing incrementally on packages affected by changed files.
# Usage: bash scripts/mutation-gate.sh [file1 file2 ...]
# No args: reads changed files from git diff (staged, then unstaged).
# Exit 0 = all pass, or no mutation config found. Exit 1 = threshold breached.
# Compatible with bash 3.2+ (macOS default).
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# Collect changed files into a temp file
TMPCHANGED="$(mktemp /tmp/mutation-gate-changed.XXXXXX)"
TMPPACKAGES="$(mktemp /tmp/mutation-gate-packages.XXXXXX)"
trap 'rm -f "$TMPCHANGED" "$TMPPACKAGES"' EXIT

if [[ $# -gt 0 ]]; then
  for f in "$@"; do echo "$f"; done >> "$TMPCHANGED"
else
  git diff --cached --name-only 2>/dev/null >> "$TMPCHANGED" || true
  git diff --name-only 2>/dev/null >> "$TMPCHANGED" || true
fi

# Deduplicate changed files
TMPCHANGED2="$(mktemp /tmp/mutation-gate-changed2.XXXXXX)"
trap 'rm -f "$TMPCHANGED" "$TMPCHANGED2" "$TMPPACKAGES"' EXIT
sort -u "$TMPCHANGED" > "$TMPCHANGED2"

if [[ ! -s "$TMPCHANGED2" ]]; then
  echo "mutation-gate: no changed files detected — skipping"
  exit 0
fi

# Walk up from each changed file to find stryker.config.json
while IFS= read -r file; do
  [[ -z "$file" ]] && continue
  # Make absolute
  if [[ "$file" != /* ]]; then
    abs_file="$REPO_ROOT/$file"
  else
    abs_file="$file"
  fi
  dir="$(dirname "$abs_file")"
  while [[ "$dir" != "/" ]]; do
    if [[ -f "$dir/stryker.config.json" ]]; then
      echo "$dir" >> "$TMPPACKAGES"
      break
    fi
    if [[ "$dir" == "$REPO_ROOT" ]]; then
      break
    fi
    dir="$(dirname "$dir")"
  done
done < "$TMPCHANGED2"

# Deduplicate packages
TMPPACKAGES2="$(mktemp /tmp/mutation-gate-pkgs2.XXXXXX)"
trap 'rm -f "$TMPCHANGED" "$TMPCHANGED2" "$TMPPACKAGES" "$TMPPACKAGES2"' EXIT
sort -u "$TMPPACKAGES" > "$TMPPACKAGES2"

if [[ ! -s "$TMPPACKAGES2" ]]; then
  echo "mutation-gate: no stryker.config.json found in directory tree — skipping"
  exit 0
fi

FAILED=""
while IFS= read -r pkg_dir; do
  [[ -z "$pkg_dir" ]] && continue
  if [[ ! -f "$pkg_dir/package.json" ]]; then
    echo "mutation-gate: WARNING — no package.json in $pkg_dir, skipping"
    continue
  fi
  pkg_name=$(python3 -c "import json; print(json.load(open('$pkg_dir/package.json'))['name'])" 2>/dev/null || true)
  if [[ -z "$pkg_name" ]]; then
    echo "mutation-gate: WARNING — could not read package name from $pkg_dir/package.json, skipping"
    continue
  fi

  echo "mutation-gate: running mutation:ci for $pkg_name ($pkg_dir)..."
  if ! pnpm --filter "$pkg_name" run mutation:ci; then
    FAILED="$FAILED $pkg_name"
  fi
done < "$TMPPACKAGES2"

if [[ -n "$FAILED" ]]; then
  echo ""
  echo "mutation-gate: THRESHOLD BREACHED — failed packages:$FAILED"
  echo "Fix: write tests whose assertions FAIL when the corresponding code is removed or mutated."
  exit 1
fi

echo "mutation-gate: all packages passed mutation threshold"
exit 0
