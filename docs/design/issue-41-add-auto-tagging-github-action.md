# Design Document: Auto-Tag GitHub Action

**Issue**: #41 - Add auto-tagging GitHub Action on PR merge
**Author**: Claude Code
**Date**: 2026-01-16
**Status**: Draft

---

## 1. Overview

### 1.1 Purpose

PRがマージされた際に、ブランチ名のtype（prefix）に基づいて自動的にSemantic Versioningタグを作成するGitHub Actionsカスタムアクションを実装する。

### 1.2 Goals

- ブランチ命名規則に基づいた自動バージョニング
- 設定ファイルによるカスタマイズ可能なマッピング
- TypeScriptによる型安全な実装
- Vitestによるテスト可能な設計
- setup.shを通じたテンプレート配布

### 1.3 Non-Goals

- GitHub Releaseの自動作成（タグのみ）
- Changelog自動生成
- 複数リポジトリへの同期

---

## 2. Architecture

### 2.1 System Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                         GitHub Events                                │
│                   (pull_request: closed + merged)                    │
└─────────────────────────────┬───────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      auto-tag.yml (Workflow)                         │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │ Trigger: on pull_request closed (merged to main/develop)    │   │
│  │ Permissions: contents write, pull-requests write            │   │
│  └─────────────────────────────────────────────────────────────┘   │
└─────────────────────────────┬───────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    auto-tag Action (TypeScript)                      │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────────┐      │
│  │ config-      │    │   version-   │    │   tag-creator    │      │
│  │ loader.ts    │───▶│  detector.ts │───▶│      .ts         │      │
│  │              │    │              │    │                  │      │
│  │ - loadConfig │    │ - parseBranch│    │ - createTag      │      │
│  │ - validate   │    │ - getLatest  │    │ - pushTag        │      │
│  │ - defaults   │    │ - calcNext   │    └──────────────────┘      │
│  └──────────────┘    └──────────────┘              │                │
│         │                   │                      │                │
│         │                   │                      ▼                │
│         │                   │          ┌──────────────────┐        │
│         │                   │          │  pr-commenter    │        │
│         │                   │          │      .ts         │        │
│         │                   │          │                  │        │
│         │                   │          │ - postSuccess    │        │
│         │                   │          │ - postFailure    │        │
│         │                   │          └──────────────────┘        │
│         │                   │                                       │
│         ▼                   ▼                                       │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                     types.ts                                 │   │
│  │  - VersionConfig, BranchInfo, VersionType, VersionInfo      │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    .github/version.yml                               │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │ versioning:                                                  │   │
│  │   branch_prefixes:                                           │   │
│  │     major: ["major/"]                                        │   │
│  │     minor: ["release/"]                                      │   │
│  │     patch: ["feature/"]                                      │   │
│  └─────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

### 2.2 Component Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                         index.ts                                 │
│                      (Entry Point)                               │
├─────────────────────────────────────────────────────────────────┤
│ async function run(): Promise<void>                              │
│   1. Load configuration                                          │
│   2. Parse branch name                                           │
│   3. Detect version type                                         │
│   4. Get latest tag                                              │
│   5. Calculate next version                                      │
│   6. Create and push tag                                         │
│   7. Post PR comment (success/failure)                           │
│   8. Set outputs                                                 │
└───────────────┬─────────────────────────────────────────────────┘
                │
    ┌───────────┼───────────┬───────────────┐
    │           │           │               │
    ▼           ▼           ▼               ▼
