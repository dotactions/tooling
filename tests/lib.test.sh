#!/usr/bin/env bash
# Tests the harness by running small test files that use it, so every consuming repo can trust a pass or fail.
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"
only_on linux macos windows

LIB="$REPO_ROOT/tests/lib.sh"

# harness <body>: runs a test file at $WORK/tests/inner.test.sh that sources lib.sh, then <body>.
harness() {
  new_case
  mkdir -p "$WORK/tests"
  printf 'source "%s"\n%s\n' "$LIB" "$1" > "$WORK/tests/inner.test.sh"
  run "$WORK/tests/inner.test.sh"
}
says() { grep -qF -- "$1" "$CASE_DIR/stdout" && echo yes; }

harness 'finish'
expect "a test file without assertions fails" "1" "$STATUS"
expect "and says why" "yes" "$(says "no assertions ran")"

harness 'expect same a a
finish'
expect_ok "a passing assertion passes"
expect "summary counts it" "yes" "$(says "1/1 passed in inner.test.sh")"

harness 'expect differs a b
finish'
expect "a failing assertion fails the file" "1" "$STATUS"
expect "failure shows expected and actual" "yes" "$(says "FAIL differs: expected 'a', got 'b'")"

harness 'only_on nowhere
expect never a b
finish'
expect_ok "only_on skips other OSes before any assertion"
expect "skip is reported" "yes" "$(says "skip inner.test.sh")"

# shellcheck disable=SC2016 # expands inside the inner test.
harness 'echo "$REPO_ROOT"
finish'
expect "REPO_ROOT is the repo of the test file, not of lib.sh" "yes" "$(says "$(cd "$WORK" && pwd)")"

# shellcheck disable=SC2016 # expands inside the inner test.
harness 'export LEAK=outer
printf "echo \"\${LEAK:-unset} \${GIVEN:-}\"\n" > "$TEST_TMP/s.sh"
new_case
run "$TEST_TMP/s.sh" GIVEN=passed
expect env "unset passed" "$(cat "$CASE_DIR/stdout")"
finish'
expect_ok "run hides the outer environment and passes VAR=val"

# shellcheck disable=SC2016 # expands inside the inner test.
harness 'printf "echo a=1 >> \"\$GITHUB_OUTPUT\"\necho a=2 >> \"\$GITHUB_OUTPUT\"\necho E=x >> \"\$GITHUB_ENV\"\n" > "$TEST_TMP/s.sh"
new_case
run "$TEST_TMP/s.sh"
expect last "2" "$(output a)"
expect env "x" "$(env_var E)"
finish'
expect_ok "output takes the last value; env_var reads GITHUB_ENV"

# shellcheck disable=SC2016 # expands inside the inner test.
harness 'printf "echo \"::error::bad thing\"\nexit 1\n" > "$TEST_TMP/s.sh"
new_case
run "$TEST_TMP/s.sh"
expect_fail matches "bad thing"
finish'
expect_ok "expect_fail passes on a matching ::error::"

# shellcheck disable=SC2016 # expands inside the inner test.
harness 'printf "echo \"::error::bad thing\"\nexit 1\n" > "$TEST_TMP/s.sh"
new_case
run "$TEST_TMP/s.sh"
expect_fail other "something else"
finish'
expect "expect_fail fails on a different ::error::" "1" "$STATUS"

# shellcheck disable=SC2016 # expands inside the inner test.
harness 'printf "exit 0\n" > "$TEST_TMP/s.sh"
new_case
run "$TEST_TMP/s.sh"
expect_fail exits0
finish'
expect "expect_fail fails when the script succeeds" "1" "$STATUS"

# shellcheck disable=SC2016 # expands inside the inner test.
harness 'stub tool "echo stubbed"
printf "tool a b\n" > "$TEST_TMP/s.sh"
new_case
run "$TEST_TMP/s.sh"
expect log "tool a b" "$(stub_log)"
expect body "stubbed" "$(cat "$CASE_DIR/stdout")"
finish'
expect_ok "stub logs its calls and runs its body"

# shellcheck disable=SC2016 # expands inside the inner test.
harness 'new_case
touch "$WORK/made"
expect_file there made
finish'
expect_ok "expect_file finds a file in WORK"

finish
