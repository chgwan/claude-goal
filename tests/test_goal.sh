#!/usr/bin/env bash
# Smoke tests for the `goal` helper. Run from anywhere.
# Each test is isolated in a fresh tmp dir. set -u (not -e) so failures are captured.

set -u

GOAL_BIN="${GOAL_BIN:-$HOME/config.d/claude/skills/goal/bin/goal}"
STOP_HOOK_BIN="${STOP_HOOK_BIN:-$HOME/config.d/claude/skills/goal/bin/stop-hook.sh}"

# Counter files so subshell test blocks can update totals.
_PASS_FILE="$(mktemp -t goal-pass.XXXXXX)"
_FAIL_FILE="$(mktemp -t goal-fail.XXXXXX)"
echo 0 > "$_PASS_FILE"; echo 0 > "$_FAIL_FILE"
trap "rm -f '$_PASS_FILE' '$_FAIL_FILE'" EXIT

pass() {
  echo "  PASS: $*"
  local n; n=$(cat "$_PASS_FILE"); echo $((n + 1)) > "$_PASS_FILE"
}
fail() {
  echo "  FAIL: $*"
  local n; n=$(cat "$_FAIL_FILE"); echo $((n + 1)) > "$_FAIL_FILE"
}

# Each test sets up its own tmp cwd and is responsible for cleanup via trap.
mk_test_dir() {
  local d
  d="$(mktemp -d -t goal-test.XXXXXX)"
  echo "$d"
}

# ---- tests go below ----

# T1: active with no _active → exit 1, silent
( d="$(mk_test_dir)"; trap "rm -rf $d" EXIT; cd "$d"
  out="$("$GOAL_BIN" active 2>&1)"; rc=$?
  if [ "$rc" = "1" ] && [ -z "$out" ]; then pass "T1: active empty → exit 1, silent"
  else fail "T1: active empty (rc=$rc, out='$out')"; fi
)

# T2: new <slug> creates file + symlink
( d="$(mk_test_dir)"; trap "rm -rf $d" EXIT; cd "$d"
  "$GOAL_BIN" new test-mig >/dev/null 2>&1 || { fail "T2: new exit"; exit; }
  [ -f .claude/goals/test-mig.md ] || { fail "T2: file missing"; exit; }
  [ -L .claude/goals/_active ] || { fail "T2: symlink missing"; exit; }
  [ "$(readlink .claude/goals/_active)" = "test-mig.md" ] || { fail "T2: symlink wrong target"; exit; }
  pass "T2: new creates file + relative symlink"
)

# T3: new prints slug via active afterwards
( d="$(mk_test_dir)"; trap "rm -rf $d" EXIT; cd "$d"
  "$GOAL_BIN" new test-mig >/dev/null
  out="$("$GOAL_BIN" active)"
  [ "$out" = "test-mig" ] && pass "T3: active prints slug" || fail "T3: got '$out'"
)

# T4: new refuses a second active goal (exit 4)
( d="$(mk_test_dir)"; trap "rm -rf $d" EXIT; cd "$d"
  "$GOAL_BIN" new first >/dev/null
  "$GOAL_BIN" new second >/dev/null 2>&1; rc=$?
  [ "$rc" = "4" ] && pass "T4: second new → exit 4" || fail "T4: rc=$rc"
  [ ! -f .claude/goals/second.md ] && pass "T4: no leak" || fail "T4: second.md leaked"
)

# T5: new refuses invalid slug (exit 5)
( d="$(mk_test_dir)"; trap "rm -rf $d" EXIT; cd "$d"
  "$GOAL_BIN" new BadSlug >/dev/null 2>&1; rc=$?
  [ "$rc" = "5" ] && pass "T5: bad slug → exit 5" || fail "T5: rc=$rc"
)

# T6: new refuses if file already exists (exit 3)
( d="$(mk_test_dir)"; trap "rm -rf $d" EXIT; cd "$d"
  mkdir -p .claude/goals && touch .claude/goals/existing.md
  "$GOAL_BIN" new existing >/dev/null 2>&1; rc=$?
  [ "$rc" = "3" ] && pass "T6: existing file → exit 3" || fail "T6: rc=$rc"
)

