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
FLOAT=$(step_script "$WF" release "Update floating tags")

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

# --- Ensure tag does not exist
new_case
repo
g tag -a v1.0.0 -m v1.0.0
run "$EXISTS" "${GITVARS[@]}" VERSION=1.0.0
expect_fail "existing tag" "Tag v1.0.0 already exists"
run "$EXISTS" "${GITVARS[@]}" VERSION=1.0.1
expect_ok "new tag"

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
new_case
run "$RELEASE" VERSION=1.0.0-rc.1 GH_TOKEN=x
expect "pre-release is marked" "gh release create v1.0.0-rc.1 --verify-tag --generate-notes --title v1.0.0-rc.1 --prerelease" "$(stub_log)"
new_case
run "$RELEASE" VERSION=1.0.0 GH_TOKEN=x
expect "stable release is not marked" "gh release create v1.0.0 --verify-tag --generate-notes --title v1.0.0" "$(stub_log)"

# --- Update floating tags: one repo, a sequence of releases on separate commits
new_case
repo
release() {
  g commit -q --allow-empty -m "$1"
  g tag -a "v$1" -m "v$1"
  run "$FLOAT" "${GITVARS[@]}" VERSION="$1"
}
release 0.5.0
expect "0.5.0 moves v0" "$(at v0.5.0)" "$(at v0)"
expect "0.5.0 moves v0.5" "$(at v0.5.0)" "$(at v0.5)"
release 0.6.0
expect "0.6.0 moves v0" "$(at v0.6.0)" "$(at v0)"
release 0.5.1
expect_ok "older release exits 0"
expect "0.5.1 leaves v0 on 0.6.0" "$(at v0.6.0)" "$(at v0)"
expect "0.5.1 moves v0.5" "$(at v0.5.1)" "$(at v0.5)"
expect "skipped tag is explained" "yes" "$(grep -q '::notice::Not moving v0' "$CASE_DIR/stdout" && echo yes)"
release 1.0.0
expect "1.0.0 moves v1" "$(at v1.0.0)" "$(at v1)"
expect "1.0.0 leaves v0 alone" "$(at v0.6.0)" "$(at v0)"
expect "no minor tag floats after 0.x" "" "$(at v1.0)"
release 1.1.0-rc.1
expect "pre-release moves nothing" "$(at v1.0.0)" "$(at v1)"
expect "floating tags are force-pushed" "git push origin v1 --force" "$(stub_log | grep '^git push' | tail -n 1)"

finish
