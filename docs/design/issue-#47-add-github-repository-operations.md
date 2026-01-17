# Design Document: GitHub Repository Operations for setup.sh

## Issue Reference
- **Issue**: #47
- **Title**: Add GitHub repository operations to setup.sh for develop branch workflow

## Overview

setup.shにGitHub Repository操作機能を追加し、開発環境セットアップの初期段階でdevelopブランチベースの開発フローを自動構築する。

## Architecture

### Module Structure

```
setup.sh
├── [NEW] GitHub Operations Module
│   ├── check_gh_auth()           # GitHub CLI認証確認
│   ├── setup_develop_branch()    # developブランチ処理
│   ├── set_default_branch()      # default branch変更
│   └── auto_commit()             # 自動コミット
│
├── [EXISTING] Plugin System
│   ├── plugin_pre_copy
│   ├── plugin_copy
│   ├── plugin_post_copy
│   └── plugin_validate
│
└── [EXISTING] Setup Flow
    ├── Language Selection
    ├── Template Processing
    └── Finalization
```

### Integration Point

GitHub操作は既存のsetup.shフローの**最初**に実行される：

```
[NEW] GitHub Operations
    ↓
[EXISTING] Devcontainer Setup
    ↓
[EXISTING] Language Selection
    ↓
[EXISTING] Plugin Processing
    ↓
[NEW] Auto Commit (各ステップ後)
```

## Component Design

### 1. GitHub CLI Authentication (`check_gh_auth`)

**責務**: GitHub CLIの認証状態を確認し、未認証の場合は認証フローを開始

```bash
check_gh_auth() {
    print_info "Checking GitHub CLI authentication..."

    if ! command -v gh &> /dev/null; then
        print_error "GitHub CLI (gh) is not installed"
        print_info "Please install: https://cli.github.com/"
        return 1
    fi

    if ! gh auth status &>/dev/null; then
        print_warning "GitHub CLI is not authenticated"
        print_info "Starting authentication flow..."
        if ! gh auth login; then
            print_error "GitHub authentication failed"
            return 1
        fi
    fi

    print_success "GitHub CLI authenticated"
    return 0
}
```

**エラーハンドリング**:
- `gh`コマンドが存在しない → エラー終了
- 認証失敗 → エラー終了（GitHub操作が必須のため）

### 2. Develop Branch Setup (`setup_develop_branch`)

**責務**: developブランチの存在確認・作成・checkout

```bash
setup_develop_branch() {
    print_info "Setting up develop branch..."

    # Check if we're in a git repository
    if ! git rev-parse --git-dir &>/dev/null; then
        print_error "Not a git repository"
        return 1
    fi

    # Check if develop branch exists locally
    if git show-ref --verify --quiet refs/heads/develop; then
        print_info "Develop branch exists locally, checking out..."
        git checkout develop
    # Check if develop branch exists on remote
    elif git show-ref --verify --quiet refs/remotes/origin/develop; then
        print_info "Develop branch exists on remote, checking out..."
        git checkout -b develop origin/develop
    else
        print_info "Creating new develop branch..."
        git checkout -b develop
    fi

    print_success "Now on develop branch"
    return 0
}
```

**ブランチ存在確認の優先順位**:
1. ローカルに存在 → checkout
2. リモートに存在 → tracking branchとしてcheckout
3. 存在しない → 新規作成

### 3. Default Branch Configuration (`set_default_branch`)

**責務**: GitHub上のdefault branchをdevelopに変更

```bash
set_default_branch() {
    print_info "Setting develop as default branch on GitHub..."

    # Try to set default branch
    if gh repo edit --default-branch develop 2>/dev/null; then
        print_success "Default branch set to develop"
    else
        print_warning "Could not set default branch (insufficient permissions)"
        print_info "Pushing develop branch to remote..."
        git push -u origin develop
        print_info "Please manually set develop as default branch in repository settings"
    fi

    return 0
}
```

**権限エラー時の処理**:
- 警告を表示してスキップ
- developブランチをpush
- 手動設定を促すメッセージを表示
- セットアップは継続

### 4. Auto Commit (`auto_commit`)

**責務**: 変更を自動コミット

```bash
auto_commit() {
    local message="$1"

    # Check if there are changes to commit
    if git diff --quiet && git diff --cached --quiet; then
        print_info "No changes to commit"
        return 0
    fi

    git add -A
    if git commit -m "$message"; then
        print_success "Committed: $message"
    else
        print_warning "Nothing to commit"
    fi

    return 0
}
```

**コミットメッセージ形式** (Conventional Commits):
- `feat: initialize devcontainer environment`
- `feat: configure <language> development environment`
- `chore: add development tools configuration`

## Processing Flow

### Complete Flow Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    setup.sh execution                        │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│ [1] check_gh_auth()                                         │
│     ├── Check gh command exists                             │
│     ├── Check authentication status                         │
│     └── Run gh auth login if needed                         │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│ [2] setup_develop_branch()                                  │
│     ├── Check if git repository                             │
│     ├── Check local develop branch                          │
│     ├── Check remote develop branch                         │
│     └── Create or checkout develop                          │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│ [3] set_default_branch()                                    │
│     ├── Try gh repo edit --default-branch                   │
│     └── Fallback: push develop, show manual instruction     │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│ [4] Existing Setup Flow                                     │
│     ├── Language selection                                  │
│     ├── Plugin loading                                      │
│     ├── Plugin hooks execution                              │
│     └── Template processing                                 │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│ [5] auto_commit() after each major step                     │
│     ├── After devcontainer setup                            │
│     ├── After language configuration                        │
│     └── After final configuration                           │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│ [6] Completion                                              │
│     └── Show success message with branch info               │
└─────────────────────────────────────────────────────────────┘
```

## File Modifications

### Modified Files

| File | Modification |
|------|-------------|
| `setup.sh` | Add GitHub operations functions and integration |
| `scripts/lib/common.sh` | Add git/GitHub utility functions |

### New Functions in setup.sh

```bash
# GitHub Operations
check_gh_auth()
setup_develop_branch()
set_default_branch()
auto_commit()

# Integration function
setup_github_repository()
```

## Error Handling Strategy

| Error | Behavior | Reason |
|-------|----------|--------|
| `gh` not installed | Exit with error | Required dependency |
| `gh auth` failed | Exit with error | GitHub operations required |
| Not a git repo | Exit with error | Cannot proceed without git |
| `gh repo edit` failed | Warning, continue | Permissions may vary |
| `git push` failed | Warning, continue | Network issues, etc. |

## Test Strategy

### Unit Tests

1. **check_gh_auth**
   - Test with authenticated state
   - Test with unauthenticated state (mock)

2. **setup_develop_branch**
   - Test with existing local branch
   - Test with existing remote branch
   - Test with no existing branch

3. **set_default_branch**
   - Test with sufficient permissions
   - Test with insufficient permissions

4. **auto_commit**
   - Test with changes
   - Test without changes

### Integration Tests

1. Full flow in a test repository
2. Error recovery scenarios
3. Dry-run mode verification

## Dependencies

### Required
- `git` - Version control
- `gh` - GitHub CLI

### Existing
- `jq` - JSON processing (already required)

## Commit Messages

For this implementation:

```
feat(setup): add GitHub CLI authentication check
feat(setup): add develop branch setup functionality
feat(setup): add default branch configuration
feat(setup): add auto commit functionality
feat(setup): integrate GitHub operations into setup flow
docs: add design document for GitHub repository operations
```

## Out of Scope

- Repository cloning (handled by ghq)
- PR creation (handled by PR command)
- `--no-github` skip option
- Multiple remote support
