#!/usr/bin/env bash
# SessionStart hook for the `goal` skill. Silent unless ./.claude/goals/_active resolves.
# Errors swallowed — never breaks a session.

ACTIVE="$PWD/.claude/goals/_active"
[ -L "$ACTIVE" ] || exit 0
TARGET="$(readlink -f "$ACTIVE" 2>/dev/null)" || exit 0
[ -f "$TARGET" ] || exit 0

SLUG="$(basename "$TARGET" .md)"
STATUS="$(grep -m1 '^- \*\*Status\*\*:' "$TARGET" 2>/dev/null | sed 's/.*Status\*\*: //' || echo unknown)"
DONE="$(grep -c '^- \[x\]' "$TARGET" 2>/dev/null || true)"
TOTAL="$(grep -cE '^- \[[ x]\]' "$TARGET" 2>/dev/null || true)"
DONE="${DONE:-0}"
TOTAL="${TOTAL:-0}"

echo "[goal] active: $SLUG (status: $STATUS, $DONE/$TOTAL ckpts) — re-read ./.claude/goals/$SLUG.md before acting."
exit 0
