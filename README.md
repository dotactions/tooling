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
- uses: dotsem/actions/setup-node@main
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
- uses: dotsem/actions/build-node@main
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
  uses: dotsem/actions/security-report@main
  if: always() && hashFiles('trivy.sarif') != ''
  with:
      title: "Trivy Vulnerability Report"
      sarif-file: "trivy.sarif"
      comment-tag: "trivy"
      fail-on-findings: "true"
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
  pull_request:
    branches: [main]
  schedule:
    - cron: "0 4 * * 4" # Weekly Thursday at 04:00 UTC

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

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

```
