# /erd:workflow - Implementation Workflow Planning

Generate structured implementation workflows from requirements and design specifications.

## Usage

```
/erd:workflow [requirement description or design reference]
```

## MCP Tools

- **sequential-thinking**: `sequentialthinking` -- for systematic task decomposition, dependency analysis, and implementation order optimization

## Behavioral Flow

1. **Analyze**: Parse requirements and design specifications to understand implementation scope
2. **Decompose**: Break down into discrete, actionable implementation steps
3. **Order**: Determine execution order based on dependencies
4. **Validate**: Ensure completeness -- all requirements are covered by steps
5. **Document**: Generate structured workflow plan

## Decomposition Principles

- **Atomic steps**: Each step should be a single, completable unit of work
- **Clear dependencies**: Explicitly state what each step depends on
- **Testable checkpoints**: Each step should have verifiable completion criteria
- **Progressive building**: Earlier steps create foundations for later ones

## Step Categories

1. **Type definitions**: Data models, interfaces, enums
2. **Core logic**: Business logic implementation
3. **Integration**: Connecting with existing modules
4. **Error handling**: Error types, recovery, validation
5. **Tests**: Unit tests, integration tests, edge cases
6. **Quality**: Linting, formatting, type checking

## Output

```markdown
# Workflow: [target]

## Implementation Steps

### Step 1: [title]
- **Action**: [what to do]
- **Files**: [files to create or modify]
- **Depends on**: [prerequisites]
- **Done when**: [completion criteria]

### Step 2: [title]
...

## Task Dependencies

- Step N depends on Step M (reason)
- Steps X and Y can be done in parallel

## Test Strategy

### Unit Tests
- [what to test and why]

### Integration Tests
- [what to test and why]

### Edge Cases
- [specific edge cases to cover]
```

## CRITICAL BOUNDARIES

**STOP AFTER PLAN CREATION**

This command produces an IMPLEMENTATION PLAN ONLY.

**Will NOT**:
- Execute any implementation tasks
- Write or modify code
- Create files (except the workflow plan document)
- Make architectural changes
- Run builds or tests

**Next Step**: After workflow completes, proceed to implementation phase.
