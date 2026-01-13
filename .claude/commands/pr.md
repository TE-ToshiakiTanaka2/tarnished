# Claude Command: PR (Pull Request)

This command helps you create Pull Requests to merge your feature branch into develop, with automatic change history gathering, issue linking, and CI verification for the Devcontainer boilerplate project.

**Environment**: Devcontainer Boilerplate

## Usage

To create a Pull Request:

```
/pr
```

Or specify a target branch:

```
/pr main
```

## What This Command Does

This command orchestrates a structured workflow by delegating to SuperClaude commands:

1. **Gather PR information** - Determine source and target branches (defaults to current → develop)
2. **Analyze staged changes** - Review current branch changes and staged content
3. **Execute /sc:analyze** - Delegate comprehensive code analysis on changed files
4. **Execute /sc:improve** - Delegate improvements based on analysis results
5. **Run test suite** - Execute all applicable tests (basic, setup, actions, language-specific)
6. **Commit improvements** - Commit all improvements with descriptive message
7. **Push changes** - Push all commits to remote branch
8. **Create Pull Request** - Submit PR with comprehensive Japanese description and **English title**
9. **Verify GitHub Actions (loop)** - Check CI status with sleep intervals:
   - Poll GitHub Actions status with `gh pr checks`
   - Wait with sleep intervals (e.g., 30 seconds) between checks
   - If failures detected: fix issues locally, commit, push, and re-check
   - Continue loop until all checks pass
10. **Report completion** - Notify user of successful PR creation

## SuperClaude Command Delegation

| Phase            | Delegated Command | Purpose                                                   |
| ---------------- | ----------------- | --------------------------------------------------------- |
| Code Analysis    | `/sc:analyze`     | Comprehensive quality, security, and performance analysis |
| Code Improvement | `/sc:improve`     | Apply systematic improvements                             |
| Git Operations   | `/sc:git`         | Git and GitHub operations                                 |

## Workflow Steps

### 1. Branch Information Gathering

- Identify current branch using `git branch --show-current`
- Default target: `develop` branch
- Verify branches are appropriate for PR
- If current branch is develop/main, ask user for clarification

### 2. Change History Collection

- Use `git log develop..HEAD` to get all commits
- Run `git diff develop...HEAD` to summarize changes
- Identify staged changes with `git diff --cached`
- Organize commits by type (feature, fix, refactor, etc.)
- Calculate statistics (files changed, additions, deletions)

### 3. Code Analysis (/sc:analyze)

Delegate to `/sc:analyze` on all changed files:

- **Quality Analysis**: Code style, complexity metrics, maintainability index
- **Security Analysis**: Vulnerability detection, security best practices
- **Shell Script Analysis**: shellcheck findings
- **YAML Analysis**: actionlint findings

Analysis scope:

```bash
# Get list of changed files
git diff develop...HEAD --name-only

# Delegate analysis to /sc:analyze
/sc:analyze <file_path>
```

### 4. Code Improvement (/sc:improve)

Delegate to `/sc:improve` to apply improvements based on analysis results:

- Fix code quality issues identified in analysis
- Apply shellcheck fixes
- Fix actionlint issues
- Optimize for better maintainability

### 5. Test Execution

Run the full test suite before creating PR:

```bash
# Basic Tests
shellcheck **/*.sh
docker build -f docker/Dockerfile.dev -t test .

# Setup Tests (if setup.sh exists)
bash setup.sh --dry-run
bash setup.sh --help

# Actions Tests (if workflows exist)
actionlint .github/workflows/*.yml
act --dryrun

# Language Tests (based on file detection)
# Python: ruff check, pytest
# Node.js: npm run lint, npm test
# Rust: cargo fmt --check, cargo test
# Deno: deno fmt --check, deno test
```

### 6. Commit and Push Improvements

- Stage all improvements: `git add .`
- Commit with descriptive message: `git commit -m "♻️ refactor: apply code improvements from analysis"`
- Push to remote with -u flag if needed: `git push -u origin <branch>`

