# Claude Command: Implement

Implementation command for CLI projects. Handles design, implementation, static analysis, and testing.

## Usage

```
/implement <issue_number>
```

Example:

```
/implement 1
```

## What This Command Does

### Phase 1: Preparation

1. **Review Issue** - Use `gh issue view` to understand Issue content
2. **Create branch** - Create branch following naming convention
3. **Understand codebase** - Grasp the structure of related code

### Phase 2: Design

4. **Execute sc:design** - Determine architecture and design:
   - Module structure
   - Interface design
   - Type definitions
5. **Execute sc:workflow** - Generate implementation steps:
   - Organize task dependencies
   - Determine implementation order
   - Test strategy

### Phase 3: Implementation

6. **Implement features** - Implement based on design:
   - Follow language best practices
   - Proper error handling
7. **Progressive commits** - Commit per task

### Phase 4: Quality Assurance

8. **Run static analysis** - Language-specific linters and formatters
9. **Run tests** - Unit and integration tests
10. **Final commit** - Commit fixes
11. **Report results** - Present branch name and Issue number

## Branch Naming Convention

```
{label}/{assignee}/#{issue_number}/{title}
```

- `{label}`: Issue label (feature, bugfix, refactor, docs)
- `{assignee}`: GitHub username
- `{issue_number}`: Issue number (with # prefix)
- `{title}`: kebab-case title

Examples:

- `feature/alice/#123/add-config-loader`
- `bugfix/bob/#456/fix-argument-parsing`

## Leveraging sc:design

Use `/sc:design` to design the following:

```
Module Structure:
  src/
  ├── commands/        # CLI commands
  ├── lib/             # Core logic
  ├── types/           # Type definitions
  └── utils/           # Utilities

Interface Design:
  - Public API design
  - Type definitions (interfaces, types)
  - Error type design
```

## Leveraging sc:workflow

Use `/sc:workflow` to generate implementation steps:

```
Implementation Steps:
1. Create type definitions
2. Implement core logic
3. Integrate CLI command
4. Create unit tests
5. Create integration tests
6. Update documentation
```

## Commit Strategy

Conventional commit format:

```
feat: add config file loader
fix: resolve CLI argument parsing error
refactor: extract validation logic
test: add unit tests for config module
docs: update CLI usage documentation
```

## Implementation Workflow

```mermaid
graph TD
    A[Review Issue] --> B[Create branch]
    B --> C[Execute sc:design]
    C --> D[Execute sc:workflow]
    D --> E[Implement feature]
    E --> F[Commit]
    F --> G{All tasks done?}
    G -->|No| E
    G -->|Yes| H[Static Analysis]
    H --> I{Errors?}
    I -->|Yes| J[Fix]
    J --> H
    I -->|No| K[Run Tests]
    K --> L{Tests pass?}
    L -->|No| M[Fix]
    M --> E
    L -->|Yes| N[Final commit]
    N --> O[Report completion]
```

## Error Handling

- **Static analysis errors**: Attempt auto-fix, commit fixes
- **Test failures**: Analyze cause, fix implementation
- **Blockers**: Report to user, request guidance

## Output Format

```
Implementation Complete

Branch: feature/username/#123/add-config-loader
Issue: #123

Quality Checks:
- Formatting: Passed
- Linting: Passed
- Type Check: Passed

Tests:
- Unit tests: 15/15 passed
- Integration tests: 3/3 passed

Commits:
- feat: add Config type definitions
- feat: implement config loader
- test: add config loader tests

Ready for /pr
```

## Best Practices

- **Design First**: Solidify design with sc:design before implementation
- **Incremental Implementation**: Implement and commit in small units
- **Type Safety**: Maximize use of type systems where available
- **Test Coverage**: Always add tests for new features

## Integration

- **Prerequisite**: Issue created with `/issue`
- **Next step**: Create Pull Request with `/pr`

ARGUMENTS:
$ARGUMENTS
