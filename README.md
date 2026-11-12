# dotactions/tooling

Shared CI for the `dotactions/*` repos: reusable workflows plus the shell test harness. Not intended for use outside the org.

| Workflow | Does | Caller job needs |
| :--- | :--- | :--- |
| `release.yml` | Rewrites the caller's `@main` self-references to `@v<version>` in a release commit, tags it, creates the GitHub release, moves `v<major>` (and `v0.<minor>` during `0.x`) forward only | `secrets: inherit` |
| `check-refs.yml` | Self-references must be `@main`; other repos in the org must be `@<40-char release-tag sha> # vX.Y.Z` | — |
| `actionlint.yml` | actionlint (pinned image), errors as annotations | — |
| `lint.yml` | ShellCheck (pinned image) and PSScriptAnalyzer (pinned version) on tracked scripts | — |
| `test-scripts.yml` | `tests/*.test.sh` on ubuntu, macOS and Windows, with submodules; fails if there are none | — |

Inside a called workflow, `github.*` and `vars` belong to the **caller**, so every workflow acts on the calling repo.

## Usage

Pin each call to a release-tag SHA (`git ls-remote https://github.com/dotactions/tooling 'refs/tags/v1.0.0^{}'`). Callers set `on:`/`paths:` and must **not** declare `concurrency:`, because the called workflows already do, and an identical group in caller and callee deadlocks.

```yaml
# .github/workflows/internal-release.yml
name: Release
on:
  workflow_dispatch:
    inputs:
      version:
        description: "Version to release, without leading v (e.g. 1.2.0 or 1.2.0-rc.1)"
        required: true
        type: string
permissions:
  contents: read
jobs:
  release:
    uses: dotactions/tooling/.github/workflows/release.yml@<sha> # v1.0.0
    with:
      version: ${{ inputs.version }}
    secrets: inherit
```

```yaml
# .github/workflows/internal-actionlint.yml
name: Lint Workflows
on:
  pull_request:
    paths: [".github/workflows/**", "action.yml", "**/action.yml"]
  push:
    branches: [main]
    paths: [".github/workflows/**", "action.yml", "**/action.yml"]
permissions:
  contents: read
jobs:
  actionlint:
    uses: dotactions/tooling/.github/workflows/actionlint.yml@<sha> # v1.0.0
```

`check-refs.yml`, `lint.yml` and `test-scripts.yml` are called the same way. None needs `with:` or permissions beyond `contents: read`.

## Test harness

Repos with script tests add this repo as a submodule and source the harness:

```bash
git submodule add https://github.com/dotactions/tooling .tooling
```

```bash
# tests/<name>.test.sh
source "$(dirname "$0")/../.tooling/tests/lib.sh"
SCRIPT="$REPO_ROOT/<action>/scripts/<name>.sh"

new_case
run "$SCRIPT" INPUT=value
expect_ok "accepts value"
expect "sets output" "expected" "$(output name)"
finish
```

`REPO_ROOT` is the consuming repo (derived from the test file's path). Functions: `new_case`, `run`, `stub`, `only_on`, `output`, `env_var`, `stub_log`, `expect`, `expect_ok`, `expect_fail`, `expect_file`, `finish`. Bump the submodule with Dependabot (`gitsubmodule`).

## Tooling's own tests

`tests/*.test.sh` run the exact inline `run:` blocks of these workflows (extracted with `yq`) against scratch repos: release versioning, rewrite, tagging and floating tags; both check-refs rules; the test loop; actionlint and ShellCheck through the pinned image (needs Docker); and the harness itself on all three OSes. `test-scripts.yml` runs them on every push and PR here.

## Org setup (once)

Releases authenticate as a GitHub App, because `GITHUB_TOKEN` can't push tags to commits that change `.github/workflows/`.

- App permissions: Contents read & write, Workflows read & write. Install it on the org.
- Org variable `RELEASE_APP_CLIENT_ID`: the app's Client ID.
- Org secret `RELEASE_APP_PRIVATE_KEY`: the app's private key (`.pem` contents).

## Releasing

Go to **Actions → Release → Run workflow** on `main` and enter a version: `1.0.0`, or `1.0.0-rc.1` for a pre-release that moves no floating tags. Don't use **Releases → Draft a new release**: it doesn't move the floating `v1` tag.
