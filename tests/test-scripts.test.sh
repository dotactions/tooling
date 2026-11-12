#!/usr/bin/env bash
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"
# shellcheck source=tests/workflow.sh
source "$(dirname "$0")/workflow.sh"
only_on linux
require_yaml_tool

LOOP=$(step_script "$REPO_ROOT/.github/workflows/test-scripts.yml" test-scripts "Run tests/*.test.sh")

# with_tests <name:exit code>...: a repo whose tests/<name>.test.sh exit with the given codes.
with_tests() {
  new_case
  mkdir -p "$WORK/tests"
  local t
  for t in "$@"; do
    printf 'echo "ran %s"\nexit %s\n' "${t%%:*}" "${t#*:}" > "$WORK/tests/${t%%:*}.test.sh"
  done
  run "$LOOP"
}

with_tests
expect_fail "no tests is an error, not a silent pass" "No tests/*.test.sh found"

with_tests a:0 b:0
expect_ok "all passing"

with_tests a:1 b:0
expect "one failure fails the run" "1" "$STATUS"
expect "tests after a failure still run" "yes" "$(grep -q '^ran b$' "$CASE_DIR/stdout" && echo yes)"
expect "each test gets a log group" "2" "$(grep -c '^::group::tests/' "$CASE_DIR/stdout")"

finish
