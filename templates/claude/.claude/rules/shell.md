---
paths:
  - "**/*.sh"
  - "**/*.bash"
---

# Shell Script Coding Rules

## Style

- Use `#!/bin/bash` shebang for all scripts
- Indent with 4 spaces, no tabs
- Max line width: 100 characters
- Use lowercase for local variables, UPPERCASE for exported/environment variables
- Quote all variable expansions: `"$var"` not `$var`

## Error Handling

- Use `set -euo pipefail` at the top of scripts
- Check command existence before use: `command -v <cmd> &> /dev/null`
- Provide meaningful error messages with `print_error` or `echo >&2`
- Use `|| return 1` or `|| exit 1` for critical operations

## Functions

- Use `local` for function-scoped variables
- Document functions with a comment header describing purpose
- Return 0 for success, non-zero for failure
- Use `readonly` for constants

## Security

- Never use `eval` with user input
- Always quote file paths: `"${target_dir}/file"`
- Use `[[ ]]` instead of `[ ]` for conditionals
- Avoid `chmod 777` -- use least-privilege permissions
- Sanitize paths before use in `rm`, `cp`, `mv`

## Testing

- Test scripts with both TTY and non-TTY (piped) input
- Include `--dry-run` support where applicable
- Test edge cases: empty input, missing files, permission errors

## Project Conventions

- Plugin scripts follow the standard interface: `plugin_name()`, `plugin_description()`, `plugin_copy()`, `plugin_post_copy()`
- Use `print_info`, `print_success`, `print_warning`, `print_error` for output
- Use `copy_with_confirm` for file operations that may overwrite
- Use `copy_dir_with_confirm` for directory-level copy operations
