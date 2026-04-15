# Design: #246 Update Available Claude Code Commands

## Architecture Overview

This is a minimal change to the setup completion message in `setup.sh`. The existing `echo` statements at lines 953-956 are replaced with an expanded command list (5 commands instead of 3) and a workflow line showing the recommended order.

No new modules, functions, or logic are introduced. The change is purely output formatting within the existing `main()` function.

## Module Structure

```
setup.sh               # Modified: completion message echo statements (lines 953-956)
scripts/lib/common.sh  # Unchanged: print_* utility functions already available
```

## Interface Design

No API or interface changes. This modifies terminal output only.

### Output Specification

The completion message section after `print_section "Setup Complete"` will produce:

```
Available Claude Code commands:
  /issue     - Create a GitHub Issue
  /design    - Design architecture for a GitHub Issue
  /implement - Implement a GitHub Issue
  /review    - Code review via Codex CLI
  /pr        - Create a Pull Request

Workflow: /issue → /design → /implement → /review → /pr
```

### Design Decisions

1. **Command order follows workflow sequence** — `/issue` → `/design` → `/implement` → `/review` → `/pr`, not alphabetical. This reinforces the intended usage pattern.

2. **Descriptions are concise single-line summaries** — Derived from each SKILL.md frontmatter but shortened to fit the terminal output width and match the existing format (`/command - Description`).

3. **Column alignment** — All command names are padded to match the longest (`/implement` at 10 chars), keeping the `-` separator aligned for readability. This matches the existing convention.

4. **Workflow line uses Unicode arrows** (`→`) — Bash `echo` supports this via the existing terminal encoding. This is consistent with how the workflow is documented in the SKILL.md files.

5. **No color formatting for the command list** — The existing code uses plain `echo` (not `print_info` or `print_success`) for this section. We preserve that convention. Only the section header uses color via `print_section`.

6. **erd commands are NOT listed** — Per requirements, `/erd:*` commands are internal sub-commands and are not surfaced to users in the setup output.

## Data Flow

No data flow changes. This is static output text.

## Error Handling

No error handling changes needed — `echo` statements cannot fail.

## Implementation Notes

- The change touches exactly lines 953-956 of `setup.sh`
- Replace 3 `echo` lines with 5 `echo` lines for commands + 1 blank line + 1 `echo` line for the workflow
- Keep `echo ""` for blank line separators consistent with existing style
- The `→` character (U+2192) is safe for UTF-8 terminals, which is the expected environment for devcontainer users
