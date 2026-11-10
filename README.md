# Shared actions

## Versioning

Pin a **full commit SHA** of a release tag (most secure, Semgrep standard), with the version in a comment:

```yaml
uses: dotsem/actions/.github/workflows/flutter-ci.yml@<40-char-sha> # v0.5.0
```

Or pin a **minor** tag (convenient, receives patch fixes):

```yaml
uses: dotsem/actions/.github/workflows/flutter-ci.yml@v0.5
```

Resolve a SHA with `git ls-remote https://github.com/dotsem/actions 'refs/tags/v0.5.0^{}'`. Only SHAs of **release tags** pin the whole tree; a SHA from `main` still contains `@main` self-references.

| Ref       | Moves on                 | Use                                                         |
| :-------- | :----------------------- | :---------------------------------------------------------- |
| `@<sha>`  | never                    | **Recommended** (recommended by SemGrep): immutable, full reproducibility            |
| `@v0.5`   | patch releases of `0.5`  | **Recommended**: bug fixes, no breaking changes             |
| `@v0.5.0` | never (tag can be moved) | Readable, but tags are mutable                              |
| `@v0`     | every `0.x` release      | Not recommended: during `0.x`, minor releases may break you |

Every release tag pins the **whole tree**. Reusable workflows and actions that call other actions in this repo get those references rewritten to the same release tag, so `flutter-ci.yml@v0.5.0` always runs `build-flutter@v0.5.0`. On `main`, self-references are `@main`.