┌────────┐ ┌────────┐ ┌──────────┐ ┌─────────────┐
│config- │ │version-│ │tag-      │ │pr-commenter │
│loader  │ │detector│ │creator   │ │             │
└────────┘ └────────┘ └──────────┘ └─────────────┘
```

---

## 3. File Structure

### 3.1 Action Package Structure

```
.github/
├── actions/
│   └── auto-tag/
│       ├── action.yml              # Action metadata
│       ├── package.json            # Dependencies
│       ├── pnpm-lock.yaml          # Lock file
│       ├── tsconfig.json           # TypeScript config
│       ├── vitest.config.ts        # Vitest config
│       ├── biome.json              # Linter config
│       ├── src/
│       │   ├── index.ts            # Entry point
│       │   ├── types.ts            # Type definitions
│       │   ├── config-loader.ts    # Configuration loading
│       │   ├── version-detector.ts # Version detection logic
│       │   ├── tag-creator.ts      # Tag creation logic
│       │   └── pr-commenter.ts     # PR comment posting
│       ├── __tests__/
│       │   ├── config-loader.test.ts
│       │   ├── version-detector.test.ts
│       │   ├── tag-creator.test.ts
│       │   └── pr-commenter.test.ts
│       └── dist/                   # Built output (ncc)
│           └── index.js
├── workflows/
│   └── auto-tag.yml                # Workflow definition
└── version.yml                     # Version mapping config
```

### 3.2 Template Structure (for setup.sh distribution)

```
templates/
└── github-actions/                 # New template directory
    ├── plugin.sh                   # Plugin script
    └── .github/
        ├── actions/
        │   └── auto-tag/
        │       └── ... (same as above)
        ├── workflows/
        │   └── auto-tag.yml
        └── version.yml
```

---

## 4. Interface Definitions

### 4.1 Type Definitions (types.ts)

```typescript
/**
 * Version bump types
 */
export type VersionType = 'major' | 'minor' | 'patch' | 'rc';

/**
 * Parsed branch information
 */
export interface BranchInfo {
  /** Branch type (e.g., 'feature', 'release', 'major') */
  type: string;
  /** Assignee username */
  assignee: string;
  /** Related issue number */
  issueNumber: number | null;
  /** Branch description */
  description: string;
  /** Raw branch name */
  raw: string;
}

/**
 * Parsed version information
 */
export interface VersionInfo {
  major: number;
  minor: number;
  patch: number;
  /** Pre-release identifier (e.g., 'rc.1', 'rc.2') */
  prerelease: string | null;
}

/**
 * Configuration file structure (.github/version.yml)
 */
export interface VersionConfig {
  versioning: {
    branch_prefixes: {
      major: string[];
      minor: string[];
      patch: string[];
    };
  };
}

/**
 * Action inputs from workflow
 */
export interface ActionInputs {
  /** GitHub token for API access */
  token: string;
}

/**
 * Action outputs
 */
export interface ActionOutputs {
  /** Created tag version (e.g., 'v1.2.3') */
  version: string;
  /** Previous tag version */
  previousVersion: string;
  /** Version bump type */
  versionType: VersionType;
}

/**
 * Tag creation result
 */
export interface TagResult {
  success: boolean;
  version: string;
  sha: string;
  error?: string;
}
```

### 4.2 Module Interfaces

#### config-loader.ts

```typescript
/**
 * Load and validate version configuration
 * @param configPath - Path to version.yml (default: .github/version.yml)
 * @returns Validated configuration or default config
 */
export async function loadConfig(configPath?: string): Promise<VersionConfig>;

/**
 * Get default configuration
 */
export function getDefaultConfig(): VersionConfig;

/**
 * Validate configuration structure
 */
export function validateConfig(config: unknown): config is VersionConfig;
```

#### version-detector.ts

```typescript
/**
 * Parse branch name into components
 * Pattern: {type}/{assignee}/#{issue}/{description}
 */
export function parseBranchName(branch: string): BranchInfo;

/**
 * Determine version type from branch info and config
 */
export function detectVersionType(
  branchInfo: BranchInfo,
  config: VersionConfig
): VersionType;

/**
 * Get latest tag from repository
 */
export async function getLatestTag(): Promise<string | null>;

/**
 * Get all RC tags for a specific base version
 */
export async function getRcTags(baseVersion: string): Promise<string[]>;

/**
 * Parse version string to VersionInfo
 */
export function parseVersion(version: string): VersionInfo;

/**
 * Calculate next version based on current and bump type
 */
export function calculateNextVersion(
  current: VersionInfo | null,
  type: VersionType,
  existingRcTags?: string[]
): string;
```

#### tag-creator.ts

```typescript
/**
 * Create and push a new tag
 */
