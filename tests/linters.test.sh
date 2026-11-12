#!/usr/bin/env bash
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"
# shellcheck source=tests/workflow.sh
source "$(dirname "$0")/workflow.sh"
only_on linux
require_yaml_tool
if ! docker info > /dev/null 2>&1; then
  echo "skip $(basename "$0"): docker not available (it is on ubuntu runners)"
  exit 0
fi

ACTIONLINT_WF="$REPO_ROOT/.github/workflows/actionlint.yml"
LINT_WF="$REPO_ROOT/.github/workflows/lint.yml"
ACTIONLINT=$(step_script "$ACTIONLINT_WF" actionlint "Run actionlint")
SHELLCHECK=$(step_script "$LINT_WF" shellcheck "Run ShellCheck")
ACTIONLINT_IMAGE=$(step_field "$ACTIONLINT_WF" actionlint "Run actionlint" env.ACTIONLINT_IMAGE)
SHELLCHECK_IMAGE=$(step_field "$LINT_WF" shellcheck "Run ShellCheck" env.ACTIONLINT_IMAGE)

expect "both workflows pin the same image" "$ACTIONLINT_IMAGE" "$SHELLCHECK_IMAGE"

GITVARS=(GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1)
DOCKERVARS=()
if [ -n "${DOCKER_HOST:-}" ]; then DOCKERVARS=(DOCKER_HOST="$DOCKER_HOST"); fi

# put <path> <content>: a tracked file in $WORK, since both linters only see git-tracked files.
put() {
  mkdir -p "$WORK/$(dirname "$1")"
  printf '%s\n' "$2" > "$WORK/$1"
  env "${GITVARS[@]}" git -C "$WORK" init -q
  env "${GITVARS[@]}" git -C "$WORK" add "$1"
}
lint() { run "$1" "${GITVARS[@]}" "${DOCKERVARS[@]}" ACTIONLINT_IMAGE="$ACTIONLINT_IMAGE"; }
stdout_has() { grep -qE -- "$1" "$CASE_DIR/stdout" && echo yes; }

# --- actionlint
new_case
put .github/workflows/ok.yml 'on: push
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - run: echo ok'
lint "$ACTIONLINT"
expect_ok "clean workflow passes"

new_case
# shellcheck disable=SC2016 # the ${{ }} is the workflow under test, not bash.
put .github/workflows/bad.yml 'on: push
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - run: echo ${{ github.nope }}'
lint "$ACTIONLINT"
expect "broken workflow fails" "yes" "$([ "$STATUS" -ne 0 ] && echo yes)"
expect "error is a file/line annotation" "yes" "$(stdout_has '^::error file=\.github/workflows/bad\.yml,line=6,col=[0-9]+::')"

# --- ShellCheck
new_case
mkdir -p "$WORK/lib"
# Like .tooling/tests/lib.sh in a consumer: on disk but untracked, so only -x makes ShellCheck follow it.
# shellcheck disable=SC2016 # the script under test, not this one.
printf '%s\n' '# shellcheck shell=bash' 'greet() { echo "hi $1"; }' > "$WORK/lib/helper.sh"
# shellcheck disable=SC2016 # the script under test, not this one.
put main.sh '#!/usr/bin/env bash
# shellcheck source=lib/helper.sh
source "$(dirname "$0")/lib/helper.sh"
greet "$@"'
lint "$SHELLCHECK"
expect_ok "untracked sourced file is followed (-x)"

new_case
# shellcheck disable=SC2016 # the script under test, not this one.
put bad.sh '#!/usr/bin/env bash
echo $1'
lint "$SHELLCHECK"
expect "unquoted variable fails" "yes" "$([ "$STATUS" -ne 0 ] && echo yes)"
expect "finding names the rule" "yes" "$(stdout_has 'SC2086')"

new_case
# shellcheck disable=SC2016 # the script under test, not this one.
put tests/fixtures/bad.sh '#!/usr/bin/env bash
echo $1'
lint "$SHELLCHECK"
expect_ok "tests/fixtures is skipped"

new_case
put README.md 'no scripts here'
lint "$SHELLCHECK"
expect_ok "repo without scripts passes"

finish
