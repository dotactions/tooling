#!/usr/bin/env bash
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"
# shellcheck source=tests/workflow.sh
source "$(dirname "$0")/workflow.sh"
only_on linux
require_yaml_tool

WF="$REPO_ROOT/.github/workflows/release.yml"
VALIDATE=$(step_script "$WF" release "Validate inputs")
EXISTS=$(step_script "$WF" release "Ensure tag does not exist")
PIN=$(step_script "$WF" release "Pin self-references to the release tag")
COMMIT=$(step_script "$WF" release "Commit, tag and push")
RELEASE=$(step_script "$WF" release "Create GitHub release")

# The developer's own git config (signing, hooks) must not leak into the cases.
GITVARS=(GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1)
REAL_GIT=$(command -v git)
# Pushes land in the stub log and never leave the machine; every other git command is real.
stub git "if [ \"\$1\" = push ]; then exit 0; fi
exec \"$REAL_GIT\" \"\$@\""
stub gh

g() { env "${GITVARS[@]}" "$REAL_GIT" -C "$WORK" "$@"; }
repo() {
  g init -q -b main
  g config user.name test
  g config user.email test@example.com
  g commit -q --allow-empty -m init
}
at() { g rev-parse -q --verify "$1^{commit}" || true; }

# --- Validate inputs
validate() {
  new_case
  run "$VALIDATE" GITHUB_REF=refs/heads/main VERSION="$1"
}
for v in 1.0.0:1.0.0 v1.0.0:1.0.0 v0.1.0-rc.1:0.1.0-rc.1; do
  validate "${v%%:*}"
  expect_ok "accepts ${v%%:*}"
  expect "${v%%:*} becomes ${v#*:}" "${v#*:}" "$(output version)"
done
for bad in vv1.0.0 V1.0.0 1.0 1.0.0.0 ""; do
  validate "$bad"
  expect_fail "rejects '$bad'" "is not a valid semver version"
done
new_case
run "$VALIDATE" GITHUB_REF=refs/heads/feature VERSION=1.0.0
expect_fail "rejects a branch other than main" "Releases must be cut from main"
for v in 0.9.0:v0.9.0 v0.9.0:v0.9.0; do
  new_case
  run "$VALIDATE" GITHUB_REF=refs/heads/main VERSION=1.0.0 PREVIOUS_TAG="${v%%:*}"
  expect "previous-tag ${v%%:*} becomes ${v#*:}" "${v#*:}" "$(output previous-tag)"
done
new_case
run "$VALIDATE" GITHUB_REF=refs/heads/main VERSION=1.0.0 PREVIOUS_TAG=main
expect_fail "rejects a non-semver previous-tag" "previous-tag 'main' is not a valid semver tag"
new_case
run "$VALIDATE" GITHUB_REF=refs/heads/main VERSION=1.0.0
expect "no previous-tag output by default" "" "$(output previous-tag)"

# --- Ensure tag does not exist
new_case
repo
g tag -a v1.0.0 -m v1.0.0
run "$EXISTS" "${GITVARS[@]}" VERSION=1.0.0
expect_fail "existing tag" "Tag v1.0.0 already exists"
run "$EXISTS" "${GITVARS[@]}" VERSION=1.0.1
expect_ok "new tag"
run "$EXISTS" "${GITVARS[@]}" VERSION=1.0.1 PREVIOUS_TAG=v1.0.0
expect_ok "existing previous-tag"
run "$EXISTS" "${GITVARS[@]}" VERSION=1.0.1 PREVIOUS_TAG=v0.9.0
expect_fail "missing previous-tag" "previous-tag v0.9.0 does not exist"

