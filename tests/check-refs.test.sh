#!/usr/bin/env bash
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"
# shellcheck source=tests/workflow.sh
source "$(dirname "$0")/workflow.sh"
only_on linux
require_yaml_tool

CHECK=$(step_script "$REPO_ROOT/.github/workflows/check-refs.yml" check-refs "Check references to dotactions repos")
SHA=0123456789abcdef0123456789abcdef01234567
GITVARS=(GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1)

# check <file> <content>: a repo for dotactions/flutter with known-good refs, plus <content> written to <file>.
check() {
  new_case
  mkdir -p "$WORK/.github/workflows" "$WORK/build"
  cat > "$WORK/.github/workflows/ci.yml" << EOF
uses: dotactions/flutter/build@main
uses: dotactions/node/setup@$SHA # v0.6.0
uses: dotactions/sarif-reporter@$SHA # v1.0.0
uses: actions/checkout@v4
EOF
  echo 'uses: dotactions/flutter/matrix@main' > "$WORK/build/action.yml"
  if [ -n "$1" ]; then
    mkdir -p "$WORK/$(dirname "$1")"
    echo "$2" >> "$WORK/$1"
  fi
  env "${GITVARS[@]}" git -C "$WORK" init -q
  env "${GITVARS[@]}" git -C "$WORK" add -A
  run "$CHECK" "${GITVARS[@]}" GITHUB_REPOSITORY=dotactions/flutter GITHUB_REPOSITORY_OWNER=dotactions
}

check "" ""
expect_ok "self @main, other repos by sha + version, third party untouched"

check action.yml "uses: dotactions/flutter@main"
expect_ok "root action self-reference @main"

check README.md "uses: dotactions/node/setup@v1"
expect_ok "README is not checked"

check build/action.yml "uses: dotactions/flutter/setup@v1"
expect_fail "self-reference by tag" "must use @main"

check .github/workflows/ci.yml "uses: dotactions/flutter/setup@$SHA # v1.0.0"
expect_fail "self-reference by sha" "must use @main"

check .github/workflows/ci.yml "uses: dotactions/node/setup@main"
expect_fail "other repo @main" "must be pinned"

check .github/workflows/ci.yml "uses: dotactions/node/setup@v0.6"
expect_fail "other repo by floating tag" "must be pinned"

check .github/workflows/ci.yml "uses: dotactions/node/setup@$SHA"
expect_fail "other repo sha without version comment" "must be pinned"

check .github/workflows/ci.yml "uses: dotactions/flutter-extra/x@main"
expect_fail "lookalike repo is another repo" "must be pinned"

check .github/workflows/x.yaml "uses: dotactions/node/setup@v1"
expect_fail ".yaml workflows are checked" "must be pinned"

check action.yaml "uses: dotactions/flutter/build@v1"
expect_fail "root action.yaml is checked" "must use @main"

finish
