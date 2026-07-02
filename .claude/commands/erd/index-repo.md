# /erd:index-repo - Repository Indexing

Generate a compact project index for efficient codebase understanding with significant token reduction.

## Usage

```
/erd:index-repo [mode: create|update|quick]
```

## Modes

| Mode | Behavior |
| --- | --- |
| `create` (default) | Full generation — run all phases (1–4) and write a fresh `PROJECT_INDEX.md`, overwriting any existing one. |
| `update` | Incremental refresh — requires an existing `PROJECT_INDEX.md`. Diff the current tree against the index (e.g. `git diff --stat` since the `Generated:` timestamp), re-analyze only the affected categories, and rewrite just those sections. Fall back to `create` if no index exists. |
| `quick` | Structure-only pass — run Phase 1 plus entry-point detection only; emit Project Structure and Entry Points sections and skip module/dependency/test extraction. Suited for a fast first orientation. |

## Purpose

- **Before**: Reading all files costs tens of thousands of tokens every session
- **After**: Reading PROJECT_INDEX.md costs ~3K tokens (90%+ reduction)

## Behavioral Flow

### Phase 1: Analyze Repository Structure

Run parallel Glob searches to categorize files:

1. **Code Structure**: `src/**/*.{rs,py,ts,js,tsx,jsx}`, `lib/**/*`
2. **Documentation**: `docs/**/*.md`, `*.md` (root level)
3. **Configuration**: `*.toml`, `*.yaml`, `*.yml`, `*.json` (exclude lock files)
4. **Tests**: `tests/**/*`, `**/*.test.*`, `**/*.spec.*`
5. **Scripts & Tools**: `scripts/**/*`, `bin/**/*`, `.github/**/*`

### Phase 2: Extract Metadata

For each category, extract:
- Entry points (main, cli, lib)
- Key modules and their exports/public API
- Dependencies and their purposes
- Test coverage structure

### Phase 3: Generate Index

Create `PROJECT_INDEX.md`:

```markdown
# Project Index: {project_name}

Generated: {timestamp}

## Project Structure
{tree view of main directories}

## Entry Points
- CLI: {path} - {description}
- Lib: {path} - {description}

## Core Modules
### {module_name}
- Path: {path}
- Purpose: {1-line description}
- Key exports: {list}

## Configuration
- {config_file}: {purpose}

## Test Coverage
- Unit tests: {count} files
- Integration tests: {count} files

## Key Dependencies
- {dependency}: {version} - {purpose}
```

### Phase 4: Validation

- All entry points identified
- Core modules documented
- Index size < 5KB
- Human-readable format

## Output

Creates:
1. `PROJECT_INDEX.md` (~3KB, human-readable)

## CRITICAL BOUNDARIES

**INDEXING ONLY**

This command produces a PROJECT INDEX ONLY.

**Will NOT**:
- Modify any source code
- Change project structure
- Install or update dependencies

**Next Step**: Use the generated index at the start of future sessions for quick codebase orientation.
