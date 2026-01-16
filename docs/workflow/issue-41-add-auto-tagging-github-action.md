# Implementation Workflow: Auto-Tag GitHub Action

**Issue**: #41 - Add auto-tagging GitHub Action on PR merge
**Design Doc**: [issue-41-add-auto-tagging-github-action.md](../design/issue-41-add-auto-tagging-github-action.md)
**Date**: 2026-01-16

---

## Overview

このワークフローは、PRマージ時に自動でSemantic Versioningタグを作成するGitHub Actionsカスタムアクションの実装手順を定義します。

---

## Phase 1: Project Foundation

### 1.1 Create Directory Structure

**Task**: アクションのディレクトリ構造を作成

```bash
mkdir -p .github/actions/auto-tag/src
mkdir -p .github/actions/auto-tag/__tests__
```

**Files to create:**
- [ ] `.github/actions/auto-tag/package.json`
- [ ] `.github/actions/auto-tag/tsconfig.json`
- [ ] `.github/actions/auto-tag/vitest.config.ts`
- [ ] `.github/actions/auto-tag/biome.json`
- [ ] `.github/actions/auto-tag/action.yml`

**Commit**: `✨ feat(auto-tag): initialize project structure`

---

### 1.2 Configure package.json

**Dependencies:**
```json
{
  "dependencies": {
    "@actions/core": "^1.10.0",
    "@actions/github": "^6.0.0",
    "js-yaml": "^4.1.0"
  },
  "devDependencies": {
    "@biomejs/biome": "^1.9.0",
    "@types/js-yaml": "^4.0.9",
    "@types/node": "^22.0.0",
    "@vercel/ncc": "^0.38.0",
    "@vitest/coverage-v8": "^2.1.0",
    "typescript": "^5.7.0",
    "vitest": "^2.1.0"
  }
}
```

**Scripts:**
```json
{
  "scripts": {
    "build": "ncc build src/index.ts -o dist --source-map --license licenses.txt",
    "lint": "biome check .",
    "lint:fix": "biome check --write .",
    "typecheck": "tsc --noEmit",
    "test": "vitest run",
    "test:watch": "vitest",
    "test:coverage": "vitest run --coverage"
  }
}
```

---

### 1.3 Configure TypeScript

**tsconfig.json:**
```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "outDir": "./dist",
    "rootDir": "./src",
    "declaration": true,
    "sourceMap": true
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "dist", "__tests__"]
}
```

---

### 1.4 Configure Vitest

**vitest.config.ts:**
```typescript
import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    include: ['__tests__/**/*.test.ts'],
    globals: true,
    coverage: {
      provider: 'v8',
      reporter: ['text', 'json', 'html'],
      exclude: ['node_modules', 'dist', '__tests__'],
    },
  },
});
```

---

### 1.5 Configure Biome

**biome.json:**
```json
{
  "$schema": "https://biomejs.dev/schemas/1.9.0/schema.json",
  "organizeImports": { "enabled": true },
  "linter": {
    "enabled": true,
    "rules": { "recommended": true }
  },
  "formatter": {
    "enabled": true,
    "indentStyle": "space",
    "indentWidth": 2
  }
}
```

---

### 1.6 Create action.yml

```yaml
name: 'Auto Tag on PR Merge'
description: 'Automatically create semantic version tags based on branch type'
author: 'tarnished'

inputs:
  token:
    description: 'GitHub token'
    required: true
    default: ${{ github.token }}

outputs:
  version:
    description: 'Created tag version'
  previous-version:
    description: 'Previous tag version'
  version-type:
    description: 'Version bump type'

runs:
  using: 'node20'
  main: 'dist/index.js'

branding:
  icon: 'tag'
  color: 'blue'
```

**Commit**: `✨ feat(auto-tag): add project configuration files`

---

## Phase 2: Core Type Definitions

### 2.1 Create types.ts

**File**: `.github/actions/auto-tag/src/types.ts`

```typescript
export type VersionType = 'major' | 'minor' | 'patch' | 'rc';

export interface BranchInfo {
  type: string;
  assignee: string;
  issueNumber: number | null;
  description: string;
  raw: string;
}

export interface VersionInfo {
  major: number;
  minor: number;
  patch: number;
  prerelease: string | null;
}

export interface VersionConfig {
  versioning: {
    branch_prefixes: {
      major: string[];
      minor: string[];
      patch: string[];
    };
  };
}

export interface TagResult {
  success: boolean;
  version: string;
  sha: string;
  error?: string;
}

export const DEFAULT_CONFIG: VersionConfig = {
  versioning: {
    branch_prefixes: {
      major: ['major/'],
      minor: ['release/'],
      patch: ['feature/'],
    },
  },
};
```

