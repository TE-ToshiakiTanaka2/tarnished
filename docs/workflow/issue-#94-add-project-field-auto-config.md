# Workflow Document: Issue #94 - Add GitHub Project Field Auto-Configuration

## Implementation Phases

### Phase 1: Update Main Issue Command

**Target File**: `.claude/commands/issue.md`

**Tasks**:
1. Add new Step 10: Configure Project Fields
2. Document the workflow for Actions monitoring
3. Add Size judgment guidelines
4. Add Priority judgment guidelines
5. Include GraphQL examples for reference

**Dependencies**: None

### Phase 2: Update Template Issue Command

**Target File**: `templates/claude/.claude/commands/issue.md`

**Tasks**:
1. Add equivalent Project field configuration section
2. Adapt for generic use (no project-specific assumptions)
3. Include skip conditions for missing configuration

**Dependencies**: Phase 1 completion

### Phase 3: Verification

**Tasks**:
1. Review markdown syntax
2. Verify all sections are complete
3. Test documentation clarity

**Dependencies**: Phase 2 completion

## Detailed Task Breakdown

### Phase 1: Main Issue Command Update

#### Task 1.1: Add Step 10 Section
- Location: After Step 9 (Return issue number)
- Content: Project Field Configuration workflow

#### Task 1.2: Document Actions Monitoring
- Describe polling approach
- Specify timeout (30 seconds)
- Document error handling

#### Task 1.3: Add Size Judgment Guidelines
- Define XS/S/M/L/XL criteria
- List factors to consider
- Provide examples

#### Task 1.4: Add Priority Judgment Guidelines
- Define High/Medium/Low criteria
- List factors to consider
- Map labels to priorities

#### Task 1.5: Include GraphQL Examples
- Field retrieval query
- Field update mutation
- CLI command examples

### Phase 2: Template Command Update

#### Task 2.1: Add Project Field Section
- Simplified version of main command
- Generic project configuration reference

#### Task 2.2: Add Skip Conditions
- Check for `project-automation.yml` existence
- Graceful skip when not configured

## Implementation Order

```
1. Read current issue.md content
   │
2. Add Step 10: Configure Project Fields
   │
3. Add Size Judgment Guidelines section
   │
4. Add Priority Judgment Guidelines section
   │
5. Add GraphQL Examples section
   │
6. Update Example Workflow section
   │
7. Commit changes to main issue command
   │
8. Read template issue.md content
   │
9. Add equivalent Project field section
   │
10. Commit changes to template issue command
    │
11. Run tests and verification
```

## Testing Checklist

- [ ] Markdown syntax is valid
- [ ] All sections are properly formatted
- [ ] GraphQL examples are correct
- [ ] Guidelines are clear and actionable
- [ ] Template version is consistent with main version

## Rollback Plan

If issues are found:
1. Revert commits: `git revert HEAD~N`
2. Fix issues in documentation
3. Re-commit with corrections

## Success Criteria

1. `/issue` command documentation includes:
   - Step 10: Configure Project Fields
   - Size judgment guidelines
   - Priority judgment guidelines
   - GraphQL examples

2. Template issue command includes:
   - Equivalent Project field configuration
   - Skip conditions for missing configuration

3. Both files pass markdown linting

4. Documentation is clear and actionable for Claude Code