export async function createTag(
  version: string,
  sha: string,
  token: string
): Promise<TagResult>;
```

#### pr-commenter.ts

```typescript
/**
 * Post success comment to PR
 */
export async function postSuccessComment(
  prNumber: number,
  version: string,
  previousVersion: string | null,
  versionType: VersionType,
  token: string
): Promise<void>;

/**
 * Post failure comment to PR
 */
export async function postFailureComment(
  prNumber: number,
  error: string,
  token: string
): Promise<void>;
```

---

## 5. Configuration

### 5.1 action.yml

```yaml
name: 'Auto Tag on PR Merge'
description: 'Automatically create semantic version tags based on branch type when PR is merged'
author: 'tarnished'

inputs:
  token:
    description: 'GitHub token with contents:write and pull-requests:write permissions'
    required: true
    default: ${{ github.token }}

outputs:
  version:
    description: 'The created tag version (e.g., v1.2.3)'
  previous-version:
    description: 'The previous tag version'
  version-type:
    description: 'The version bump type (major, minor, patch, rc)'

runs:
  using: 'node20'
  main: 'dist/index.js'

branding:
  icon: 'tag'
  color: 'blue'
```

### 5.2 auto-tag.yml (Workflow)

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
          fetch-depth: 0  # Full history for tag detection

      - name: Run Auto Tag Action
        id: auto-tag
        uses: ./.github/actions/auto-tag
        with:
          token: ${{ secrets.GITHUB_TOKEN }}

      - name: Summary
        run: |
          echo "## Auto Tag Result" >> $GITHUB_STEP_SUMMARY
          echo "- **Version**: ${{ steps.auto-tag.outputs.version }}" >> $GITHUB_STEP_SUMMARY
          echo "- **Previous**: ${{ steps.auto-tag.outputs.previous-version }}" >> $GITHUB_STEP_SUMMARY
          echo "- **Type**: ${{ steps.auto-tag.outputs.version-type }}" >> $GITHUB_STEP_SUMMARY
```

### 5.3 version.yml (Default Configuration)

```yaml
# Semantic Versioning Branch Prefix Configuration
# This file defines the mapping between branch prefixes and version bump types
# for automatic Git tagging in GitHub Actions.

versioning:
  # Branch prefix to version type mapping
  # Each version type can have multiple prefixes
  branch_prefixes:
    # Major version bump (X.0.0)
    # Used for breaking changes or major releases
    major:
      - "major/"

    # Minor version bump (0.X.0)
    # Used for new features that are backwards compatible
    minor:
      - "release/"

    # Patch version bump (0.0.X)
    # Used for bug fixes and small improvements
    patch:
      - "feature/"

    # Note: Any branches that don't match the prefixes above
    # will default to RC (0.0.0-rc.X)
```

---

## 6. Algorithm Details

### 6.1 Branch Name Parsing

```
Input:  "feature/tanaka/#123/add-login-feature"

Pattern: {type}/{assignee}/#{issue}/{description}

Result:
  type: "feature"
  assignee: "tanaka"
  issueNumber: 123
  description: "add-login-feature"
  raw: "feature/tanaka/#123/add-login-feature"
```

**Regex Pattern:**
```typescript
const BRANCH_PATTERN = /^([^/]+)\/([^/]+)\/#?(\d+)\/(.+)$/;
```

### 6.2 Version Type Detection

```typescript
function detectVersionType(branchInfo: BranchInfo, config: VersionConfig): VersionType {
  const { branch_prefixes } = config.versioning;
  const branchPrefix = `${branchInfo.type}/`;

  if (branch_prefixes.major.some(p => branchPrefix.startsWith(p))) {
    return 'major';
  }
  if (branch_prefixes.minor.some(p => branchPrefix.startsWith(p))) {
    return 'minor';
  }
  if (branch_prefixes.patch.some(p => branchPrefix.startsWith(p))) {
    return 'patch';
  }
  return 'rc';
}
```

### 6.3 Version Calculation