**Commit**: `✨ feat(auto-tag): add TypeScript type definitions`

---

## Phase 3: Config Loader Implementation

### 3.1 Implement config-loader.ts

**File**: `.github/actions/auto-tag/src/config-loader.ts`

**Functions:**
1. `loadConfig(configPath?: string): Promise<VersionConfig>`
2. `validateConfig(config: unknown): config is VersionConfig`
3. `getDefaultConfig(): VersionConfig`

**Logic:**
1. Check if `.github/version.yml` exists
2. Parse YAML content with js-yaml
3. Validate against schema
4. Return config or default

**Commit**: `✨ feat(auto-tag): implement configuration loader`

---

### 3.2 Write config-loader tests

**File**: `.github/actions/auto-tag/__tests__/config-loader.test.ts`

**Test Cases:**
- [ ] Load valid configuration file
- [ ] Return default config when file not found
- [ ] Handle invalid YAML syntax
- [ ] Validate config schema
- [ ] Handle partial config (merge with defaults)

**Commit**: `✅ test(auto-tag): add config-loader unit tests`

---

## Phase 4: Version Detector Implementation

### 4.1 Implement version-detector.ts

**File**: `.github/actions/auto-tag/src/version-detector.ts`

**Functions:**
1. `parseBranchName(branch: string): BranchInfo`
2. `detectVersionType(branchInfo: BranchInfo, config: VersionConfig): VersionType`
3. `parseVersion(version: string): VersionInfo`
4. `getLatestTag(): Promise<string | null>`
5. `getRcTags(baseVersion: string): Promise<string[]>`
6. `calculateNextVersion(current: VersionInfo | null, type: VersionType, rcTags?: string[]): string`

**Branch Parsing Regex:**
```typescript
const BRANCH_PATTERN = /^([^/]+)\/([^/]+)\/#?(\d+)\/(.+)$/;
```

**Version Parsing Regex:**
```typescript
const VERSION_PATTERN = /^v?(\d+)\.(\d+)\.(\d+)(?:-(.+))?$/;
```

**Commit**: `✨ feat(auto-tag): implement version detection logic`

---

### 4.2 Write version-detector tests

**File**: `.github/actions/auto-tag/__tests__/version-detector.test.ts`

**Test Cases:**

**parseBranchName:**
- [ ] Parse standard format: `feature/user/#123/description`
- [ ] Parse without hash: `feature/user/123/description`
- [ ] Handle complex descriptions with hyphens
- [ ] Return null values for invalid format

**detectVersionType:**
- [ ] Detect major from `major/` prefix
- [ ] Detect minor from `release/` prefix
- [ ] Detect patch from `feature/` prefix
- [ ] Default to rc for unknown prefixes

**parseVersion:**
- [ ] Parse `v1.2.3`
- [ ] Parse `1.2.3` (without v)
- [ ] Parse `v1.2.3-rc.1`
- [ ] Handle invalid version strings

**calculateNextVersion:**
- [ ] Major: v1.2.3 → v2.0.0
- [ ] Minor: v1.2.3 → v1.3.0
- [ ] Patch: v1.2.3 → v1.2.4
- [ ] RC first: v1.2.3 → v1.2.4-rc.1
- [ ] RC increment: existing rc.1 → v1.2.4-rc.2
- [ ] Initial version (no tags): → v0.0.1

**Commit**: `✅ test(auto-tag): add version-detector unit tests`

---

## Phase 5: Tag Creator Implementation

### 5.1 Implement tag-creator.ts

**File**: `.github/actions/auto-tag/src/tag-creator.ts`

**Functions:**
1. `createTag(version: string, sha: string, token: string): Promise<TagResult>`

**Logic:**
1. Get GitHub context (owner, repo)
2. Create tag reference via GitHub API
3. Return success/failure result

**GitHub API:**
```typescript
await octokit.rest.git.createRef({
  owner,
  repo,
  ref: `refs/tags/${version}`,
  sha,
});
```

**Commit**: `✨ feat(auto-tag): implement tag creation logic`

---

### 5.2 Write tag-creator tests

**File**: `.github/actions/auto-tag/__tests__/tag-creator.test.ts`

**Test Cases:**
- [ ] Create tag successfully (mock API)
- [ ] Handle API errors
- [ ] Handle duplicate tag error

**Commit**: `✅ test(auto-tag): add tag-creator unit tests`

---

## Phase 6: PR Commenter Implementation

