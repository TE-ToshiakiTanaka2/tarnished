# Auto Tag GitHub Action

Automatically create semantic version tags when a Pull Request is merged, based on branch naming conventions.

## Features

- **Semantic Versioning**: Follows semver (vX.Y.Z) format
- **Branch-based versioning**: Version bump determined by branch prefix
- **Configurable**: Customize branch prefix mappings via `.github/version.yml`
- **PR Comments**: Posts success/failure comments to the merged PR
- **RC Support**: Unmatched branches create Release Candidate tags

## Usage

### Basic Setup

1. Create the workflow file `.github/workflows/auto-tag.yml`:

```yaml
name: Auto Tag on PR Merge

on:
  pull_request:
    types: [closed]
    branches:
      - main
      - develop

jobs:
  auto-tag:
    name: Create Version Tag
    runs-on: ubuntu-latest
    if: github.event.pull_request.merged == true

    permissions:
      contents: write
      pull-requests: write

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Run Auto Tag Action
        id: auto-tag
        uses: ./.github/actions/auto-tag
        with:
          token: ${{ secrets.GITHUB_TOKEN }}
```

2. Create the configuration file `.github/version.yml`:

```yaml
versioning:
  branch_prefixes:
    major:
      - "major/"
    minor:
      - "release/"
    patch:
      - "feature/"
```

## Branch Naming Convention

Branches must follow this pattern:

```
{type}/{assignee}/#{issue}/{description}
```

**Examples:**
- `feature/tanaka/#123/add-login`
- `release/yamada/#45/v2-release`
- `major/suzuki/#99/breaking-change`
- `bugfix/tanaka/#10/fix-validation`

## Version Mapping

| Branch Type | Version Bump | Example |
|-------------|--------------|---------|
| `major/*` | Major (X.0.0) | v1.2.3 → v2.0.0 |
| `release/*` | Minor (0.X.0) | v1.2.3 → v1.3.0 |
| `feature/*` | Patch (0.0.X) | v1.2.3 → v1.2.4 |
| Others | RC (0.0.X-rc.N) | v1.2.3 → v1.2.4-rc.1 |

## Configuration

### `.github/version.yml`

```yaml
versioning:
  branch_prefixes:
    # Major version bump (X.0.0)
    major:
      - "major/"
      - "breaking/"

    # Minor version bump (0.X.0)
    minor:
      - "release/"
      - "feat/"

    # Patch version bump (0.0.X)
    patch:
      - "feature/"
      - "fix/"
```

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `token` | GitHub token with `contents:write` and `pull-requests:write` permissions | Yes | `${{ github.token }}` |

## Outputs

| Output | Description | Example |
|--------|-------------|---------|
| `version` | Created tag version | `v1.2.3` |
| `previous-version` | Previous tag version | `v1.2.2` |
| `version-type` | Version bump type | `patch` |

## PR Comments

### Success

```markdown
## 🔧 Auto Tag Created

| Item | Value |
|------|-------|
| **Version** | `v1.2.4` |
| **Previous** | `v1.2.3` |
| **Type** | patch |

Tag created successfully!
```

### Failure

```markdown
## ❌ Auto Tag Failed

**Error**: Could not parse branch name

Please check the workflow logs for details.
```

## Development

### Prerequisites

- Node.js 20+
- pnpm (or npm)

### Setup

```bash
cd .github/actions/auto-tag
pnpm install
```

### Commands

| Command | Description |
|---------|-------------|
| `pnpm build` | Build with ncc |
| `pnpm test` | Run tests |
| `pnpm test:coverage` | Run tests with coverage |
| `pnpm lint` | Run linter |
| `pnpm typecheck` | Type check |

### Testing

```bash
pnpm test
```

## License

MIT
