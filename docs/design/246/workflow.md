# Workflow: #246 Update Available Claude Code Commands

## Implementation Steps

### Step 1: Update command list echo statements
- **Action**: Replace lines 953-956 in `setup.sh` — remove the 3 existing echo lines for commands and replace with 5 echo lines (one per workflow command in order: `/issue`, `/design`, `/implement`, `/review`, `/pr`), a blank-line separator, and a workflow-order echo line
- **Files**: `setup.sh` (lines 953-956)
- **Depends on**: None
- **Done when**: The "Available Claude Code commands:" section lists all 5 commands with aligned formatting, followed by the workflow order line

### Step 2: Verify output formatting
- **Action**: Visually inspect the modified echo statements to confirm column alignment (command names padded to 10 chars) and that the `→` Unicode arrow renders correctly
- **Files**: `setup.sh` (read-only check)
- **Depends on**: Step 1
- **Done when**: All `-` separators are vertically aligned and the workflow line reads `/issue → /design → /implement → /review → /pr`

## Task Dependencies

- Step 2 depends on Step 1 (need the edited file to verify)
- No parallelism needed — this is a 2-step sequential change

## Test Strategy

### Unit Tests
- Not applicable — this is a static output change with no logic

### Integration Tests
- Not applicable — echo statements have no failure modes

### Edge Cases
- None — the change is purely cosmetic terminal output