### 6.1 Implement pr-commenter.ts

**File**: `.github/actions/auto-tag/src/pr-commenter.ts`

**Functions:**
1. `postSuccessComment(prNumber, version, previousVersion, versionType, token): Promise<void>`
2. `postFailureComment(prNumber, error, token): Promise<void>`

**Success Comment Template:**
```markdown
## 🏷️ Auto Tag Created

| Item | Value |
|------|-------|
| **Version** | `{version}` |
| **Previous** | `{previousVersion}` |
| **Type** | {versionType} |

Tag created successfully!
```

**Failure Comment Template:**
```markdown
## ❌ Auto Tag Failed

**Error**: {error}

Please check the workflow logs for details.
```

**Commit**: `✨ feat(auto-tag): implement PR comment posting`

---

### 6.2 Write pr-commenter tests

**File**: `.github/actions/auto-tag/__tests__/pr-commenter.test.ts`

**Test Cases:**
- [ ] Post success comment (mock API)
- [ ] Post failure comment (mock API)
- [ ] Handle API errors gracefully

**Commit**: `✅ test(auto-tag): add pr-commenter unit tests`

---

## Phase 7: Entry Point Implementation

### 7.1 Implement index.ts

**File**: `.github/actions/auto-tag/src/index.ts`

**Main Flow:**
```typescript
async function run(): Promise<void> {
  try {
    // 1. Get inputs
    const token = core.getInput('token', { required: true });

    // 2. Get PR context
    const context = github.context;
    const prNumber = context.payload.pull_request?.number;
    const branchName = context.payload.pull_request?.head.ref;
    const sha = context.payload.pull_request?.merge_commit_sha;

    // 3. Validate context
    if (!prNumber || !branchName || !sha) {
      throw new Error('Missing PR context');
    }

    // 4. Load configuration
    const config = await loadConfig();

    // 5. Parse branch and detect version type
    const branchInfo = parseBranchName(branchName);
    const versionType = detectVersionType(branchInfo, config);

    // 6. Get latest tag and calculate next version
    const latestTag = await getLatestTag();
    const currentVersion = latestTag ? parseVersion(latestTag) : null;
    const rcTags = versionType === 'rc' ? await getRcTags(/*...*/) : [];
    const nextVersion = calculateNextVersion(currentVersion, versionType, rcTags);

    // 7. Create tag
    const result = await createTag(nextVersion, sha, token);

    // 8. Post comment and set outputs
    if (result.success) {
      await postSuccessComment(prNumber, nextVersion, latestTag, versionType, token);
      core.setOutput('version', nextVersion);
      core.setOutput('previous-version', latestTag || '');
      core.setOutput('version-type', versionType);
    } else {
      throw new Error(result.error);
    }
  } catch (error) {
    // Handle errors
    await postFailureComment(prNumber, error.message, token);
    core.setFailed(error.message);
  }
}

run();
```

**Commit**: `✨ feat(auto-tag): implement main entry point`

---

## Phase 8: Build and Bundle

### 8.1 Install dependencies and build

```bash
cd .github/actions/auto-tag
pnpm install
pnpm build
```

**Verify:**
- [ ] `dist/index.js` generated
- [ ] No TypeScript errors
- [ ] Bundle size reasonable

**Commit**: `🔧 build(auto-tag): add compiled distribution`

---

## Phase 9: Workflow and Configuration

### 9.1 Create auto-tag.yml workflow

**File**: `.github/workflows/auto-tag.yml`

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

      - name: Summary
        run: |
          echo "## Auto Tag Result" >> $GITHUB_STEP_SUMMARY
          echo "- **Version**: ${{ steps.auto-tag.outputs.version }}" >> $GITHUB_STEP_SUMMARY
          echo "- **Previous**: ${{ steps.auto-tag.outputs.previous-version }}" >> $GITHUB_STEP_SUMMARY
          echo "- **Type**: ${{ steps.auto-tag.outputs.version-type }}" >> $GITHUB_STEP_SUMMARY
```

**Commit**: `✨ feat(auto-tag): add workflow definition`

---

### 9.2 Create default version.yml

**File**: `.github/version.yml`

```yaml
# Semantic Versioning Branch Prefix Configuration
versioning:
  branch_prefixes:
    major:
      - "major/"
    minor:
      - "release/"
    patch:
      - "feature/"
```

**Commit**: `✨ feat(auto-tag): add default version configuration`

---

## Phase 10: Template Integration

### 10.1 Create github-actions plugin

**File**: `templates/github-actions/plugin.sh`

```bash
#!/bin/bash

plugin_name() {
    echo "github-actions"
}

