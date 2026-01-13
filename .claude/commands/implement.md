# Claude Command: Implement

This command helps you implement GitHub Issues by reviewing requirements, creating branches, implementing features, running tests, and ensuring code quality for the Devcontainer boilerplate project.

**Environment**: Devcontainer Boilerplate

## Usage

To implement a GitHub Issue:

```
/implement <issue_number>
```

Example:

```
/implement 1
```

## What This Command Does

This command orchestrates a structured workflow by delegating to SuperClaude commands:

1. **Review GitHub Issue** - Use `gh issue view` to check and understand the issue content (including any documentation comments)
2. **Create feature branch** - Checkout a new branch from develop with the naming convention:
   - Format: `{label}/{assignee}/#{issue_number}/{title}`
   - Example: `feature/john/#42/add-python-template`
3. **Execute /sc:design** - Delegate to design skill for architecture and component specifications
4. **Execute /sc:workflow** - Delegate to workflow skill for implementation planning
5. **Break down tasks** - Organize implementation tasks based on design and workflow documents
6. **Execute /sc:implement** - Delegate actual implementation to the implement skill
7. **Commit progressively** - Create commits as each task or subtask is completed
8. **Run tests** - Execute test suite based on file detection (see Test Strategy)
9. **Execute /sc:analyze + /sc:improve** - Run quality checks and apply improvements
10. **Final commit** - Commit all remaining modifications (including design and workflow documents)
11. **Present results** - Show the final branch name and issue number to the user

## SuperClaude Command Delegation

| Phase          | Delegated Command | Purpose                                    |
| -------------- | ----------------- | ------------------------------------------ |
| Design         | `/sc:design`      | Architecture and component specifications  |
| Planning       | `/sc:workflow`    | Implementation workflow and task breakdown |
| Implementation | `/sc:implement`   | Feature and code implementation            |
| Analysis       | `/sc:analyze`     | Comprehensive code quality analysis        |
| Improvement    | `/sc:improve`     | Apply systematic code improvements         |

## Branch Naming Convention

Branches are created following this pattern:

```
{label}/{assignee}/#{issue_number}/{title}
```

Where:

- `{label}` - Issue label (feature, bugfix, patch, refactor, documentation)
- `{assignee}` - GitHub username of the assignee
- `{issue_number}` - The issue number (with # prefix)
- `{title}` - Kebab-case title derived from the issue

Examples:

- `feature/alice/#123/add-python-template`
- `bugfix/bob/#456/fix-setup-script`
- `refactor/charlie/#789/optimize-docker-build`

## Test Strategy

### Test Categories

| Category | Description | Execution |
|----------|-------------|-----------|
| **Basic Tests** | Docker build, Devcontainer startup, shellcheck | Always run |
| **Setup Tests** | setup.sh functionality verification | Always run |
| **Actions Tests** | YAML syntax check, `act` local execution | Always run |
| **Language Tests** | Language-specific lint/test | File detection based |

### Basic Tests (Always Run)

```bash
# Shell script linting
shellcheck **/*.sh

# Docker build verification
docker build -f docker/Dockerfile.dev -t test-image .

# Devcontainer config validation
# (Check JSON syntax of devcontainer.json)
```

### Setup Script Tests (Always Run)

```bash
# Dry run test
bash setup.sh --dry-run

# Help option test
bash setup.sh --help

# Language argument test (if applicable)
bash setup.sh --lang python --dry-run
```

### GitHub Actions Tests (Always Run)

```bash
# YAML syntax validation
actionlint .github/workflows/*.yml

# Local execution with act (dry run)
act --dryrun

# Full local execution (optional, may require Docker)
act push
```

### Language Detection Rules

Language-specific tests are executed based on file detection:

| Detection File | Language | Tests |
|----------------|----------|-------|
| `pyproject.toml`, `requirements.txt` | Python | `ruff check`, `ruff format --check`, `pytest` |
| `package.json` | Node.js/TS | `npm run lint`, `npm test` |
| `Cargo.toml` | Rust | `cargo fmt --check`, `cargo clippy`, `cargo test` |
| `deno.json`, `deno.jsonc` | Deno | `deno fmt --check`, `deno lint`, `deno test` |

### Test Execution Flow

```
/implement execution
│
├─ Basic Tests (always)
│   ├── shellcheck *.sh
│   ├── docker build verification
│   └── devcontainer.json validation
│
├─ Setup Tests (always)
│   ├── setup.sh --dry-run
│   ├── setup.sh --help
│   └── setup.sh --lang <lang> --dry-run
│
├─ Actions Tests (always)
│   ├── actionlint (yaml syntax)
│   └── act --dryrun (local execution)
│
└─ Language Tests (file detection based)
    ├── pyproject.toml → ruff, pytest
    ├── package.json → eslint, npm test
    ├── Cargo.toml → cargo fmt, cargo test
    └── deno.json → deno fmt, deno test
```

## Implementation Workflow

### 1. Issue Analysis

- Read and understand all requirements
- Check issue comments for documentation notes (from `/issue` command)
- Identify main tasks and subtasks
- Note acceptance criteria
- Check for dependencies
- Determine target milestone (core, github-actions, claude-code, or language template)

### 2. Design Phase (/sc:design)

Delegate to `/sc:design` skill to create comprehensive design document:

- Output file: `docs/design/issue-#{issue_number}-{title}.md`
- Contents:
  - Architecture overview and component structure
  - File structure and modifications
  - Configuration changes
  - Test strategy
- Commit design document before proceeding

### 3. Workflow Planning (/sc:workflow)

Delegate to `/sc:workflow` skill to create implementation workflow:

- Output file: `docs/workflow/issue-#{issue_number}-{title}.md`
- Contents:
  - Step-by-step implementation phases
  - Task breakdown with dependencies
  - Critical path identification
  - Testing strategy per phase
  - Rollback considerations
- Commit workflow document before proceeding

### 4. Development Process

Delegate to `/sc:implement` for actual implementation:

- Implement features incrementally **following the workflow document**
- Reference the design document for architecture decisions
- Follow existing code patterns and conventions
- Write clean, maintainable code
- Add appropriate comments and documentation

### 5. Commit Strategy

- Make atomic commits for each logical change
- Use conventional commit format with emojis
- Examples:
  - ✨ feat: add Python template support
  - 🐛 fix: resolve setup.sh permission issue
  - ♻️ refactor: extract language detection logic
  - ✅ test: add shellcheck validation
  - 📝 docs: update README with usage examples

### 6. Testing Requirements

Execute tests based on the test strategy:

1. **Always run basic tests** (shellcheck, docker build)
2. **Always run setup tests** (setup.sh verification)
3. **Always run actions tests** (actionlint, act)
4. **Conditionally run language tests** (based on file detection)

### 7. Code Quality (/sc:analyze + /sc:improve)

Delegate to `/sc:analyze` and `/sc:improve`:

- **Shell scripts**: Run `shellcheck`
- **YAML files**: Run `actionlint`
- **Markdown**: Check formatting
- Fix all issues before proceeding

### 8. Final Verification

- Run full test suite
- Ensure no regressions
- Verify all issue requirements are met
- Confirm design and workflow documents are committed

## Common Commands

| Task | Command |
|------|---------|
| Shell lint | `shellcheck **/*.sh` |
| Docker build | `docker build -f docker/Dockerfile.dev -t test .` |
| Actions lint | `actionlint .github/workflows/*.yml` |
| Act dry run | `act --dryrun` |
| Act full run | `act push` |

## Error Handling

If unable to complete implementation:

- Clearly communicate blockers to the user
- Ask for guidance on unresolved issues
- Document any assumptions made

## Output Format

Upon successful completion, the command will present:

```
✅ Implementation Complete

Branch: feature/username/#123/feature-title
Issue: #123
Milestone: core

Documents Created:
- docs/design/issue-#123-feature-title.md
- docs/workflow/issue-#123-feature-title.md

SuperClaude Execution:
- /sc:design: Design document created
- /sc:workflow: Workflow document created
- /sc:implement: All tasks implemented
- /sc:analyze: X issues found
- /sc:improve: X improvements applied

Test Results:
- Basic Tests: ✅ Passed
  - shellcheck: ✅
  - docker build: ✅
- Setup Tests: ✅ Passed
  - setup.sh --dry-run: ✅
  - setup.sh --help: ✅
- Actions Tests: ✅ Passed
  - actionlint: ✅
  - act --dryrun: ✅
- Language Tests: ✅ Passed (Python detected)
  - ruff check: ✅
  - pytest: ✅

Summary:
- Design document created and committed
- Workflow document created and committed
- All tasks implemented
- All tests passing

Ready for review and merge.
```

## Best Practices

- **SuperClaude Delegation**: Leverage specialized commands for each phase
- **Incremental Development**: Build features step by step
- **Test-Driven Development**: Consider writing tests first when appropriate
- **Code Review Ready**: Ensure code is clean and well-documented
- **Continuous Integration**: Verify all CI checks would pass
- **Communication**: Keep the user informed of progress and any issues

## Integration with Other Commands

This command delegates to and combines:

- `/sc:design` - Architecture and design specifications
- `/sc:workflow` - Implementation planning
- `/sc:implement` - Feature implementation
- `/sc:analyze` - Code quality analysis
- `/sc:improve` - Code improvement

## Japanese Issue Support

このコマンドは日本語で書かれたGitHub Issueにも対応しています。実装時には：

- 日本語の要件を正確に理解
- 適切な英語のコード/コメントへの変換
- 必要に応じて日本語でのフィードバック提供
