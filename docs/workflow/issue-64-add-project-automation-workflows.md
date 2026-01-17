# Implementation Workflow: Issue #64 - Add Project Automation Workflows and Label Setup

## Phase 1: Add project-automation/action.yml

**Files to create:**
- `.github/actions/project-automation/action.yml`

**Steps:**
1. Copy content from `templates/github-actions/.github/actions/project-automation/action.yml`
2. Verify the file references `dist/index.js` correctly

## Phase 2: Add Workflow Files

**Files to create:**
- `.github/workflows/project-automation.yml`
- `.github/workflows/pr-status-update.yml`

**Steps:**
1. Create project-automation.yml with `issues: [opened]` trigger
2. Create pr-status-update.yml with `pull_request: [opened, reopened]` trigger
3. Both workflows use PROJECT_TOKEN secret

## Phase 3: Add Configuration File

**Files to create:**
- `.github/project-automation.yml`

**Steps:**
1. Create config with TE-ToshiakiTanaka2 organization, project #3
2. Set default Status to "Ready"

## Phase 4: Add Label Setup to setup.sh

**Files to modify:**
- `setup.sh`

**Steps:**
1. Add `setup_github_labels()` function after GitHub auth functions
2. Define labels array with name, color, description
3. Loop through labels and create using `gh label create`
4. Handle existing labels gracefully (skip on error)
5. Call function from `setup_github_repository()`

## Phase 5: Testing

**Commands:**
```bash
# Lint shell scripts
shellcheck setup.sh

# Lint workflow files
actionlint .github/workflows/*.yml

# Test setup.sh dry-run
./setup.sh --dry-run
```

## Phase 6: Commit Strategy

1. `feat: add project-automation action.yml`
2. `feat: add project-automation and pr-status-update workflows`
3. `feat: add project-automation configuration`
4. `feat: add automatic label setup to setup.sh`
5. `docs: add design and workflow documents for issue #64`

## Rollback Plan

If issues occur:
1. Remove added files with `git checkout develop -- <file>`
2. Revert setup.sh changes
3. Delete branch and recreate from develop