### 7. Issue Linking

- Extract issue number from branch name (format: `#{number}`)
- Add "Closes #XXX" to ensure automatic issue closure
- Link related issues mentioned in commits
- Copy labels from the target issue to the PR
- Copy milestone from the target issue to the PR (if set)

### 8. PR Creation

Use `gh pr create` with:

- **Title in English** derived from branch name or main feature (e.g., "refactor: update commands for devcontainer boilerplate")
- Comprehensive Japanese description
- Labels copied from the target issue (plus additional labels based on change type)
- Milestone copied from the target issue (if set)
- Issue closing keywords

### 9. GitHub Actions Verification (Loop)

After PR creation, verify CI/CD pipeline status with polling loop:

**Polling Process:**

```bash
# Check PR status with sleep intervals
while true; do
  gh pr checks <PR_NUMBER>

  # If all checks pass, exit loop
  # If still running, sleep and retry
  # If failed, fix and re-check

  sleep 30  # Wait 30 seconds between checks
done
```

**Verification Steps:**

1. Use `gh pr checks <PR_NUMBER>` to check GitHub Actions status
2. If checks are still running:
   - Sleep for 30 seconds
   - Re-check status
   - Continue polling until completion
3. If any check fails:
   1. Identify the failing check
   2. Run the corresponding local command to reproduce the issue
   3. Fix the issue locally
   4. Commit and push the fix
   5. Return to step 1 (re-verify all checks)
4. Continue loop until all checks pass

**Common fixes:**

- **shellcheck**: Fix shell script issues
- **actionlint**: Fix GitHub Actions workflow issues
- **Docker build**: Fix Dockerfile issues
- **Tests**: Fix failing tests

**Exit conditions:**

- All checks pass → Proceed to completion report
- Maximum retries exceeded → Report failure to user with details

### 10. Completion Report

Present PR URL and summary to user

## Pull Request Title Format (English)

The PR title should follow conventional commit format in English:

```
{type}: {description in English}
```

Examples:

- `feat: add Python template support`
- `fix: resolve setup.sh permission issue`
- `refactor: update commands for devcontainer boilerplate`
- `docs: update README with installation guide`

## Pull Request Description Format (Japanese)

The PR description will include:

```markdown
## 概要

このPRで実装された主な機能や修正内容の簡潔な説明

## 変更内容

### ✨ 新機能

- 実装された新機能のリスト

### 🐛 バグ修正

- 修正されたバグのリスト

### ♻️ リファクタリング

- リファクタリングされた部分

### 📝 ドキュメント

- ドキュメントの更新内容

## 技術的詳細

実装方法や設計上の決定事項など、レビュアーが知っておくべき技術的な詳細

## テスト

- [ ] shellcheck通過
- [ ] Docker build成功
- [ ] setup.sh動作確認
- [ ] actionlint通過
- [ ] act --dryrun成功
- [ ] 言語固有テスト（該当する場合）

## SuperClaude実行結果 (/sc:analyze → /sc:improve)

PR作成前に実施した分析と改善内容：

### 分析結果 (/sc:analyze)

- 品質スコア: X/100
- shellcheck: X件の修正
- actionlint: X件の修正

### 適用した改善 (/sc:improve)

- 改善項目1の説明
- 改善項目2の説明

## チェックリスト

- [ ] コード分析実施 (/sc:analyze)
- [ ] 改善適用 (/sc:improve)
- [ ] shellcheck通過
- [ ] actionlint通過
- [ ] Docker build成功
- [ ] setup.shテスト通過
- [ ] act --dryrun成功
- [ ] コードレビュー準備完了

## 関連Issue

Closes #XXX

## その他

レビュアーへの注意事項や今後の課題など
```

## Automatic Issue Closing

The PR will include keywords to automatically close related issues:

- `Closes #123` - Closes issue when PR is merged
- `Fixes #456` - Alternative keyword for bug fixes
- `Resolves #789` - Alternative keyword for resolved issues

Multiple issues can be linked:

```
Closes #123, Closes #456
```

