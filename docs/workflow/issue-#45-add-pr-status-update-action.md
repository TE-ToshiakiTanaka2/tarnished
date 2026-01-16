# Implementation Workflow: PR Status Update GitHub Action

**Issue**: #45
**Title**: Add PR status update GitHub Action for automatic project status change
**Date**: 2026-01-16

## Phase Overview

| Phase | Description | Dependencies |
|-------|-------------|--------------|
| 1 | Project Setup | None |
| 2 | Core Logic Implementation | Phase 1 |
| 3 | Integration & Entry Point | Phase 2 |
| 4 | Testing | Phase 3 |
| 5 | Build & Distribution | Phase 4 |
| 6 | Documentation & Cleanup | Phase 5 |

## Phase 1: Project Setup

### Task 1.1: Create Action Directory Structure

```bash
mkdir -p .github/actions/pr-status-update/src/{graphql,project}
mkdir -p .github/actions/pr-status-update/__tests__
```

### Task 1.2: Create package.json

Create `.github/actions/pr-status-update/package.json` with same dependencies as `project-automation`.

### Task 1.3: Create tsconfig.json

Copy from `project-automation` with same configuration.

### Task 1.4: Create vitest.config.ts

Copy from `project-automation`.

### Task 1.5: Create action.yml

Define action inputs, outputs, and runtime configuration.

**Checkpoint**: Directory structure and configuration files in place.

---

## Phase 2: Core Logic Implementation

### Task 2.1: Copy Shared Modules

Copy the following from `project-automation`:
- `src/graphql/client.ts`
- `src/graphql/queries.ts`
- `src/graphql/mutations.ts`
- `src/project/finder.ts`
- `src/project/item.ts`
- `src/project/fields.ts`
- `src/types.ts`

### Task 2.2: Extend Types (`types.ts`)

Add new types for:
- `ExtendedProjectConfig` (includes `pr` section)
- `DetectedIssues` interface
- `GetIssueResponse` for Issue node ID lookup

### Task 2.3: Extend Configuration (`config.ts`)

Create new `config.ts` that:
- Extends the existing config loader
- Validates the new `pr` section
- Provides defaults for optional fields

### Task 2.4: Implement Issue Detection (`issue-detector.ts`)

Create `issue-detector.ts` with:
- `detectIssuesFromKeywords(title: string, body: string): number[]`
- `detectIssuesFromBranch(branchName: string, pattern?: string): number[]`
- `detectIssues(pr: PullRequest, branchPattern?: string): DetectedIssues`

### Task 2.5: Add Issue Node ID Query

Add to `graphql/queries.ts`:
- `GET_ISSUE_BY_NUMBER` query to get Issue node ID from number

**Checkpoint**: All core logic modules implemented.

---

## Phase 3: Integration & Entry Point

### Task 3.1: Create Main Entry Point (`index.ts`)

Implement the main workflow:
1. Parse inputs
2. Load configuration
3. Get PR context
4. Detect issues
5. Find project
6. Process each issue (add to project if needed, update status)
7. Set outputs

### Task 3.2: Error Handling

Implement graceful error handling:
- Wrap issue processing in try-catch
- Log warnings instead of failing
- Continue processing remaining issues

**Checkpoint**: Action is functionally complete.

---

## Phase 4: Testing

### Task 4.1: Unit Tests for Issue Detection

Create `__tests__/issue-detector.test.ts`:
- Test keyword detection with various formats
- Test branch pattern detection
- Test combined detection
- Test edge cases (empty, no match, duplicates)

### Task 4.2: Unit Tests for Configuration

Create `__tests__/config.test.ts`:
- Test loading config with PR section
- Test loading config without PR section (backward compatible)
- Test validation errors

### Task 4.3: Run Tests

```bash
cd .github/actions/pr-status-update
npm install
npm test
```

**Checkpoint**: All tests passing.

---

## Phase 5: Build & Distribution

### Task 5.1: Install Dependencies

```bash
cd .github/actions/pr-status-update
npm install
```

### Task 5.2: Build Action

```bash
npm run build
```

### Task 5.3: Copy to Templates

Copy built files to templates directory:

```bash
# Create directories
mkdir -p templates/github-actions/.github/actions/pr-status-update/dist

# Copy action.yml
cp .github/actions/pr-status-update/action.yml \
   templates/github-actions/.github/actions/pr-status-update/

# Copy dist folder
cp -r .github/actions/pr-status-update/dist/* \
   templates/github-actions/.github/actions/pr-status-update/dist/
```

### Task 5.4: Create Workflow Template

Create `templates/github-actions/.github/workflows/pr-status-update.yml`.

### Task 5.5: Update version.yml

Add pr-status-update to version tracking.

**Checkpoint**: Distribution files in place.

---

## Phase 6: Documentation & Cleanup

### Task 6.1: Verify plugin.sh

Check if `templates/github-actions/plugin.sh` needs updates to copy new action.

### Task 6.2: Final Code Review

- Check for TypeScript errors: `npm run typecheck`
- Check code style consistency
- Verify all files are committed

### Task 6.3: Commit All Changes

Create final commit with all implementation files.

**Checkpoint**: Implementation complete.

---

## Commit Strategy

| Commit | Description | Files |
|--------|-------------|-------|
| 1 | docs: add design and workflow documents | `docs/design/*`, `docs/workflow/*` |
| 2 | feat(pr-status-update): add project structure | `action.yml`, `package.json`, `tsconfig.json` |
| 3 | feat(pr-status-update): add shared modules | `src/graphql/*`, `src/project/*`, `src/types.ts` |
| 4 | feat(pr-status-update): add issue detection | `src/issue-detector.ts`, `src/config.ts` |
| 5 | feat(pr-status-update): add main entry point | `src/index.ts` |
| 6 | test(pr-status-update): add unit tests | `__tests__/*` |
| 7 | build(pr-status-update): add distribution | `templates/github-actions/*` |

---

## Rollback Plan

If issues are discovered after deployment:

1. **Immediate**: Disable the workflow in consuming repositories
2. **Short-term**: Fix the issue in a new branch
3. **Long-term**: Consider adding feature flags for gradual rollout

---

## Success Criteria

- [ ] All unit tests pass
- [ ] TypeScript compiles without errors
- [ ] Action runs successfully on PR events
- [ ] Issues are correctly detected from keywords and branch names
- [ ] Status is updated in GitHub Project
- [ ] Build artifacts are properly placed in templates
- [ ] Backward compatible with existing configuration