```typescript
function calculateNextVersion(
  current: VersionInfo | null,
  type: VersionType,
  existingRcTags: string[] = []
): string {
  // No existing tags - start from v0.0.0
  const base = current ?? { major: 0, minor: 0, patch: 0, prerelease: null };

  switch (type) {
    case 'major':
      return `v${base.major + 1}.0.0`;

    case 'minor':
      return `v${base.major}.${base.minor + 1}.0`;

    case 'patch':
      return `v${base.major}.${base.minor}.${base.patch + 1}`;

    case 'rc': {
      const nextPatch = base.patch + 1;
      const baseVersion = `v${base.major}.${base.minor}.${nextPatch}`;
      const rcNumber = findNextRcNumber(baseVersion, existingRcTags);
      return `${baseVersion}-rc.${rcNumber}`;
    }
  }
}

function findNextRcNumber(baseVersion: string, existingRcTags: string[]): number {
  const rcPattern = new RegExp(`^${escapeRegex(baseVersion)}-rc\\.(\\d+)$`);
  let maxRc = 0;

  for (const tag of existingRcTags) {
    const match = tag.match(rcPattern);
    if (match) {
      maxRc = Math.max(maxRc, parseInt(match[1], 10));
    }
  }

  return maxRc + 1;
}
```

### 6.4 Version Transition Examples

| Current | Type | Next |
|---------|------|------|
| (none) | patch | v0.0.1 |
| v0.0.1 | patch | v0.0.2 |
| v0.0.2 | minor | v0.1.0 |
| v0.1.0 | major | v1.0.0 |
| v1.0.0 | rc | v1.0.1-rc.1 |
| v1.0.1-rc.1 | rc | v1.0.1-rc.2 |
| v1.0.1-rc.2 | patch | v1.0.1 |

---

## 7. Error Handling

### 7.1 Error Categories

| Category | Description | Action |
|----------|-------------|--------|
| Config Error | Invalid version.yml | Use default config, log warning |
| Parse Error | Invalid branch name | Skip tagging, post failure comment |
| Git Error | Tag already exists | Increment version, retry |
| API Error | GitHub API failure | Post failure comment, fail workflow |
| Permission Error | Insufficient permissions | Post failure comment, fail workflow |

### 7.2 Error Messages (PR Comments)

**Success Comment:**
```markdown
## 🏷️ Auto Tag Created

| Item | Value |
|------|-------|
| **Version** | `v1.2.3` |
| **Previous** | `v1.2.2` |
| **Type** | patch |
| **Branch** | `feature/tanaka/#123/add-login` |

Tag created successfully!
```

**Failure Comment:**
```markdown
## ❌ Auto Tag Failed

**Error**: Unable to parse branch name

**Branch**: `invalid-branch-name`

**Expected Format**: `{type}/{assignee}/#{issue}/{description}`

Please ensure your branch follows the naming convention.
```

---

## 8. Testing Strategy

### 8.1 Unit Tests

| Module | Test Cases |
|--------|------------|
| config-loader | Load valid config, handle missing file, validate schema |
| version-detector | Parse various branch formats, detect version types, calculate versions |
| tag-creator | Mock GitHub API, handle errors |
| pr-commenter | Mock comment creation, format messages |

### 8.2 Test Examples

```typescript
// version-detector.test.ts
describe('parseBranchName', () => {
  it('should parse standard branch name', () => {
    const result = parseBranchName('feature/tanaka/#123/add-login');
    expect(result).toEqual({
      type: 'feature',
      assignee: 'tanaka',
      issueNumber: 123,
      description: 'add-login',
      raw: 'feature/tanaka/#123/add-login',
    });
  });

  it('should handle branch without hash in issue number', () => {
    const result = parseBranchName('feature/tanaka/123/add-login');
    expect(result.issueNumber).toBe(123);
  });
});

