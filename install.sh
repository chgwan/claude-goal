#!/usr/bin/env bash
# install.sh — install the goal skill into Claude Code.
# Usage: ./install.sh [--prefix <path>]
#   --prefix  Where to install the skill (default: ~/config.d/claude/skills/goal)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PREFIX="${HOME}/config.d/claude/skills/goal"

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix) PREFIX="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 [--prefix <path>]"
      echo "  Default prefix: ~/config.d/claude/skills/goal"
      exit 0
      ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

CLAUDE_DIR="$HOME/.claude"
COMMANDS_DIR="$CLAUDE_DIR/commands"
SETTINGS="$CLAUDE_DIR/settings.json"

echo "Installing goal skill..."
echo "  Prefix: $PREFIX"

# --- 1. Copy skill files ---
mkdir -p "$PREFIX/bin"
cp "$SCRIPT_DIR/skill/SKILL.md" "$PREFIX/SKILL.md"
cp "$SCRIPT_DIR/skill/template.md" "$PREFIX/template.md"
cp "$SCRIPT_DIR/skill/bin/goal" "$PREFIX/bin/goal"
cp "$SCRIPT_DIR/skill/bin/session-start.sh" "$PREFIX/bin/session-start.sh"
cp "$SCRIPT_DIR/skill/bin/stop-hook.sh" "$PREFIX/bin/stop-hook.sh"
chmod +x "$PREFIX/bin/goal" "$PREFIX/bin/session-start.sh" "$PREFIX/bin/stop-hook.sh"

# --- 2. Stamp paths ---
# Replace __SKILL_ROOT__ placeholders with the actual install prefix.
ESCAPED_PREFIX="$(echo "$PREFIX" | sed 's/[&/\]/\\&/g')"
sed -i "s|__SKILL_ROOT__|$ESCAPED_PREFIX|g" "$PREFIX/bin/goal"
sed -i "s|__SKILL_ROOT__|$ESCAPED_PREFIX|g" "$PREFIX/SKILL.md"

echo "  Stamped paths in bin/goal and SKILL.md"

# --- 3. Skill symlink ---
mkdir -p "$CLAUDE_DIR/skills"
if [ -L "$CLAUDE_DIR/skills/goal" ]; then
  rm "$CLAUDE_DIR/skills/goal"
elif [ -e "$CLAUDE_DIR/skills/goal" ]; then
  echo "  WARNING: $CLAUDE_DIR/skills/goal exists and is not a symlink — skipping"
  echo "  Remove it manually if you want the symlink."
fi
[ ! -e "$CLAUDE_DIR/skills/goal" ] && ln -s "$PREFIX" "$CLAUDE_DIR/skills/goal"
echo "  Linked $CLAUDE_DIR/skills/goal → $PREFIX"

# --- 4. Slash command ---
mkdir -p "$COMMANDS_DIR"
cat > "$COMMANDS_DIR/goal.md" <<'CMDEOF'
---
description: Set or manage a long-running goal with a verifiable stop condition.
---

Invoke the `goal` skill. User input: $ARGUMENTS
CMDEOF
echo "  Created $COMMANDS_DIR/goal.md"

# --- 5. SessionStart hook in settings.json ---
mkdir -p "$CLAUDE_DIR"

if [ ! -f "$SETTINGS" ]; then
  echo '{}' > "$SETTINGS"
fi

# Check if hook already exists
if python3 -c "
import json, sys
s = json.load(open('$SETTINGS'))
hooks = s.get('hooks', {}).get('SessionStart', [])
for h in hooks:
    for hook in h.get('hooks', []):
        if 'session-start.sh' in hook.get('command', ''):
            sys.exit(0)
sys.exit(1)
" 2>/dev/null; then
  echo "  SessionStart hook already registered — skipping"
else
  python3 -c "
import json
path = '$SETTINGS'
s = json.load(open(path))
s.setdefault('hooks', {})
s['hooks'].setdefault('SessionStart', [])
s['hooks']['SessionStart'].append({
    'hooks': [{
        'type': 'command',
        'command': '$PREFIX/bin/session-start.sh'
    }]
})
with open(path, 'w') as f:
    json.dump(s, f, indent=2)
    f.write('\n')
"
  echo "  Registered SessionStart hook in $SETTINGS"
fi

# --- 5b. Stop hook in settings.json ---
if python3 -c "
import json, sys
s = json.load(open('$SETTINGS'))
hooks = s.get('hooks', {}).get('Stop', [])
for h in hooks:
    for hook in h.get('hooks', []):
        if 'stop-hook.sh' in hook.get('command', ''):
            sys.exit(0)
sys.exit(1)
" 2>/dev/null; then
  echo "  Stop hook already registered — skipping"
else
  python3 -c "
import json
path = '$SETTINGS'
s = json.load(open(path))
s.setdefault('hooks', {})
s['hooks'].setdefault('Stop', [])
s['hooks']['Stop'].append({
    'hooks': [{
        'type': 'command',
        'command': '$PREFIX/bin/stop-hook.sh'
    }]
})
with open(path, 'w') as f:
    json.dump(s, f, indent=2)
    f.write('\n')
"
  echo "  Registered Stop hook in $SETTINGS"
fi

# --- 6. Run tests ---
echo
echo "Running tests..."
GOAL_BIN="$PREFIX/bin/goal" bash "$SCRIPT_DIR/tests/test_goal.sh"
echo
echo "Done. The /goal command is ready."
echo "Restart Claude Code (or open /hooks) to activate the SessionStart hook."