## Issue Metadata Copying

When a target issue is identified from the branch name, the PR creation process will automatically copy metadata from the issue:

### Labels

- All labels from the target issue will be copied to the PR
- Additional labels may be added based on the type of changes
- The combination ensures proper categorization and filtering

### Milestones

- If the target issue has an assigned milestone, it will be copied to the PR
- This maintains project planning consistency and tracking
- PRs without linked issues will not have milestones automatically assigned

### Implementation Steps

1. Use `gh issue view #XXX --json labels,milestone` to retrieve issue metadata
2. Extract label names and milestone information from JSON response
3. Apply labels using `gh pr edit --add-label` for each label
4. Apply milestone using `gh pr edit --milestone` if milestone exists

### Example Commands

```bash
# Get issue metadata
gh issue view #123 --json labels,milestone

# Apply labels to PR
gh pr edit 456 --add-label "feature,core"

# Apply milestone to PR
gh pr edit 456 --milestone "core"
```

## Branch Naming Convention

Expected branch format for automatic issue detection:

```
{type}/{assignee}/#{issue_number}/{description}
```

Examples:

- `feature/alice/#123/add-python-template` → Links to issue #123
- `bugfix/bob/#456/fix-setup-script` → Links to issue #456

## Error Handling

The command will handle these scenarios:

1. **No changes to commit**: Remind user to commit changes first
2. **On default branch**: Ask which feature branch to create PR from
3. **Conflicts detected**: Notify user and provide merge instructions
4. **No issue number**: Proceed without issue linking
5. **PR already exists**: Show existing PR URL
6. **GitHub Actions failure**: Automatically fix and push corrections

## Command Output

Successful completion will show:

```
✅ Pull Request作成完了

PR: #XXX - [Title in English]
URL: https://github.com/owner/repo/pull/XXX

対象ブランチ: develop
ソースブランチ: feature/user/#123/add-feature

関連Issue: #123 (マージ時に自動クローズ)
コピー済みメタデータ:
- ラベル: feature
- マイルストーン: core

SuperClaude実行結果:
- /sc:analyze: 5件の改善点を検出
- /sc:improve: 5件の改善を適用
- 品質スコア: 85/100 → 95/100

変更サマリー:
- 5 ファイル変更
- 250 行追加
- 50 行削除
- 3 コミット (+1 改善コミット)

テスト結果:
- shellcheck: ✅ passed
- Docker build: ✅ passed
- setup.sh: ✅ passed
- actionlint: ✅ passed
- act --dryrun: ✅ passed

GitHub Actions:
- ✅ lint: passed
- ✅ build: passed
- ✅ test: passed

レビュー準備完了です。
```

## Best Practices

- **SuperClaude Delegation**: Leverage specialized commands for each phase
- **Code Analysis First**: Always run `/sc:analyze` before creating PR to identify issues
- **Apply Improvements**: Use `/sc:improve` to fix identified issues before PR creation
- **Run All Tests**: Execute the full test suite before creating PR
- **English Title**: Always use English for PR titles following conventional commit format
- **Comprehensive Description**: Include all context needed for review in Japanese
- **Clear Change Summary**: Organize changes by type
- **Test Evidence**: Document testing approach and results
- **Issue Linking**: Always link related issues for traceability
- **Review Ready**: Ensure all checks pass before creating PR
- **CI Verification Loop**: Poll GitHub Actions with sleep intervals until all checks pass
- **Automatic Fixes**: Fix any CI failures automatically and push corrections

## Integration with Other Commands

This command delegates to and combines:

- `/sc:analyze` - Comprehensive code analysis
- `/sc:improve` - Code improvement
- `/sc:git` - Git operations

This command works seamlessly with:

- `/issue` - Create issues that will be linked
- `/implement` - Implement features that will be merged

## Language Convention

- **PR titles**: Always in English using conventional commit format
- **Descriptions**: Written in professional Japanese
- **Commit messages**: Preserved as-is
- **Technical terms**: May remain in English where appropriate
