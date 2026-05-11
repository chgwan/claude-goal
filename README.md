# goal skill for Claude Code

A skill that turns long-running coding tasks into verifiable contracts with checkpoints, validation loops, and strict stopping discipline.

Inspired by Codex's `/goal` mode. Designed for migrations, large refactors, eval-driven prompt tuning, and any task where "I think it works" is not an acceptable stopping condition.

## What it does

- Defines a **five-field contract** per goal (Objective, Constraints, Inputs, Validation, Stopping condition)
- Maintains a **single active goal** per working directory via a symlink invariant
- Runs a **checkpoint-driven loop**: smallest change → validate → log → repeat
- Enforces **strict stopping discipline**: stop only on validation pass, real blocker, or user pause
- Persists state across sessions via a **SessionStart hook** that injects active-goal context
- **Auto-resumes** via a Stop hook that re-invokes the active goal when Claude stops mid-task (hours-long autonomy with skip-permissions)

## Quick start

```bash
cd ~/Codes/claude-goal
./install.sh
```

This installs the skill to `~/config.d/claude/skills/goal/` (default). To choose a different location:

```bash
./install.sh --prefix ~/my/skills/goal
```

Then restart Claude Code (or open `/hooks`) to activate the hooks.

## Using /goal

In Claude Code:

```
/goal migrate user auth to JWT
```

Claude walks you through the five-field contract, writes the goal file, and begins iterating. Each checkpoint has its own validation command. Claude does not stop until validation passes or it hits a real blocker.

| Command | What it does |
|---------|-------------|
| `/goal <objective>` | Start a new goal — walks through the five fields |
| `/goal` | Status — shows current checkpoint, what's done, what remains |
| `/goal pause` | Pause — set status to paused, log reason |
| `/goal resume` | Resume — re-read file, continue from next checkpoint |
| `/goal done` | Done — only after validation passes. Archives the goal |
| `/goal clear` | Clear — archive without completing |

## Helper script

The skill includes a bash helper at `bin/goal` with four verbs:

```bash
goal new <slug>                              # Create goal from template, set _active symlink
goal archive <slug> <done|cleared|abandoned> # Archive a goal, clear _active if applicable
goal active                                  # Print active slug (exit 1 if none)
goal list                                    # List all goals grouped by status
```

The agent calls this helper for state transitions (create, archive) and edits goal-file contents directly.

## File layout

```
claude-goal/
├── README.md                 # This file
├── install.sh                # Quick install script
├── skill/
│   ├── SKILL.md              # Skill definition (triggers, contract, discipline)
│   ├── template.md           # Goal file template with {{started}}/{{workdir}} tokens
│   └── bin/
│       ├── goal              # Helper script (4 verbs)
│       └── session-start.sh  # SessionStart hook (silent unless active goal exists)
│       ├── session-start.sh  # SessionStart hook (silent unless active goal exists)
│       └── stop-hook.sh      # Stop hook (auto-resumes active goal, per-session counter)
└── tests/
    └── test_goal.sh          # Smoke tests (30 tests)
```

## How goals are stored

Goals live per-project at `<workdir>/.claude/goals/`:

```
.claude/goals/
├── _active → jwt-migration.md      # Symlink (only one active at a time)
├── jwt-migration.md                # Active goal
├── old-refactor.done.md            # Archived — completed
├── experiment.cleared.md           # Archived — cleared without completing
└── dead-end.abandoned.md           # Archived — abandoned
```

## Architecture

Three layers:

1. **Skill source** — `SKILL.md` tells Claude when and how to use goal mode
2. **Helper script** — `bin/goal` manages state transitions and the symlink invariant
3. **Per-project state** — `./.claude/goals/` holds the contract files, scoped to the working directory

The helper is the only thing that touches the `_active` symlink. The agent edits file contents directly but never creates, removes, or repoints the symlink.

## Autonomous (hours-long) execution

Combine the goal skill with skip-permissions for unattended multi-hour runs:

1. Set up a goal: `/goal <objective>`
2. Enable skip-permissions (or run Claude Code with `--dangerously-skip-permissions`)
3. The Stop hook automatically re-invokes the active goal each time Claude stops
4. A per-session counter caps re-entries at 30 (configurable via `GOAL_MAX_RESUME`)
5. The agent keeps working until validation passes, it hits a real blocker, or the counter limit is hit

To break out: Ctrl+C. To reset the counter: `rm .claude/goals/.stop-count.*`

## Uninstall

```bash
rm -rf ~/config.d/claude/skills/goal    # Remove installed skill
rm ~/.claude/skills/goal                # Remove symlink
rm ~/.claude/commands/goal.md           # Remove slash command
# Then remove the SessionStart and Stop hooks from ~/.claude/settings.json
```

## Requirements

- Bash 4+, GNU coreutils (`grep`, `sed`, `ln`, `mv`, `readlink`, `date`)
- Python 3 (for `install.sh` settings.json manipulation)
- Claude Code with skill support
