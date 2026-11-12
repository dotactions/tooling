# Agents Rules for dotactions/tooling

Reusable workflows (`workflow_call`) and the shell test harness shared by every `dotactions/*` repo's CI. Nothing here runs in a consumer's pipeline, but every change runs in every `dotactions` repo, so a broken workflow blocks all of them at once.

## CRITICAL INSTRUCTIONS

1. **The Ponytail Workflow (Default Execution Mode)**:
    - Climb the senior dev ladder: YAGNI -> Reuse -> Stdlib -> Platform -> Deps -> Simplicity -> Minimal Diff.
    - Deletion over addition. Boring over clever.
    - Mark intentional simplifications with `ponytail:` comments (`# ponytail:` in YAML/shell/PowerShell, `// ponytail:` in TypeScript) naming the known ceiling and upgrade path.
    - Non-trivial logic must leave behind at least one runnable check (see [Testing](#testing)).

2. **Commit Policy**:
    - AI assistants are strictly prohibited from generating, suggesting, or running git commits, pushes, tags, or releases under any circumstance. Commits and releases are human-only.

3. **Plan Execution Policy**:
    - **Never** proceed to code changes or implementation commands directly from a plan unless the human developer explicitly replies with direct authorization (e.g., "go ahead", "approved", "execute").
    - A plan is strictly for review. Keep your hands off the files until permission is explicitly given.

4. **Comments & Standards**:
    - Strictly NO inline comments explaining syntax or obvious actions. Comments explain _why_ (constraints, GitHub quirks, security reasons), never _what_.
    - Ceiling of 300 lines per file (excluding `README.md`, lockfiles, fixtures and `dist/`). Always ask before performing major file splits or autonomous refactoring.

## Repository Layout

| Path | Purpose |
| :--- | :--- |
| `.github/workflows/release.yml` | Cuts a release in the **calling** repo: rewrites its `@main` self-references, tags, moves floating tags |
| `.github/workflows/check-refs.yml` | Self-references `@main`; other `dotactions` repos pinned by release-tag SHA |
| `.github/workflows/actionlint.yml`, `lint.yml` | actionlint, ShellCheck, PSScriptAnalyzer |
| `.github/workflows/test-scripts.yml` | Runs the caller's `tests/*.test.sh` on ubuntu, macOS and Windows |
| `tests/lib.sh` | Test harness, consumed as the `.tooling` git submodule (tests only, never at runtime) |
| `tests/workflow.sh` | Tooling-only helpers: extract a step's `run:` block (`step_script`) or field (`step_field`) |
| `tests/*.test.sh` | Tooling's own tests: release, check-refs, test-scripts, linters (Docker) and the harness itself |

## Project Rules

### Reusable-workflow context

- In a called workflow, `github.repository`, `github.ref`, `github.event.*`, `vars` and the checkout default are the **caller's**. That is what makes one `release.yml` work for every repo. Never hardcode a repo name; derive it from `$GITHUB_REPOSITORY` / `$GITHUB_REPOSITORY_OWNER`.
- A called workflow cannot read files from this repo (checkout gets the caller's), so logic stays inline in `run:`. Keep it short, bash, `set -euo pipefail` semantics.
- Called workflows can only narrow the caller's permissions. A job that needs more than `contents: read` documents it in `README.md` so callers grant it.
- Each workflow keeps its own `concurrency:`. Callers must not set the same group (deadlock).
- Workflows with their own `on:` triggers next to `workflow_call` are this repo's own CI; no separate caller files.

### Pinning

- Every `uses:` is pinned to a full commit SHA with a version comment: `uses: owner/repo@<40-char-sha> # vX.Y.Z`. Resolve SHAs with `git ls-remote --tags`; never guess or invent one. If you cannot resolve it, stop and ask.

### Security

- Never interpolate `${{ }}` directly into `run:`. Pass values through `env:` and reference `"$VAR"`.
- Workflows declare `permissions: contents: read` at the top level and widen per job only where required.

### Public API & Versioning

- Workflow `inputs:`/`secrets:`, the check-refs rules, the release tag scheme and the `tests/lib.sh` functions (`new_case`, `run`, `stub`, `expect*`, `only_on`, `finish`, `REPO_ROOT`, `WORK`) are public API for every `dotactions` repo. Changing them is a **breaking change**: flag it explicitly so the human can bump the major version.
- Releases are cut only by the human via the `Release` workflow. Never create or move tags, and never edit the floating-tag logic without being asked.

## Testing

- Every inline `run:` block with logic has a test in `tests/<workflow>.test.sh` that runs the exact block via `step_script` (no copies, so tests can't drift). Add cases for every branch you change; refer to steps by `name:`, so renaming a step means updating its test.
- `tests/lib.test.sh` covers the harness on all three OSes. A `lib.sh` change also gets a run of a consumer's tests, e.g. from `../flutter` with `.tooling` pointing at your working copy.
- `test-scripts.yml` runs all of them on push/PR. Locally: `for t in tests/*.test.sh; do bash "$t"; done` (needs `yq` or python3 + PyYAML; `linters.test.sh` needs Docker and skips without it).
- Local checks before finishing (run whichever apply):
    - `for t in tests/*.test.sh; do bash "$t"; done`
    - `docker run --rm -v "$PWD:/repo" -w /repo rhysd/actionlint:1.7.12` for workflow changes
- Report honestly which checks ran and which could not (e.g. multi-OS builds only run in CI).