describe('calculateNextVersion', () => {
  it('should increment major version', () => {
    const current = { major: 1, minor: 2, patch: 3, prerelease: null };
    expect(calculateNextVersion(current, 'major')).toBe('v2.0.0');
  });

  it('should create RC version', () => {
    const current = { major: 1, minor: 0, patch: 0, prerelease: null };
    expect(calculateNextVersion(current, 'rc', [])).toBe('v1.0.1-rc.1');
  });

  it('should increment RC number', () => {
    const current = { major: 1, minor: 0, patch: 0, prerelease: null };
    const existingRcs = ['v1.0.1-rc.1', 'v1.0.1-rc.2'];
    expect(calculateNextVersion(current, 'rc', existingRcs)).toBe('v1.0.1-rc.3');
  });
});
```

---

## 9. Dependencies

### 9.1 Production Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| @actions/core | ^1.10.0 | GitHub Actions toolkit core |
| @actions/github | ^6.0.0 | GitHub API client |
| js-yaml | ^4.1.0 | YAML parsing |

### 9.2 Development Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| typescript | ^5.7.0 | TypeScript compiler |
| @vercel/ncc | ^0.38.0 | Bundle for distribution |
| vitest | ^2.1.0 | Testing framework |
| @vitest/coverage-v8 | ^2.1.0 | Coverage reporting |
| @biomejs/biome | ^1.9.0 | Linting and formatting |
| @types/js-yaml | ^4.0.9 | Type definitions |

---

## 10. Distribution

### 10.1 Build Process

```bash
# Install dependencies
pnpm install

# Build with ncc
pnpm build  # ncc build src/index.ts -o dist

# The dist/index.js is the single-file bundle
```

### 10.2 setup.sh Integration

New plugin: `templates/github-actions/plugin.sh`

```bash
plugin_name() {
    echo "github-actions"
}

plugin_description() {
    echo "GitHub Actions templates including auto-tag"
}

plugin_copy() {
    local target_dir="$1"

    # Copy auto-tag action
    mkdir -p "${target_dir}/.github/actions"
    cp -r "${PLUGIN_DIR}/.github/actions/auto-tag" "${target_dir}/.github/actions/"

    # Copy workflow
    mkdir -p "${target_dir}/.github/workflows"
    cp "${PLUGIN_DIR}/.github/workflows/auto-tag.yml" "${target_dir}/.github/workflows/"

    # Copy default config
    cp "${PLUGIN_DIR}/.github/version.yml" "${target_dir}/.github/"
}
```

---

## 11. Security Considerations

### 11.1 Token Permissions

Required permissions:
- `contents: write` - Create tags
- `pull-requests: write` - Post comments

### 11.2 Input Validation

- Branch names are validated against expected pattern
- Configuration file is validated against schema
- Version strings are sanitized before tag creation

### 11.3 Rate Limiting

- GitHub API rate limits are respected
- Retry logic with exponential backoff for transient failures

---

## 12. Future Considerations

### 12.1 Potential Enhancements

1. **Changelog Generation** - Auto-generate CHANGELOG.md
2. **Release Creation** - Optional GitHub Release creation
3. **Slack Notification** - Post to Slack on tag creation
4. **Custom Tag Format** - Support for custom tag prefixes
5. **Branch Protection** - Validate against protected branches

### 12.2 Breaking Changes Policy

Major version bumps for:
- Changes to action inputs/outputs
- Changes to configuration schema
- Changes to default behavior

---

## Appendix A: Example Scenarios

### Scenario 1: First Feature Branch

```
Branch: feature/tanaka/#1/initial-setup
Latest Tag: (none)
Config: default

Result:
  Version Type: patch
  New Tag: v0.0.1
```

### Scenario 2: Release Branch

```
Branch: release/tanaka/#10/version-1-0
Latest Tag: v0.5.3
Config: default

Result:
  Version Type: minor
  New Tag: v0.6.0
```

### Scenario 3: Bugfix Branch (RC)

```
Branch: bugfix/tanaka/#15/fix-login
Latest Tag: v1.0.0
Config: default

Result:
  Version Type: rc
  New Tag: v1.0.1-rc.1
```

### Scenario 4: Major Breaking Change

```
Branch: major/tanaka/#20/v2-migration
Latest Tag: v1.5.2
Config: default

Result:
  Version Type: major
  New Tag: v2.0.0
```
