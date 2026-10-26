# Shared actions

## Actions

### Setup Node & pnpm (`setup-node`)

Configures PNPM, sets up the Node.js runtime, restores cached dependencies, and runs `pnpm install --frozen-lockfile`.

> **Prerequisite**: Run `actions/checkout` before calling this action.

#### Inputs

| Name | Description | Required | Default |
| :--- | :--- | :--- | :--- |
| `node-version` | Target Node.js version | No | `"22"` |
| `pnpm-version` | Specific PNPM version (empty string reads from `package.json`) | No | `""` |
| `working-directory` | Directory containing the target `package.json` | No | `"."` |
| `cache-dependency-path` | Explicit lockfile path for cache hashing (defaults to `<working-directory>/pnpm-lock.yaml`) | No | `""` |

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

| Name | Description | Required | Default |
| :--- | :--- | :--- | :--- |
| `working-directory` | Directory to execute the build command in | No | `"."` |
| `script` | Lifecycle script defined in package.json | No | `"build"` |
| `args` | Additional CLI flags passed to the script (e.g. --filter) | No | `""` |

#### Usage

```yaml
- uses: dotsem/actions/build-node@main
  with:
    working-directory: "frontend"
    script: "build"
    args: "--filter=web"
```

## Workflows