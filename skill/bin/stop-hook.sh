#!/usr/bin/env bash
# Stop hook for the `goal` skill. Blocks stop if an active goal is in progress.
# Errors swallowed — never breaks a session.

GOAL_DIR="$PWD/.claude/goals"
MAX_RESUME="${GOAL_MAX_RESUME:-30}"

# Extract session_id from stdin JSON
SESSION_ID="$(sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
SESSION_ID="${SESSION_ID:-default}"

# Step 1: active goal exists?
[ -L "$GOAL_DIR/_active" ] || exit 0
TARGET="$(readlink -f "$GOAL_DIR/_active" 2>/dev/null)" || exit 0
[ -f "$TARGET" ] || exit 0

# Step 2: already archived?
BASENAME="$(basename "$TARGET")"
case "$BASENAME" in
  *.done.md|*.cleared.md|*.abandoned.md) exit 0 ;;
esac

# Step 3-4: per-session counter
COUNT_FILE="$GOAL_DIR/.stop-count.$SESSION_ID"
COUNT="$(cat "$COUNT_FILE" 2>/dev/null || echo 0)"
COUNT=$((COUNT + 1))
echo "$COUNT" > "$COUNT_FILE"

# Step 5: max exceeded?
if [ "$COUNT" -ge "$MAX_RESUME" ]; then
  echo "[goal] max resume count ($MAX_RESUME) reached — stopping. Reset with: rm $COUNT_FILE" >&2
  exit 0
fi

# Step 6: block the stop, inject re-entry prompt
SLUG="$(basename "$TARGET" .md)"
cat <<EOF
{"decision":"block","reason":"Re-read ./.claude/goals/$SLUG.md and continue from the next unchecked checkpoint. Run validation, log results, repeat."}
EOF
