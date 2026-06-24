# Claude Dev Team

A CTO-orchestrated AI development team for Claude Code. Three specialized agents — build, audit, and orchestration — working together with machine-enforced quality gates.

## What's included

**Slash commands** (installed to `~/.claude/commands/`):

| Command | Role |
|---------|------|
| `/task` | CTO — orchestrates the full build-audit-fix cycle |
| `/autocode` | Build agent — implements features with test gates and mutation testing |
| `/audit` | Audit team — four independent reviewers (A, B, Security, Red Adversarial) synthesized by Agent C |
| `/patterns` | Graduate recurring findings into philosophy rules |
| `/worldclass` | Self-assessment against world-class engineering standards |
| `/reflect` | Post-cycle reflection and lessons learned |
| `/findings` | Query and manage the findings history |
| `/resume` | Session resume protocol |
| `/consult` | Specialist consultation |
| `/meet` | Simulated stakeholder meeting |
| `/tasks` | Task list management |
| `/team-health` | Dev team health assessment |

**Project scripts** (copied to each project's `scripts/`):

| Script | Purpose |
|--------|---------|
| `deep-audit.sh` | Deep implementation audit — catches incident-class bugs |
| `shipping-gate.sh` | Feature completeness gate — tests, auth, feature flags |
| `mutation-gate.sh` | Stryker mutation testing gate — ensures tests catch real bugs |
| `check-patterns-threshold.sh` | Detects when recurring findings are ready to become rules |
| `validate-findings.sh` | Machine schema validation for FINDINGS_JSON |
| `validate-cycle-log.sh` | Validates the audit cycle log format |
| `update-memory.py` | Updates Claude's cross-session memory from cycle data |

## Install

**On a new machine:**

```bash
git clone https://github.com/m4x-us/claude-dev-team.git ~/claude-dev-team
cd ~/claude-dev-team
bash install.sh
```

Commands are symlinked — `git pull` updates them automatically.

**Add scripts to a project:**

```bash
cd ~/claude-dev-team
bash add-to-project.sh /path/to/your/project
```

**Keep up to date:**

```bash
cd ~/claude-dev-team && git pull
# Commands update automatically via symlinks.
# Re-run add-to-project.sh for each project to update scripts.
```

## How it works

`/task` is the CTO. You give it a requirement; it spawns `/autocode` to build it, then `/audit` to review it, then loops until the audit passes. All findings flow through a machine-readable `FINDINGS_JSON` contract. The audit uses four independent reviewers — including an unprimed adversarial agent (Red Agent R) that receives only the raw diff.

Quality gates are enforced at every step: mutation testing via Stryker, schema validation, pattern graduation tracking, and a pre-commit hook that blocks anti-patterns.
