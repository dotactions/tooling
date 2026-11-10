# Agents Rules for dotsem/actions

This file specifies constraints and standards for AI Agents when working on dotsem/actions: a monorepo of opinionated composite/JS actions and reusable workflows consumed by other repositories. Every change here ships to every consumer, so correctness and pinning discipline outrank convenience.

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
    - Package manager is strictly `pnpm`.

## Repository Layout

| Path                               | Purpose                                                                                                                            |
| :--------------------------------- | :--------------------------------------------------------------------------------------------------------------------------------- |
| `<action>/action.yml`              | Public composite or JS actions (`setup-node`, `build-node`, `setup-flutter`, `build-flutter`, `flutter-matrix`, `security-report`) |
| `<action>/scripts/`                | Shell / PowerShell called from composite steps via `${{ github.action_path }}`                                                     |
| `security-report/src/` → `dist/`   | TypeScript source, bundled by `tsup` into committed `dist/index.js`                                                                |
| `build-flutter/targets.json`       | Single source of truth for valid Flutter targets and their runner OS                                                               |
| `.github/workflows/<name>.yml`     | Public reusable workflows (`workflow_call`): `flutter-ci`, `flutter-cd`, `trivy-audit`                                             |
| `.github/workflows/internal-*.yml` | This repo's own CI, tests and release. Never consumed externally                                                                   |
| `tests/fixtures/`                  | Minimal Node / Flutter projects and SARIF files used by `internal-test-*` workflows                                                |

## Project Rules

### Pinning & Self-References

- Every third-party `uses:` is pinned to a full commit SHA with a version comment: `uses: owner/repo@<40-char-sha> # vX.Y.Z`. Resolve SHAs with `git ls-remote --tags`; never guess or invent one. If you cannot resolve it, stop and ask.
- References to this repo's own actions **must** be `dotsem/actions/<path>@main` with the comment `# @main is rewritten to the exact release tag by internal-release.yml`. Never write `@v0`, `@vX.Y.Z` or a SHA for a self-reference; `internal-check-refs.yml` fails on it.
- Composite actions cannot reference sibling actions by relative path. Inside a reusable workflow, `./` points at the **caller's** repo. Never "fix" this with a checkout of `dotsem/actions` at a branch.

### Inputs, Scripts & Security

- Never interpolate `${{ }}` directly into `run:`. Pass values through `env:` and reference `"$VAR"`.
- Logic longer than a few lines goes into `<action>/scripts/*.sh` (bash, `set -euo pipefail`) or `*.ps1`, not inline YAML. Scripts must pass ShellCheck / PSScriptAnalyzer.
- Validate inputs early and fail with `::error::` messages naming the allowed values.
- Workflows declare `permissions: contents: read` at the top level and widen per job only where required.
- Input defaults must not duplicate data that lives elsewhere (e.g. Flutter version comes from the consumer's `pubspec.yaml`, pnpm from `packageManager`, targets from `targets.json`).

### TypeScript (`security-report`)

- After changing anything in `src/`, run `pnpm build` and include the regenerated `dist/`. `internal-check-dist.yml` fails on drift.
- Run `pnpm check-types` before finishing. No `any` without a `// ponytail:` justification.

### Public API & Versioning

- Inputs, outputs, input defaults, artifact names and reusable-workflow `with:`/`secrets:` are public API. Renaming, removing or changing the default of any of them is a **breaking change**: flag it explicitly in your response so the human can bump the minor version (during `0.x`).
- Every public input/output change must be reflected in `README.md` (tables + usage examples, which pin `@v0.N`).
- Releases are cut only by the human via the `Release` workflow (`internal-release.yml`). Never create or move tags, and never edit the floating-tag logic without being asked.

## Testing

- Composite actions are tested via `uses: ./<action>` in the matching `internal-test-<area>.yml`, with assertions on outputs and produced files. Add or extend a test for every behavioural change.
- Script logic is unit-tested in `tests/<name>.test.sh` using the `tests/lib.sh` harness (`new_case`, `run`, `expect*`, `stub`, `only_on`); `internal-test-scripts.yml` runs every one on ubuntu, macOS and Windows. Add cases for every branch you change.
- Each `internal-*` workflow has a `paths:` filter. When adding files that a workflow should cover, update its filter.
- Local checks before finishing (run whichever apply):
    - `shellcheck <changed .sh files>`
    - `docker run --rm -v "$PWD:/repo" -w /repo rhysd/actionlint:1.7.12` for workflow changes
    - `pnpm check-types && pnpm build` for `security-report`
    - `pnpm prettier --check .`
    - Exercise changed scripts directly with sample env vars and a temp `GITHUB_OUTPUT` / `GITHUB_ENV`
- Report honestly which checks ran and which could not (e.g. multi-OS builds only run in CI).