plugin_description() {
    echo "GitHub Actions templates including auto-tag"
}

plugin_copy() {
    local target_dir="$1"
    local plugin_dir
    plugin_dir="$(dirname "${BASH_SOURCE[0]}")"

    # Copy auto-tag action
    mkdir -p "${target_dir}/.github/actions"
    cp -r "${plugin_dir}/.github/actions/auto-tag" "${target_dir}/.github/actions/"

    # Copy workflow
    mkdir -p "${target_dir}/.github/workflows"
    cp "${plugin_dir}/.github/workflows/auto-tag.yml" "${target_dir}/.github/workflows/"

    # Copy default config
    cp "${plugin_dir}/.github/version.yml" "${target_dir}/.github/"

    print_success "GitHub Actions templates copied"
}
```

**Commit**: `✨ feat(setup): add github-actions plugin for template distribution`

---

### 10.2 Update setup.sh (if needed)

Add github-actions to optional plugins or core plugins based on requirements.

---

## Phase 11: Documentation

### 11.1 Create README for auto-tag action

**File**: `.github/actions/auto-tag/README.md`

Contents:
- Usage instructions
- Configuration options
- Branch naming conventions
- Version mapping examples
- Troubleshooting guide

**Commit**: `📝 docs(auto-tag): add README documentation`

---

## Phase 12: Final Testing and Validation

### 12.1 Run all tests

```bash
cd .github/actions/auto-tag
pnpm test:coverage
```

**Verify:**
- [ ] All tests passing
- [ ] Coverage > 80%

---

### 12.2 Lint and format

```bash
pnpm lint
pnpm typecheck
```

**Verify:**
- [ ] No lint errors
- [ ] No type errors

---

### 12.3 Local workflow test (optional)

```bash
act pull_request -e test-event.json --dryrun
```

---

## Commit History Summary

| Phase | Commit Message |
|-------|----------------|
| 1 | `✨ feat(auto-tag): initialize project structure` |
| 1 | `✨ feat(auto-tag): add project configuration files` |
| 2 | `✨ feat(auto-tag): add TypeScript type definitions` |
| 3 | `✨ feat(auto-tag): implement configuration loader` |
| 3 | `✅ test(auto-tag): add config-loader unit tests` |
| 4 | `✨ feat(auto-tag): implement version detection logic` |
| 4 | `✅ test(auto-tag): add version-detector unit tests` |
| 5 | `✨ feat(auto-tag): implement tag creation logic` |
| 5 | `✅ test(auto-tag): add tag-creator unit tests` |
| 6 | `✨ feat(auto-tag): implement PR comment posting` |
| 6 | `✅ test(auto-tag): add pr-commenter unit tests` |
| 7 | `✨ feat(auto-tag): implement main entry point` |
| 8 | `🔧 build(auto-tag): add compiled distribution` |
| 9 | `✨ feat(auto-tag): add workflow definition` |
| 9 | `✨ feat(auto-tag): add default version configuration` |
| 10 | `✨ feat(setup): add github-actions plugin for template distribution` |
| 11 | `📝 docs(auto-tag): add README documentation` |

---

## Dependencies and Critical Path

```
Phase 1 (Foundation)
    │
    ▼
Phase 2 (Types) ──────────────────────┐
    │                                  │
    ▼                                  │
Phase 3 (Config) ◄─────────────────────┤
    │                                  │
    ▼                                  │
Phase 4 (Version) ◄────────────────────┤
    │                                  │
    ▼                                  │
Phase 5 (Tag) ◄────────────────────────┤
    │                                  │
    ▼                                  │
Phase 6 (Comment) ◄────────────────────┘
    │
    ▼
Phase 7 (Entry Point)
    │
    ▼
Phase 8 (Build)
    │
    ├─────────────────┐
    ▼                 ▼
Phase 9 (Workflow)   Phase 10 (Template)
    │                 │
    └────────┬────────┘
             ▼
     Phase 11 (Docs)
             │
             ▼
     Phase 12 (Validation)
```

---

## Rollback Plan

各フェーズでコミットを行うため、問題発生時は該当コミットまでリバート可能。

```bash
# Revert to specific commit
git revert <commit-hash>

# Or reset to previous state
git reset --hard <commit-hash>
```

---

## Success Criteria

- [ ] 全テストがパス
- [ ] カバレッジ80%以上
- [ ] TypeScriptエラーなし
- [ ] Lintエラーなし
- [ ] ワークフローが正常にトリガー
- [ ] PRマージ時にタグが作成される
- [ ] PRにコメントが投稿される
