# Shared actions

## Actions

### Setup Node & pnpm (`setup-node`)

Configures PNPM, sets up the Node.js runtime, restores cached dependencies, and runs `pnpm install --frozen-lockfile`.

> **Prerequisite**: Run `actions/checkout` before calling this action.

#### Inputs

| Name                    | Description                                                                                 | Required | Default |
| :---------------------- | :------------------------------------------------------------------------------------------ | :------- | :------ |
| `node-version`          | Target Node.js version                                                                      | No       | `"22"`  |
| `pnpm-version`          | Specific PNPM version (empty string reads from `package.json`)                              | No       | `""`    |
| `working-directory`     | Directory containing the target `package.json`                                              | No       | `"."`   |
| `cache-dependency-path` | Explicit lockfile path for cache hashing (defaults to `<working-directory>/pnpm-lock.yaml`) | No       | `""`    |

#### Usage

```yaml
- uses: dotsem/actions/setup-node@v0
  with:
      node-version: "22"
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
- uses: dotsem/actions/build-node@v0
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
  uses: dotsem/actions/security-report@v0
  if: always() && hashFiles('trivy.sarif') != ''
  with:
      title: "Trivy Vulnerability Report"
      sarif-file: "trivy.sarif"
      comment-tag: "trivy"
      fail-on-findings: "true"
```

### Build Flutter (`build-flutter`)

Sets up Flutter, automatically resolves app metadata from `pubspec.yaml`, installs target dependencies, builds binaries in release, debug, or profile mode, and packages artifacts for Linux, macOS, Windows, Android (APK/AAB), or iOS.

> **Prerequisite**: Run `actions/checkout` before calling this action.

#### Inputs

| Name                | Description                                                       | Required | Default    |
| :------------------ | :---------------------------------------------------------------- | :------- | :--------- |
| `target`            | Target platform: `linux`, `macos`, `windows`, `android`, or `ios` | Yes      | -          |
| `flutter-version`   | Target Flutter SDK version                                        | No       | `"3.47.1"` |
| `channel`           | Flutter release channel                                           | No       | `"stable"` |
| `cache`             | Cache Flutter SDK artifacts                                       | No       | `"true"`   |
| `working-directory` | Directory containing `pubspec.yaml`                               | No       | `"."`      |
| `android-format`    | Artifact format when targeting Android (`apk`, `aab`, or `both`)  | No       | `"apk"`    |
| `build-mode`        | Build compilation mode: `debug`, `profile`, or `release`          | No       | `"release"`|

*Note: Selecting 'both' will upload both APK & AAB as individual release assets.*

#### Outputs

| Name            | Description                                   |
| :-------------- | :-------------------------------------------- |
| `artifact-name` | Base name for the generated artifact          |
| `artifact-path` | Path glob pointing to the packaged archive(s) |

#### Usage

```yaml
- name: Build Flutter App
  uses: dotsem/actions/build-flutter@v0
  with:
      target: "linux"
```

## Workflows

### Trivy Security Audit (`trivy-audit.yml`)

Runs Trivy vulnerability and misconfiguration scanning on the caller repository, parses findings, publishes sticky PR comments / job summaries via `security-report`, and optionally uploads SARIF artifacts.

#### Permissions Required

```yaml
permissions:
    contents: read
    pull-requests: write # for sticky PR comments
    issues: write # for automated issue management
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
        uses: dotsem/actions/.github/workflows/trivy-audit.yml@v0
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

#### Inputs

| Name                | Description                                                          | Required | Default    |
| :------------------ | :------------------------------------------------------------------- | :------- | :--------- |
| `pr-targets`        | JSON array of targets to build on pull request (e.g. `'["linux"]'`)  | No*       | `""`       |
| `push-targets`      | JSON array of targets to build on push (e.g. `'["linux", "macos"]'`) | No*       | `""`       |
| `targets`           | JSON array of targets to build for all events (overrides above)      | No*       | `""`       |
| `flutter-version`   | Flutter SDK version                                                  | No       | `"3.47.1"` |
| `working-directory` | Directory containing `pubspec.yaml`                                  | No       | `"."`      |
| `android-format`    | Artifact format when targeting Android (`apk`, `aab`, or `both`)     | No       | `"apk"`    |
| `build-mode`        | Universal build mode (`debug`, `profile`, `release`) (overrides below)| No       | `""`**        |
| `pr-build-mode`     | Build mode on pull request (defaults to `"debug"`)                   | No       | `""`**        |
| `push-build-mode`   | Build mode on push/merge (defaults to `"release"`)                   | No      | `""`**        |
| `concurrency-tests` | Number of concurrent test runners                                    | No       | `4`        |

**You must provide either `targets` or both `pr-targets` and `push-targets`.*

** *If none are provided. PR build-mode is `"debug"`, push build-mode is `"release"`.*

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
        uses: dotsem/actions/.github/workflows/flutter-ci.yml@v0
        with:
            pr-targets: '["linux"]'
            push-targets: '["linux", "windows", "macos"]'
            # or a target for all events:
            # targets: '["android"]'

            pr-build-mode: 'debug'
            push-build-mode: 'release'
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

| Name                | Description                                                      | Required | Default    |
| :------------------ | :--------------------------------------------------------------- | :------- | :--------- |
| `targets`           | JSON array of targets to build (e.g. `'["linux", "windows"]'`)   | Yes      | -          |
| `tag`               | Target release tag (defaults to event tag or ref)                | No       | `""`       |
| `flutter-version`   | Flutter SDK version                                              | No       | `"3.47.1"` |
| `working-directory` | Directory containing `pubspec.yaml`                              | No       | `"."`      |
| `android-format`    | Artifact format when targeting Android (`apk`, `aab`, or `both`) | No       | `"apk"`    |

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
    cancel-in-progress: true

jobs:
    cd:
        uses: dotsem/actions/.github/workflows/flutter-cd.yml@v0
        permissions:
            contents: write
        with:
            targets: '["linux", "windows", "macos", "android"]'
            tag: ${{ inputs.tag || github.event.release.tag_name }}
```
