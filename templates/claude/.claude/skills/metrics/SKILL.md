---
name: metrics
description: Project metrics and analytics. Collects code statistics, test coverage, issue/PR status, dependency health, and git activity. Generates a metrics report.
argument-hint: "[--full | --code | --issues | --deps | --activity]"
disable-model-invocation: true
context: fork
agent: Explore
---

# Metrics Skill

Project metrics and analytics skill. Collects code statistics, test coverage, issue/PR status, dependency health, and git activity summary. Generates a comprehensive metrics report.

## MCP Tools

Use the following MCP tools for project exploration:

- **serena**: `find_file`, `list_dir` — for discovering project files and directory structure

## Usage

```
/metrics              # Full metrics report
/metrics --code       # Code statistics only
/metrics --issues     # Issue/PR statistics only
/metrics --deps       # Dependency health only
/metrics --activity   # Git activity only
```

## What This Skill Does

### 1. Code Statistics

- **Lines of code** by language (excluding generated/vendored files)
- **File count** by type
- **Module/directory breakdown** — lines per top-level directory
- **Test-to-code ratio** — test files vs source files

### 2. Test Coverage (if available)

- Run test suite with coverage if the project supports it
- Report overall coverage percentage
- Identify uncovered modules

### 3. Issue/PR Statistics

Collect via `gh` CLI:

```bash
gh issue list --state open --json number,title,labels,createdAt
gh issue list --state closed --limit 20 --json number,title,closedAt
gh pr list --state open --json number,title,createdAt
gh pr list --state merged --limit 20 --json number,title,mergedAt
```

- Open issues count and age distribution
- Recently closed issues
- Open PRs count
- Recently merged PRs
- Issue velocity (opened vs closed over last 30 days)

### 4. Dependency Health

- List dependencies and their versions
- Check for outdated dependencies (language-specific):
  - Rust: `cargo outdated` (if available)
  - Node.js: `npm outdated` or `npx npm-check`
  - Python: `pip list --outdated`
  - Deno: check import versions
- Flag security advisories if tooling supports it

### 5. Git Activity Summary

```bash
git log --oneline --since="30 days ago" --format="%H %an %s"
git shortlog -sn --since="30 days ago"
```

- Commits in last 30 days
- Active contributors
- Most changed files
- Commit frequency by day/week

## Output Format

Generate and display a metrics report:

```markdown
# Project Metrics Report

Generated: {ISO 8601 timestamp}
Repository: {repo name}

## Code Statistics

| Language | Files | Lines | % |
| --- | --- | --- | --- |
| Rust | 25 | 3,400 | 72% |
| TOML | 5 | 120 | 3% |
| Shell | 8 | 450 | 10% |
| Markdown | 12 | 720 | 15% |

**Total**: 50 files, 4,690 lines
**Test-to-code ratio**: 1:3.2 (820 test lines / 2,580 source lines)

## Test Coverage

- Overall: 78%
- Uncovered: src/github/api.rs, src/cli/parse.rs

## Issues & PRs

| Metric | Count |
| --- | --- |
| Open issues | 12 |
| Closed (30d) | 8 |
| Open PRs | 3 |
| Merged (30d) | 15 |
| Issue velocity | +4 (12 opened, 8 closed in 30d) |

## Dependency Health

- Total dependencies: 15
- Outdated: 3 (clap 4.4→4.5, serde 1.0.196→1.0.200, tokio 1.35→1.37)
- Security advisories: 0

## Git Activity (Last 30 Days)

- Commits: 42
- Contributors: 3
- Most changed: src/main.rs (12 commits), src/cli/mod.rs (8 commits)
```

## Best Practices

- Run periodically to track project health trends
- Use before sprint planning to identify tech debt
- Check dependency health before releases

## Integration

- **Standalone**: Can be run at any time
- **Before planning**: Use metrics to inform issue sizing and prioritization
- **Typical workflow**: **`/metrics`** → `/issue` → `/design` → `/implement` → `/review` → `/pr`

ARGUMENTS:
$ARGUMENTS
