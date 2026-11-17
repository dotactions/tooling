#!/usr/bin/env bash
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"
# shellcheck source=tests/workflow.sh
source "$(dirname "$0")/workflow.sh"
only_on linux
require_yaml_tool

WF="$REPO_ROOT/.github/workflows/floating-tags.yml"
VALIDATE=$(step_script "$WF" floating-tags "Validate inputs")
FLOAT=$(step_script "$WF" floating-tags "Update floating tags")

# The developer's own git config (signing, hooks) must not leak into the cases.
GITVARS=(GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1)
REAL_GIT=$(command -v git)
# Pushes land in the stub log and never leave the machine; every other git command is real.
stub git "if [ \"\$1\" = push ]; then exit 0; fi
exec \"$REAL_GIT\" \"\$@\""

g() { env "${GITVARS[@]}" "$REAL_GIT" -C "$WORK" "$@"; }
# Like a fresh runner checkout: no committer identity in the repo, so the step must set its own.
gi() { g -c user.name=test -c user.email=test@example.com "$@"; }
repo() {
  g init -q -b main
  gi commit -q --allow-empty -m init
}
at() { g rev-parse -q --verify "$1^{commit}" || true; }

# --- Validate inputs
for v in 1.2.0:1.2.0 v1.2.0:1.2.0 v1.3.0-rc.1:1.3.0-rc.1; do
  new_case
  run "$VALIDATE" VERSION="${v%%:*}"
  expect_ok "accepts ${v%%:*}"
  expect "${v%%:*} becomes ${v#*:}" "${v#*:}" "$(output version)"
done
for bad in release-1 vv1.0.0 1.0 ""; do
  new_case
  run "$VALIDATE" VERSION="$bad"
  expect_fail "rejects '$bad'" "is not a valid semver version"
done

# --- Update floating tags: the release tag must already exist (UI releases and release.yml both create it first)
new_case
repo
run "$FLOAT" "${GITVARS[@]}" VERSION=1.0.0
expect_fail "missing release tag" "Tag v1.0.0 does not exist"
expect "nothing is pushed for a missing tag" "" "$(stub_log | grep '^git push' || true)"

# --- Update floating tags: one repo, a sequence of releases on separate commits
new_case
repo
release() {
  gi commit -q --allow-empty -m "$1"
  gi tag -a "v$1" -m "v$1"
  # HEAD moves past the release tag, like main does after a release (the job checks out main, not the tag).
  gi commit -q --allow-empty -m "after v$1"
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
