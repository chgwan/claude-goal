#!/usr/bin/env bash
# SessionStart hook for the `goal` skill.
# Extracts session ID from stdin JSON and writes to .current-session.
# Errors swallowed — never breaks a session.

GOAL_DIR="$PWD/.claude/goals"

# Extract session_id from stdin JSON
SESSION_ID="$(sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
SESSION_ID="${SESSION_ID:-default}"

# Write current session ID for `goal new` to read
mkdir -p "$GOAL_DIR" 2>/dev/null
echo "$SESSION_ID" > "$GOAL_DIR/.current-session"

exit 0
