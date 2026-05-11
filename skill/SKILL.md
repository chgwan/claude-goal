---
name: goal
description: Use when the user invokes `/goal`, says "set a goal", "work until X passes", "keep iterating until", "don't stop until", or describes a long-running coding objective that names — or that the user can name on prompt — a concrete validation command. Not for open-ended refactors without a verifiable stop condition.
---

# Goal Mode

## Overview

Run long-running work as a contract, not a chat. Commit to one objective, one validation command, and one stopping condition — then iterate in checkpoints until validation passes or a real blocker is hit. No stopping on "I think it works."

Claude-Code analogue of Codex's `/goal`. Good for migrations, large refactors, eval-driven prompt tuning, polish-a-prototype, and retry loops.

## Scope and limits

This skill enforces discipline **within a single assistant turn**, not autonomous work across turns. Claude Code ends each turn and waits for the next user message — "work until done" is bounded by the turn, not by Codex-style background autonomy.

For cross-turn autonomy, a Stop hook automatically re-invokes the active goal when Claude stops mid-task. The hook reads `./.claude/goals/_active`, blocks the stop, and injects a re-entry prompt. A per-session counter file caps re-entries at 30 (configurable via `GOAL_MAX_RESUME`). When the goal is archived or replaced, counters reset. This gives you hours-long autonomous execution when combined with skip-permissions — the agent keeps re-engaging the goal until validation passes or the counter limit is hit.

## When to use

Trigger when:
- User invokes `/goal <objective>` or `/goal pause | resume | clear | status | done`
- User says: "set a goal", "work until X passes", "keep iterating until", "don't stop until", "grind on this"
- Task has a clear target, a way to validate progress, and enough room to advance without per-step steering

Do NOT use for:
- One-shot questions or single-file edits
- Open-ended exploration with no success criterion
- Bundles of unrelated todos (split into separate goals)

If the user's phrasing sounds long-running but no validation command or stop condition is named (e.g. "refactor this 200-line file into smaller functions"), do not enter goal mode silently. Ask: "What command or check should prove this is done?" If they can't name one, the work isn't a goal — it's open-ended editing.

## The five-field contract

Before any work, write down — concretely — all five:

1. **Objective** — one sentence, falsifiable.
2. **Constraints** — what must NOT change (files, APIs, perf budgets, deps).
3. **Inputs** — files, docs, issues, logs to read first.
4. **Validation** — exact command(s) or artifact(s) that prove progress or done.
5. **Stopping condition** — verifiable end state.

If any field is vague, ask the user before starting. Vague contract → vague work.

## Goal file

Write the contract to `./.claude/goals/<kebab-slug>.md`. One active file at a time. If `./.claude/goals/` doesn't exist, create it. When a goal is finished or replaced, rename to `<slug>.done.md` or `<slug>.cleared.md`.

State transitions on the goal file (create new, archive on done/clear/abandon) MUST go through the helper script at `__SKILL_ROOT__/bin/goal`:

- `goal new <slug>` — bootstraps from template, sets `_active` symlink. Refuses if another active goal exists.
- `goal archive <slug> <done|cleared|abandoned>` — renames file, clears `_active` if applicable.
- `goal active` — prints the active slug, or exits 1 silently.
- `goal list` — shows all goals grouped by status.

The agent edits goal-file *contents* (objective, constraints, progress log, checkpoint ticks) directly with Edit. The agent never creates, removes, or repoints the `_active` symlink by hand — only the helper does. This keeps the one-active-at-a-time invariant enforceable.

Template:

````markdown
# Goal: <one-line objective>

- **Status**: active | paused | done | blocked
- **Started**: <YYYY-MM-DD HH:MM>
- **Working dir**: <absolute path>

## Objective
<concrete, falsifiable>

## Constraints
- <do-not-change list>

## Inputs
- <files / docs / issues to read first>

## Validation
```bash
<command(s) that exit 0 on success>
```

## Stopping condition
<verifiable end state>

## Checkpoints
- [ ] <name> — <validation> — <status>

## Progress log
- <YYYY-MM-DD HH:MM> <checkpoint>: <what was verified, what remains, blockers>
````

## Slash forms

- `/goal <objective>` — start. Walk the user through the five fields, write the file, begin checkpoint 1.
- `/goal` (no args) — read active file, report current checkpoint, last verified, remaining work, blockers.
- `/goal pause` — set `Status: paused`, log reason, stop work.
- `/goal resume` — re-read the file, continue from next unchecked checkpoint.
- `/goal clear` — confirm with user, then archive to `<slug>.cleared.md`.
- `/goal done` — only after validation passes. Archive to `<slug>.done.md`.

If there are 0 active files, `/goal` with no args reports "no active goal". If there are 2+ (shouldn't happen), report all and ask which is current — archive the rest.

## Working loop

Per checkpoint:

1. Re-read the goal file. Confirm the next checkpoint and its validation.
2. Make the smallest change that could clear the checkpoint.
3. Run the validation command. Capture exit code and key output.
4. Append a one-line entry to the progress log.
5. Pass → tick the checkbox, move on. Fail → **diagnose root cause** (use `superpowers:systematic-debugging`), patch, re-run. "Intermittent / probably flaky" is a claim that requires evidence — repeat runs in isolation — not a vibe. No skipping ahead.
6. Repeat until the stopping condition is met.

Keep log entries short (one line each). The file is for grep, not narrative.

## Stopping discipline (strict)

Stop ONLY if:

- **Done** — stopping condition verifiably met (validation exited 0, invariants checked).
- **Blocked** — real external blocker: missing creds, ambiguous spec, destructive action needing user approval, decision only the user can make.
- **Paused** — explicit user pause.

Do NOT stop because:

- "I think it's working"
- "Feels like a good place to check in"
- "Tests pass locally but I didn't run the full validation"
- "Made progress, the rest is straightforward"
- "It's been a while, user might want an update"

If tempted to stop for any of the above: run the validation command instead. Output decides.

## When blocked

Write one message containing:

- Current checkpoint
- What you tried (terse)
- The exact decision the user must make
- The default you'll take if they don't reply

Then pause. Don't churn on a blocked decision.

## Common mistakes

| Mistake | Fix |
|---------|-----|
| Working before the contract is written | Write the file first. Five fields. |
| Validation = "looks right" | Must be a command that exits 0 or an artifact you can diff. If neither exists, ask the user to define one. |
| Long checkpoint with no validation in between | Break it down. Each checkpoint needs its own validation. |
| Log becomes a journal | One line per entry. Narrative goes in the user message, not the file. |
| Scope drift ("while I'm here…") | Constraints forbid it. New work → new goal, not silent expansion. |
| Stop at "I think it works" | Run validation. Output decides. |
| Multiple active goal files | One at a time. Archive the previous before starting a new one. |

## Red flags — STOP and re-read the contract

- About to say "I think this is done" without running validation
- About to edit a file the Constraints section excluded
- Progress log hasn't been updated in several edits
- Working from memory of the goal instead of re-reading the file
- Scope expanded and you haven't flagged it

All of these mean: stop, re-read `./.claude/goals/<slug>.md`, then either re-align or escalate to the user.
