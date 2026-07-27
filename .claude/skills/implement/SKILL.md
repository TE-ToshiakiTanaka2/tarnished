---
name: implement
description: Implement a GitHub Issue with codebase understanding, build verification, testing, and quality assurance. Uses erd commands (erd:index-repo, erd:implement, erd:build, erd:test, erd:analyze, erd:improve, erd:troubleshoot).
argument-hint: "<issue_number> [--base <branch>]"
disable-model-invocation: true
---

# Skill: Implement

Implementation skill for projects. Handles codebase understanding, feature implementation, build verification, testing, code analysis, and quality improvement.

This skill is the Claude Code projection of `.tarnished/workflows/implement.md`. Keep the shared workflow source and this tool-specific entrypoint aligned.

## Usage

```
/implement <issue_number>              # reuse or create a branch based on develop
/implement <issue_number> --base main  # base on main instead
```

`--base` defaults to `develop` and is passed through to `_shared/branch`. When `/design` already created a branch for this issue it is detected and reused, and `--base` only matters if a branch has to be created.

## Roles

Read `.claude/skills/_shared/delegation/SKILL.md` for the role vocabulary and the routing table.

This stage is the one most often mis-delegated. Interpreting the design and matching existing conventions is the highest-judgment work in the lifecycle and stays with the orchestrator. What is genuinely mechanical — the repository survey, the lint/format/type-check fix loop, boilerplate test authoring, and bulk application of an already-decided change — is delegated. Route per unit of work, not per phase.

## erd Command Invocation

Invoke each erd command by the first available route:

1. `Skill(erd:<command>)` — loads the instructions into the current turn
2. `Read(".claude/commands.local/erd/<command>.md")` — the project's overlay, when one exists
3. `Read(".claude/commands/erd/<command>.md")` — the base copy

Check for the overlay before falling back to the base copy: a project that customizes an erd command does so in `commands.local/`, and reading the base copy directly would silently ignore it.

## Pipeline

Seven steps. Each carries its own skip condition — a one-file change should not run a full repository survey just because the pipeline lists one.

| # | Step | Skip when |
| --- | --- | --- |
| 1 | **Prepare** — read the issue with `gh issue view`; detect or create the branch via `_shared/branch` (Issue mode, with `base`); load both design layers | Never. The branch and the design artifacts are the stage's inputs |
| 2 | **Survey** — `/erd:index-repo` to map relevant modules, locate files to change, and learn existing patterns | The change is confined to files you have already read and whose conventions are established |
| 3 | **Implement** — `/erd:implement`, following the design artifacts and the codebase's existing conventions; commit per logical unit | Never |
| 4 | **Build** — `/erd:build`: linters, formatters, type checkers; fix iteratively | Never |
| 5 | **Test** — `/erd:test`: run the suite, assess coverage, author tests for changed paths | Never |
| 6 | **Analyze and improve** — `/erd:analyze` for findings, `/erd:improve` to apply behavior-preserving fixes, then re-run build and test | No findings worth acting on, or the change is too small to have introduced any. Say so rather than running the loop for form |
| 7 | **Troubleshoot** — `/erd:troubleshoot` for root-cause analysis | Build and test pass, or a failure was fixed directly. Reach for this when failures persist after direct fixes, or stem from configuration and dependencies rather than code |

### Design artifacts to load in step 1

- **Shared layer**: `docs/design/shared/architecture.md`, `data-model.md`, `api-spec.md`, `class.md`, `sequence.md`, and any `shared/research/*.md`. Skip files that do not exist — `shared/` may be empty for the very first issue.
- **Per-issue layer**: `docs/design/#{issue_number}/design.md`, `api-spec.md`, `workflow.md`, `flowchart.md`, `research.md`. Skip files that do not exist.

The shared layer is the cumulative project truth maintained by `/design`; the per-issue layer is the self-contained delta for this issue.

### The quality loop

Steps 4-6 form a cycle: `analyze findings → improve → build → test`. Deciding what counts as a finding and which refactor preserves behavior is judgment; running the tools and fixing what they report is mechanical.

## MCP Tools

Use the following MCP tools during implementation:

- **serena**: `find_symbol`, `get_symbols_overview`, `find_file`, `search_for_pattern`, `list_dir`, `replace_symbol_body`, `insert_after_symbol`, `insert_before_symbol` — for codebase navigation, understanding existing patterns, and semantic code editing
- **context7**: `resolve-library-id`, `get-library-docs` — for looking up library documentation when implementing with external dependencies

If a listed MCP server is unavailable in the current environment, fall back to the agent's built-in code search, file reading, and web search tools — do not stop or ask for installation.

## erd Commands Used

| Command | Purpose | Pipeline step |
| --- | --- | --- |
| `/erd:index-repo` | Repository indexing for efficient codebase understanding | 2 |
| `/erd:implement` | Feature implementation following design artifacts | 3 |
| `/erd:build` | Build verification with iterative error fixing | 4 |
| `/erd:test` | Test execution, coverage analysis, and authoring missing tests | 5 |
| `/erd:analyze` | Code analysis (quality, security, performance, architecture) | 6 |
| `/erd:improve` | Behavior-preserving quality improvements | 6 |
| `/erd:troubleshoot` | Diagnose persistent build/test failures (conditional) | 7 |

## Commit Strategy

Conventional commit format with progressive commits — one per logical unit of work, not one per pipeline step:

```
feat: add config type definitions
feat: implement config file loader
test: add unit tests for config module
fix: resolve edge case in config parsing
refactor: extract validation logic (erd:improve)
```

Stage explicit paths. Avoid `git add -A` and `git add .` — they sweep up unrelated untracked content such as editor state and MCP scratch directories.

## Error Handling

- **Build errors**: Auto-fix with linters and formatters, retry. This is mechanical; a retry budget applies
- **Test failures**: Analyze the cause and fix. Deciding that a failing test encodes the wrong expectation is judgment, not a retry
- **Persistent failures**: Escalate to `/erd:troubleshoot` for root cause analysis
- **Blockers**: Report to the user with what you tried, and request guidance

## Reporting

Report, in whatever shape fits the change:

- Branch and issue number
- Pipeline steps run, and steps skipped with the reason
- Build and test results, with the commands actually run
- Analysis findings and the improvements applied
- Commits made
- Remaining risks, and anything left incomplete
- The next command

## Best Practices

- **Design First**: Load and follow design artifacts from `/design` if available
- **Skip Deliberately**: A skipped step is a decision to report, not a step to hide
- **Incremental Implementation**: Implement and commit in small logical units
- **Type Safety**: Maximize use of type systems where available
- **Test Coverage**: Always add tests for new features
- **Match the Codebase**: Follow existing conventions over personal preference

## Integration

- **Prerequisite**: Issue created with `/issue`, optionally designed with `/design`
- **Next step**: Review with `/review` or create Pull Request with `/pr`
- **Typical workflow**: `/issue` → `/design` → **`/implement`** → `/review` → `/pr`

ARGUMENTS:
$ARGUMENTS
