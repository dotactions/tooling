# shellcheck shell=bash
# Shared harness for tests/*.test.sh. Sourced, never executed.
# Must stay bash 3.2 compatible: macOS runners ship it.
#
# Each case: new_case; set up files in "$WORK"; run <script> [VAR=val ...]; assert.
set -euo pipefail

# $0 is the test file, so this is the consuming repo even when sourced from its .tooling submodule.
# shellcheck disable=SC2034 # used by the test files that source this.
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_TMP=$(mktemp -d)
trap 'rm -rf "$TEST_TMP"' EXIT
STUB_DIR="$TEST_TMP/stubs"
mkdir -p "$STUB_DIR"
ASSERTIONS=0
FAILURES=0
STATUS=0
CASE_DIR=""
WORK=""

# Exits 0 when the current OS is not listed, so a test only runs where its script runs in production.
only_on() {
  local os
  case "$(uname -s)" in
    Linux) os=linux ;;
    Darwin) os=macos ;;
    MINGW* | MSYS* | CYGWIN*) os=windows ;;
    *) os=unknown ;;
  esac
  case " $* " in
    *" $os "*) ;;
    *)
      echo "skip $(basename "$0"): not run on $os"
      exit 0
      ;;
  esac
}

new_case() {
  CASE_DIR=$(mktemp -d "$TEST_TMP/case.XXXXXX")
  WORK="$CASE_DIR/work"
  mkdir -p "$WORK"
}

# Runs a script inside $WORK with an emptied environment, so no variable leaks between cases or from CI.
# Only OS plumbing is passed through; everything else must be given as VAR=val.
run() {
  local script="$1" v
  shift
  local keep=("PATH=$STUB_DIR:$PATH")
  for v in HOME TMPDIR TEMP TMP LANG SYSTEMROOT WINDIR USERPROFILE APPDATA LOCALAPPDATA PROGRAMDATA PROGRAMFILES COMSPEC PATHEXT; do
    if [ -n "${!v:-}" ]; then keep+=("$v=${!v}"); fi
  done
  : > "$CASE_DIR/output"
  : > "$CASE_DIR/env"
  local cmd=(bash "$script")
  case "$script" in *.ps1) cmd=(pwsh -NoProfile -NonInteractive -File "$script") ;; esac
  set +e
  (cd "$WORK" && env -i "${keep[@]}" GITHUB_OUTPUT="$CASE_DIR/output" GITHUB_ENV="$CASE_DIR/env" \
    STUB_LOG="$CASE_DIR/stubs.log" "$@" "${cmd[@]}") > "$CASE_DIR/stdout" 2>&1
  STATUS=$?
  set -e
}

# Puts a fake <cmd> on PATH that logs "<cmd> <args>" to $STUB_LOG, then runs the optional body.
stub() {
  # shellcheck disable=SC2016 # $* and $STUB_LOG must expand inside the stub, not here.
  printf '#!/usr/bin/env bash\necho "%s $*" >> "$STUB_LOG"\n%s\n' "$1" "${2:-}" > "$STUB_DIR/$1"
  chmod +x "$STUB_DIR/$1"
}

output() { sed -n "s/^$1=//p" "$CASE_DIR/output" | tail -n 1; }
env_var() { sed -n "s/^$1=//p" "$CASE_DIR/env" | tail -n 1; }
stub_log() { cat "$CASE_DIR/stubs.log" 2> /dev/null || true; }

pass() {
  ASSERTIONS=$((ASSERTIONS + 1))
  echo "ok   $1"
}

fail() {
  ASSERTIONS=$((ASSERTIONS + 1))
  FAILURES=$((FAILURES + 1))
  echo "FAIL $1: $2"
  if [ -s "$CASE_DIR/stdout" ]; then sed 's/^/     | /' "$CASE_DIR/stdout"; fi
}

expect() {
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "expected '$2', got '$3'"; fi
}

expect_ok() {
  if [ "$STATUS" -eq 0 ]; then pass "$1"; else fail "$1" "exited $STATUS"; fi
}

# expect_fail <name> [substring that must appear in an ::error:: line]
expect_fail() {
  if [ "$STATUS" -eq 0 ]; then
    fail "$1" "expected failure, exited 0"
  elif [ -n "${2:-}" ] && ! grep '^::error::' "$CASE_DIR/stdout" | grep -qF -- "$2"; then
    fail "$1" "no ::error:: containing '$2'"
  else
    pass "$1"
  fi
}

expect_file() {
  if [ -f "$WORK/$2" ]; then pass "$1"; else fail "$1" "missing $2 (have: $(cd "$WORK" && find . -type f | tr '\n' ' '))"; fi
}

# A test file that never asserts must not pass silently.
finish() {
  if [ "$ASSERTIONS" -eq 0 ]; then
    echo "FAIL $(basename "$0"): no assertions ran"
    exit 1
  fi
  echo "$((ASSERTIONS - FAILURES))/$ASSERTIONS passed in $(basename "$0")"
  if [ "$FAILURES" -ne 0 ]; then exit 1; fi
}