# T7: new substitutes {{started}} and {{workdir}}
( d="$(mk_test_dir)"; trap "rm -rf $d" EXIT; cd "$d"
  "$GOAL_BIN" new sub-test >/dev/null
  if grep -q "{{started}}" .claude/goals/sub-test.md; then fail "T7: {{started}} not substituted"; else pass "T7: {{started}} substituted"; fi
  if grep -q "{{workdir}}" .claude/goals/sub-test.md; then fail "T7: {{workdir}} not substituted"; else pass "T7: {{workdir}} substituted"; fi
  grep -q "Working dir.*$d" .claude/goals/sub-test.md && pass "T7: workdir value correct" || fail "T7: workdir value"
)

# T8: archive done → rename + clear symlink
( d="$(mk_test_dir)"; trap "rm -rf $d" EXIT; cd "$d"
  "$GOAL_BIN" new mig >/dev/null
  "$GOAL_BIN" archive mig done >/dev/null 2>&1 || { fail "T8: archive exit"; exit; }
  [ -f .claude/goals/mig.done.md ] && pass "T8: renamed to .done.md" || fail "T8: rename"
  [ ! -L .claude/goals/_active ] && pass "T8: symlink cleared" || fail "T8: symlink leak"
)

# T9: archive cleared → cleared suffix
( d="$(mk_test_dir)"; trap "rm -rf $d" EXIT; cd "$d"
  "$GOAL_BIN" new mig >/dev/null
  "$GOAL_BIN" archive mig cleared >/dev/null
  [ -f .claude/goals/mig.cleared.md ] && pass "T9: .cleared.md" || fail "T9"
)

# T10: archive abandoned → abandoned suffix
( d="$(mk_test_dir)"; trap "rm -rf $d" EXIT; cd "$d"
  "$GOAL_BIN" new mig >/dev/null
  "$GOAL_BIN" archive mig abandoned >/dev/null
  [ -f .claude/goals/mig.abandoned.md ] && pass "T10: .abandoned.md" || fail "T10"
)

# T11: archive bad status → exit 7
( d="$(mk_test_dir)"; trap "rm -rf $d" EXIT; cd "$d"
  "$GOAL_BIN" new mig >/dev/null
  "$GOAL_BIN" archive mig zzz >/dev/null 2>&1; rc=$?
  [ "$rc" = "7" ] && pass "T11: bad status → exit 7" || fail "T11: rc=$rc"
)

# T12: archive missing slug → exit 6
( d="$(mk_test_dir)"; trap "rm -rf $d" EXIT; cd "$d"
  mkdir -p .claude/goals
  "$GOAL_BIN" archive ghost done >/dev/null 2>&1; rc=$?
  [ "$rc" = "6" ] && pass "T12: missing slug → exit 6" || fail "T12: rc=$rc"
)

# T13: archive does NOT clear _active if it points to a different slug
( d="$(mk_test_dir)"; trap "rm -rf $d" EXIT; cd "$d"
  "$GOAL_BIN" new mig >/dev/null
  # Create a second goal file manually (no symlink change)
  touch .claude/goals/other.md
  "$GOAL_BIN" archive other done >/dev/null
  [ -L .claude/goals/_active ] && pass "T13: _active preserved" || fail "T13: _active wrongly removed"
)

# T14: list on empty dir → "no goals"
( d="$(mk_test_dir)"; trap "rm -rf $d" EXIT; cd "$d"
  out="$("$GOAL_BIN" list)"
  [ "$out" = "no goals" ] && pass "T14: list empty" || fail "T14: got '$out'"
)