Release notes: [GitHub Releases](https://github.com/dotsem/actions/releases).

## Permissions

Examples assume a **public** repository. In a **private** repository, `actions/checkout` needs `contents: read`, so every job using these actions (or `flutter-ci.yml`) must grant it:

```yaml
permissions:
    contents: read # required for private repos; optional for public
```

Reusable workflows can only narrow the caller's token permissions, never widen them. Grant the permissions listed under each workflow in the calling job.

## Actions

### Setup Node & pnpm (`setup-node`)

Configures PNPM, sets up the Node.js runtime, restores cached dependencies, and runs `pnpm install --frozen-lockfile`.

> **Prerequisite**: Run `actions/checkout` before calling this action.

#### Inputs

| Name                    | Description                                                                                 | Required | Default |
| :---------------------- | :------------------------------------------------------------------------------------------ | :------- | :------ |
| `node-version`          | Target Node.js version                                                                      | No       | `"24"`  |
| `pnpm-version`          | Specific PNPM version (empty string reads from `package.json`)                              | No       | `""`    |
| `working-directory`     | Directory containing the target `package.json`                                              | No       | `"."`   |
| `cache-dependency-path` | Explicit lockfile path for cache hashing (defaults to `<working-directory>/pnpm-lock.yaml`) | No       | `""`    |

#### Usage

```yaml
- uses: dotsem/actions/setup-node@v0.5
  with:
      node-version: "24"
      working-directory: "frontend"
```

### Build Node (`build-node`)

Runs a production build command using PNPM in the specified directory.

#### Inputs

| Name                | Description                                               | Required | Default   |
| :------------------ | :-------------------------------------------------------- | :------- | :-------- |
| `working-directory` | Directory to execute the build command in                 | No       | `"."`     |
| `script`            | Lifecycle script defined in package.json                  | No       | `"build"` |
| `args`              | Additional CLI flags passed to the script (e.g. --filter) | No       | `""`      |

#### Usage

```yaml
- uses: dotsem/actions/build-node@v0.5
  with:
      working-directory: "frontend"
      script: "build"
      args: "--filter=web"
```

### Security Report (`security-report`)

Parses SARIF output, appends a detailed markdown summary with badge to the GitHub Actions Job Summary, upserts a sticky PR comment, and manages automated issue tracking.

#### Permissions Required

```yaml
permissions:
    contents: read
    pull-requests: write # for sticky PR comments
    issues: write # for automated issue management
```

#### Inputs

| Name               | Description                                           | Required | Default                                              |
| :----------------- | :---------------------------------------------------- | :------- | :--------------------------------------------------- |
| `sarif-file`       | Path to SARIF output file                             | Yes      | -                                                    |
| `title`            | Header title in report                                | No       | `"Security Scan Report"`                             |
| `comment-tag`      | Identifier tag for sticky PR comments & issue markers | No       | `"security-report"`                                  |
| `badge-label`      | Label text for shields.io badge                       | No       | `"Security"`                                         |
| `github-token`     | Token with PR and issues write permissions            | No       | `${{ github.token }}`                                |
| `fail-on-findings` | Fail step if findings are detected                    | No       | `"false"`                                            |
| `manage-issue`     | Create/update/close tracked GitHub issue              | No       | `"false"`                                            |
| `issue-title`      | Title of automated GitHub issue                       | No       | `"[Security Audit] Active Vulnerabilities Detected"` |

#### Outputs

| Name             | Description                                      |
| :--------------- | :----------------------------------------------- |
| `total-findings` | Total number of non-suppressed findings detected |
| `report-file`    | Path to the generated Markdown report file       |

#### Usage

```yaml
- name: Report Trivy Results
  uses: dotsem/actions/security-report@v0.5
  if: always() && hashFiles('trivy.sarif') != ''
  with:
      title: "Trivy Vulnerability Report"
      sarif-file: "trivy.sarif"
      comment-tag: "trivy"
      fail-on-findings: "true"
```

### Build Flutter (`build-flutter`)

Sets up Flutter, automatically resolves app metadata from `pubspec.yaml`, installs target dependencies, builds binaries in release, debug, or profile mode, and packages artifacts for Linux, macOS, Windows, Android (android-apk/android-aab), or iOS.

> **Prerequisite**: Run `actions/checkout` before calling this action.

> **Flutter version**: unless `flutter-version` is passed, the SDK version is read from `environment.flutter` in `<working-directory>/pubspec.yaml`, which must be an exact version:
>
> ```yaml
> environment:
>     sdk: ^3.13.1
>     flutter: 3.47.1
> ```

#### Inputs

| Name                | Description                                                                          | Required | Default     |
| :------------------ | :----------------------------------------------------------------------------------- | :------- | :---------- |
| `target`            | Target platform: `linux`, `macos`, `windows`, `android-apk`, `android-aab`, or `ios` | Yes      | -           |
| `flutter-version`   | Flutter SDK version (empty reads `environment.flutter` from `pubspec.yaml`)          | No       | `""`        |
| `channel`           | Flutter release channel                                                              | No       | `"stable"`  |
| `cache`             | Cache Flutter SDK artifacts                                                          | No       | `"true"`    |
| `working-directory` | Directory containing `pubspec.yaml`                                                  | No       | `"."`       |
| `build-mode`        | Build compilation mode: `debug`, `profile`, or `release`                             | No       | `"release"` |

#### Outputs

| Name            | Description                                   |
| :-------------- | :-------------------------------------------- |
| `artifact-name` | Base name for the generated artifact          |
| `artifact-path` | Path glob pointing to the packaged archive(s) |

#### Usage

```yaml
- name: Build Flutter App
  uses: dotsem/actions/build-flutter@v0.5
  with:
      target: "linux"
```

### Setup Flutter (`setup-flutter`)

Installs the Flutter SDK and runs `flutter pub get`.

> **Prerequisite**: Run `actions/checkout` before calling this action.

> **Flutter version**: unless `flutter-version` is passed, the SDK version is read from `environment.flutter` in `<working-directory>/pubspec.yaml`, which must be an exact version:
>
> ```yaml
> environment:
>     sdk: ^3.13.1
>     flutter: 3.47.1
> ```

#### Inputs

| Name                | Description                                                                 | Required | Default    |
| :------------------ | :-------------------------------------------------------------------------- | :------- | :--------- |
| `flutter-version`   | Flutter SDK version (empty reads `environment.flutter` from `pubspec.yaml`) | No       | `""`       |
| `channel`           | Flutter release channel                                                     | No       | `"stable"` |
| `cache`             | Cache Flutter SDK artifacts                                                 | No       | `"true"`   |
| `working-directory` | Directory containing `pubspec.yaml`                                         | No       | `"."`      |

#### Usage

```yaml
- uses: dotsem/actions/setup-flutter@v0.5
- run: flutter analyze
```

### Flutter Matrix (`flutter-matrix`)

Validates Flutter targets and resolves a `strategy.matrix` (target + runner OS) and build mode for the current event. Used internally by `flutter-ci.yml` and `flutter-cd.yml`. The list of valid targets and their runners is defined in [`build-flutter/targets.json`](build-flutter/targets.json).

#### Inputs

| Name              | Description                                                    | Required | Default |
| :---------------- | :------------------------------------------------------------- | :------- | :------ |
| `targets`         | JSON array of targets for all events (overrides the two below) | No*      | `""`    |
| `pr-targets`      | JSON array of targets on `pull_request`                        | No*      | `""`    |
| `push-targets`    | JSON array of targets on push / other events                   | No*      | `""`    |
| `build-mode`      | Build mode for all events (overrides the two below)            | No       | `""`    |
| `pr-build-mode`   | Build mode on `pull_request` (falls back to `"debug"`)         | No       | `""`    |
| `push-build-mode` | Build mode on push / other events (falls back to `"release"`)  | No       | `""`    |

_Provide either `targets` or both `pr-targets` and `push-targets`._

#### Outputs

| Name         | Description                                                |
| :----------- | :--------------------------------------------------------- |
| `matrix`     | JSON array of `{target, os}` for `strategy.matrix.include` |
| `build-mode` | Resolved build mode                                        |

#### Usage

```yaml
jobs:
    matrix:
        runs-on: ubuntu-latest
        outputs:
            matrix: ${{ steps.m.outputs.matrix }}
        steps:
            - id: m
              uses: dotsem/actions/flutter-matrix@v0.5
              with:
                  targets: '["linux", "windows"]'
    build:
        needs: matrix
        runs-on: ${{ matrix.os }}
        strategy:
            matrix:
                include: ${{ fromJson(needs.matrix.outputs.matrix) }}
        steps:
            - uses: actions/checkout@v7
            - uses: dotsem/actions/build-flutter@v0.5
              with:
                  target: ${{ matrix.target }}
```

## Workflows

### Trivy Security Audit (`trivy-audit.yml`)

Runs Trivy vulnerability and misconfiguration scanning on the caller repository, parses findings, publishes sticky PR comments / job summaries via `security-report`, and optionally uploads SARIF artifacts.

#### Permissions Required

```yaml
permissions:
    contents: read
    issues: write # PR comments + issue tracking
    pull-requests: write # optional: only if you replace the issues API with the pulls API
```

#### Inputs

| Name               | Description                                | Required | Default                  |
| :----------------- | :----------------------------------------- | :------- | :----------------------- |
| `scan-type`        | Trivy scan target type (e.g. `fs`)         | No       | `"fs"`                   |
| `severity`         | Comma-separated severity levels to include | No       | `"CRITICAL,HIGH,MEDIUM"` |
| `fail-on-findings` | Fail the workflow if findings are detected | No       | `false`                  |
| `upload-artifact`  | Upload SARIF scan report as a job artifact | No       | `true`                   |
| `manage-issue`     | Create/update/close tracked GitHub issue   | No       | `false`                  |

#### Secrets

| Name    | Description                                                  | Required |
| :------ | :----------------------------------------------------------- | :------- |
| `token` | GitHub token with pull-requests and issues write permissions | No       |

#### Usage

```yaml
# .github/workflows/security.yml
name: Security Audit

on:
    push:
        branches: [main]
        paths-ignore:
            - "**.md"
    pull_request:
        branches: [main]
        paths-ignore:
            - "**.md"
    schedule:
        - cron: "0 4 * * 4" # weekly Thursday at 04:00 UTC
    workflow_dispatch:

concurrency:
    group: ${{ github.workflow }}-${{ github.ref }}
    cancel-in-progress: ${{ github.ref != 'refs/heads/main' }}

jobs:
    audit:
        uses: dotsem/actions/.github/workflows/trivy-audit.yml@v0.5
        permissions:
            contents: read
            pull-requests: write
            issues: write
        with:
            severity: "CRITICAL,HIGH"
            fail-on-findings: true
            manage-issue: ${{ github.event_name == 'schedule' || github.event_name == 'workflow_dispatch' }}
```

### Flutter CI (`flutter-ci.yml`)

Runs Flutter static analysis, unit tests, and cross-platform compilation across a specified list of targets.

#### Permissions Required

```yaml
permissions:
    contents: read # required for private repos; optional for public
```

#### Permissions Required

```yaml
permissions:
    contents: read # required on private repos; harmless on public
```

#### Inputs

| Name                | Description                                                                 | Required | Default |
| :------------------ | :-------------------------------------------------------------------------- | :------- | :------ |
| `pr-targets`        | JSON array of targets to build on pull request (e.g. `'["linux"]'`)         | No*      | `""`    |
| `push-targets`      | JSON array of targets to build on push (e.g. `'["linux", "macos"]'`)        | No*      | `""`    |
| `targets`           | JSON array of targets to build for all events (overrides above)             | No*      | `""`    |
| `flutter-version`   | Flutter SDK version (empty reads `environment.flutter` from `pubspec.yaml`) | No       | `""`    |
| `working-directory` | Directory containing `pubspec.yaml`                                         | No       | `"."`   |
| `build-mode`        | Universal build mode (`debug`, `profile`, `release`) (overrides below)      | No       | `""`**  |
| `pr-build-mode`     | Build mode on pull request (defaults to `"debug"`)                          | No       | `""`**  |
| `push-build-mode`   | Build mode on push/merge (defaults to `"release"`)                          | No       | `""`**  |
| `concurrency-tests` | Number of concurrent test runners                                           | No       | `4`     |

*_You must provide either `targets` or both `pr-targets` and `push-targets`._

** _If none are provided. PR build-mode is `"debug"`, push build-mode is `"release"`._

#### Usage

```yaml
# .github/workflows/ci.yml
name: CI Pipeline

on:
    push:
        branches: [main]
        paths-ignore: ["**.md"]
    pull_request:
        branches: ["**"]
        paths-ignore: ["**.md"]

concurrency:
    group: ${{ github.workflow }}-${{ github.ref }}
    cancel-in-progress: true

jobs:
    ci:
        uses: dotsem/actions/.github/workflows/flutter-ci.yml@v0.5
        with:
            pr-targets: '["android-apk"]'
            push-targets: '["android-aab", "windows"]'
            # or a target for all events:
            # targets: '["linux"]'

            pr-build-mode: "debug"
            push-build-mode: "release"
            # or a build mode for all events:
            # build-mode: 'release'
```

### Flutter CD (`flutter-cd.yml`)

Builds release packages across specified platforms and uploads them directly to a GitHub release.

#### Permissions Required

```yaml
permissions:
    contents: write # for uploading release assets
```

#### Inputs

| Name                | Description                                                                 | Required | Default |
| :------------------ | :-------------------------------------------------------------------------- | :------- | :------ |
| `targets`           | JSON array of targets to build (e.g. `'["linux", "windows"]'`)              | Yes      | -       |
| `tag`               | Target release tag (defaults to event tag or ref)                           | No       | `""`    |
| `flutter-version`   | Flutter SDK version (empty reads `environment.flutter` from `pubspec.yaml`) | No       | `""`    |
| `working-directory` | Directory containing `pubspec.yaml`                                         | No       | `"."`   |

#### Secrets

| Name    | Description                                               | Required |
| :------ | :-------------------------------------------------------- | :------- |
| `token` | GitHub token with write access (defaults to GITHUB_TOKEN) | No       |

#### Usage

```yaml
# .github/workflows/release.yml
name: Release

on:
    release:
        types: [published]
    workflow_dispatch:
        inputs:
            tag:
                description: "Release tag"
                required: false

concurrency:
    group: ${{ github.workflow }}-${{ github.ref }}
    cancel-in-progress: false

jobs:
    cd:
        uses: dotsem/actions/.github/workflows/flutter-cd.yml@v0.5
        permissions:
            contents: write
        with:
            targets: '["linux", "windows", "macos", "android-aab"]'
            tag: ${{ inputs.tag || github.event.release.tag_name }}
```

## Releasing (maintainers)

1. Merge to `main` with conventional-commit PR titles; these become the release notes.
2. Run the **Release** workflow (`internal-release.yml`) from `main` with a version, e.g. `0.5.0` or `0.5.0-rc.1`.
3. The workflow:
    - rewrites every `dotsem/actions/...@main` self-reference to `@v<version>` in a detached release commit
    - tags it `v<version>` and creates a GitHub release with generated notes
    - moves `v0` and `v0.<minor>` to the new tag (skipped for pre-releases)

Authenticates as a GitHub App (short-lived token, scoped to this repo), because `GITHUB_TOKEN` can't push commits that modify `.github/workflows/`. Requires:

- repository variable `RELEASE_APP_CLIENT_ID`: the app's Client ID
- repository secret `RELEASE_APP_PRIVATE_KEY`: the app's private key
- app repository permissions **Contents: read & write** and **Workflows: read & write**, installed on this repo only

Bump the **minor** version for breaking changes and the **patch** version for everything else.
