#!/usr/bin/env bash
# Installs Claude dev team commands to ~/.claude/commands/
# Run from repo root: bash install.sh
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMANDS_DIR="$HOME/.claude/commands"

mkdir -p "$COMMANDS_DIR"

echo "Installing Claude dev team commands → $COMMANDS_DIR"
echo ""

INSTALLED=0
SKIPPED=0

for src in "$REPO_DIR/commands/"*.md; do
  name="$(basename "$src")"
  dest="$COMMANDS_DIR/$name"

  if [[ -L "$dest" && "$(readlink "$dest")" == "$src" ]]; then
    echo "  ✓ $name (already linked)"
    ((SKIPPED++)) || true
    continue
  fi

  if [[ -f "$dest" && ! -L "$dest" ]]; then
    backup="$dest.backup-$(date +%Y%m%d%H%M%S)"
    echo "  ⚠ $name exists (not a symlink) — backing up to $(basename "$backup")"
    mv "$dest" "$backup"
  fi

  ln -sf "$src" "$dest"
  echo "  → $name"
  ((INSTALLED++)) || true
done

echo ""
echo "Done. $INSTALLED installed, $SKIPPED already up to date."
echo ""
echo "Commands are symlinked — 'git pull' in this repo updates them automatically."
echo ""
echo "To add the project scripts to a codebase:"
echo "  bash add-to-project.sh /path/to/your/project"