# T15: list shows ACTIVE, DONE, CLR, ABDN groups
( d="$(mk_test_dir)"; trap "rm -rf $d" EXIT; cd "$d"
  "$GOAL_BIN" new act >/dev/null
  touch .claude/goals/d1.done.md .claude/goals/c1.cleared.md .claude/goals/a1.abandoned.md
  out="$("$GOAL_BIN" list)"
  echo "$out" | grep -q "^ACTIVE.*act" && pass "T15a: ACTIVE" || fail "T15a: ACTIVE missing in '$out'"
  echo "$out" | grep -q "^DONE.*d1" && pass "T15b: DONE" || fail "T15b: DONE missing"
  echo "$out" | grep -q "^CLR.*c1" && pass "T15c: CLR" || fail "T15c: CLR missing"
  echo "$out" | grep -q "^ABDN.*a1" && pass "T15d: ABDN" || fail "T15d: ABDN missing"
)

# T16: stop hook allows stop when no active goal
( d="$(mk_test_dir)"; trap "rm -rf $d" EXIT; cd "$d"
  out="$(echo '{"session_id":"t16"}' | "$STOP_HOOK_BIN")"; rc=$?
  if [ "$rc" = "0" ] && [ -z "$out" ]; then pass "T16: stop hook no goal → exit 0, silent"
  else fail "T16: (rc=$rc, out='$out')"; fi
)

# T17: stop hook blocks when active goal exists
( d="$(mk_test_dir)"; trap "rm -rf $d" EXIT; cd "$d"
  "$GOAL_BIN" new stop-test >/dev/null
  out="$(echo '{"session_id":"t17"}' | "$STOP_HOOK_BIN")"; rc=$?
  if [ "$rc" = "0" ]; then pass "T17: stop hook exit 0"
  else fail "T17: rc=$rc"; fi
  echo "$out" | grep -q '"decision":"block"' && pass "T17: decision=block" || fail "T17: no block in '$out'"
  echo "$out" | grep -q 'stop-test' && pass "T17: slug in reason" || fail "T17: slug missing"
)

# T18: stop hook allows stop when counter >= GOAL_MAX_RESUME
( d="$(mk_test_dir)"; trap "rm -rf $d" EXIT; cd "$d"
  "$GOAL_BIN" new max-test >/dev/null
  echo 3 > .claude/goals/.stop-count.t18
  out="$(echo '{"session_id":"t18"}' | GOAL_MAX_RESUME=3 "$STOP_HOOK_BIN" 2>&1)"; rc=$?
  if [ "$rc" = "0" ]; then pass "T18: allows stop at max"
  else fail "T18: rc=$rc"; fi
  echo "$out" | grep -q "max resume" && pass "T18: warning printed" || fail "T18: no warning in '$out'"
)

# T19: goal new removes all .stop-count.* files
( d="$(mk_test_dir)"; trap "rm -rf $d" EXIT; cd "$d"
  "$GOAL_BIN" new first >/dev/null
  echo 5 > .claude/goals/.stop-count.stale1
  echo 5 > .claude/goals/.stop-count.stale2
  "$GOAL_BIN" archive first done >/dev/null
  "$GOAL_BIN" new second >/dev/null
  found="$(ls .claude/goals/.stop-count.* 2>/dev/null | wc -l)"
  [ "$found" = "0" ] && pass "T19: new clears counters" || fail "T19: $found counter files remain"
)

# T20: goal archive removes all .stop-count.* files
( d="$(mk_test_dir)"; trap "rm -rf $d" EXIT; cd "$d"
  "$GOAL_BIN" new arc-test >/dev/null
  echo 5 > .claude/goals/.stop-count.s1
  echo 5 > .claude/goals/.stop-count.s2
  "$GOAL_BIN" archive arc-test done >/dev/null
  found="$(ls .claude/goals/.stop-count.* 2>/dev/null | wc -l)"
  [ "$found" = "0" ] && pass "T20: archive clears counters" || fail "T20: $found counter files remain"
)

# ---- summary ----
PASS=$(cat "$_PASS_FILE"); FAIL=$(cat "$_FAIL_FILE")
echo
echo "Total: $((PASS + FAIL))    Pass: $PASS    Fail: $FAIL"
[ "$FAIL" -eq 0 ]