# --- Pin self-references
SHA=0123456789abcdef0123456789abcdef01234567
new_case
repo
mkdir -p "$WORK/.github/workflows" "$WORK/build"
cat > "$WORK/.github/workflows/ci.yml" << EOF
uses: dotactions/flutter/build@main
uses: dotactions/flutter/.github/workflows/cd.yml@main
uses: dotactions/flutter-extra/x@main
uses: dotactions/node/setup@$SHA # v0.6.0
EOF
echo 'uses: dotactions/flutter/setup@main' > "$WORK/.github/workflows/other.yaml"
echo 'uses: dotactions/flutter/matrix@main' > "$WORK/build/action.yml"
echo 'uses: dotactions/flutter@main' > "$WORK/action.yaml"
echo 'uses: dotactions/flutter/build@main' > "$WORK/README.md"
g add -A
g commit -q -m files
run "$PIN" "${GITVARS[@]}" VERSION=1.2.3 GITHUB_REPOSITORY=dotactions/flutter
expect_ok "pin exits 0"
expect "workflow self-references pinned, lookalike and other repos untouched" "uses: dotactions/flutter/build@v1.2.3
uses: dotactions/flutter/.github/workflows/cd.yml@v1.2.3
uses: dotactions/flutter-extra/x@main
uses: dotactions/node/setup@$SHA # v0.6.0" "$(cat "$WORK/.github/workflows/ci.yml")"
expect ".yaml workflow pinned" "uses: dotactions/flutter/setup@v1.2.3" "$(cat "$WORK/.github/workflows/other.yaml")"
expect "nested action.yml pinned" "uses: dotactions/flutter/matrix@v1.2.3" "$(cat "$WORK/build/action.yml")"
expect "root action.yaml pinned" "uses: dotactions/flutter@v1.2.3" "$(cat "$WORK/action.yaml")"
expect "README is never rewritten" "uses: dotactions/flutter/build@main" "$(cat "$WORK/README.md")"

# --- Commit, tag and push
new_case
repo
echo before > "$WORK/file"
g add file
g commit -q -m file
echo after > "$WORK/file"
run "$COMMIT" "${GITVARS[@]}" VERSION=1.2.3
expect_ok "commit exits 0"
expect "release commit message" "chore(release): v1.2.3" "$(g log -1 --format=%s v1.2.3)"
expect "release commit holds the rewrite" "after" "$(g show v1.2.3:file)"
expect "tag is annotated" "tag" "$(g cat-file -t v1.2.3)"
expect "main is untouched" "file" "$(g log -1 --format=%s main)"
expect "only the tag is pushed" "git push origin v1.2.3" "$(stub_log | grep '^git push')"

# --- Create GitHub release
gh_call() { stub_log | grep '^gh '; }
new_case
repo
run "$RELEASE" "${GITVARS[@]}" VERSION=1.0.0-rc.1 GH_TOKEN=x
expect "pre-release is marked" "gh release create v1.0.0-rc.1 --verify-tag --generate-notes --title v1.0.0-rc.1 --prerelease" "$(gh_call)"
new_case
repo
run "$RELEASE" "${GITVARS[@]}" VERSION=1.0.0 GH_TOKEN=x
expect "stable release is not marked" "gh release create v1.0.0 --verify-tag --generate-notes --title v1.0.0" "$(gh_call)"

# Release notes start at the highest stable tag below the new version; floating and pre-release tags never count.
new_case
repo
for t in v0.9.0 v0.10.0 v1.2.0 v1.3.0 v2.0.0-rc.1 v0 v0.10 v1 v1.3; do g tag "$t"; done
notes_start() {
  g tag -f "v$1" > /dev/null
  : > "$CASE_DIR/stubs.log"
  run "$RELEASE" "${GITVARS[@]}" VERSION="$1" PREVIOUS_TAG="${2:-}" GH_TOKEN=x
  gh_call | sed -n 's/.*--notes-start-tag \([^ ]*\).*/\1/p'
  g tag -d "v$1" > /dev/null
}
expect "patch starts at previous patch line" "v1.3.0" "$(notes_start 1.3.1)"
expect "hotfix on an older line skips newer tags" "v1.2.0" "$(notes_start 1.2.1)"
expect "versions sort numerically, not lexically" "v0.10.0" "$(notes_start 1.0.0)"
expect "pre-release starts at the last stable" "v1.3.0" "$(notes_start 2.0.0-rc.2)"
expect "stable after an rc skips the rc" "v1.3.0" "$(notes_start 2.0.0)"
expect "first release has no start tag" "" "$(notes_start 0.1.0)"
expect "previous-tag overrides the computed start" "v0.9.0" "$(notes_start 1.3.1 v0.9.0)"

finish
