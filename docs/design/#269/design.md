# Design: #269 Bring MySQL service templates to parity with PostgreSQL in setup integration

## Context

`templates/services/postgresql/` and `templates/services/mysql/` already mirror
each other at the file level — each has a `plugin.sh`, a
`docker-compose.<db>.yml` overlay, and a `.devcontainer/devcontainer.json`
fragment. Their `plugin.sh` hooks (`plugin_copy`, `plugin_post_copy`) are
structurally identical and produce a `{{PROJECT_NAME}}-db` service in the
merged docker-compose.

The asymmetry sits one level up, in the integration layer:

- `scripts/lib/common.sh::replace_placeholders()` maintains an explicit
  hardcoded list of overlay files to scan for `{{PROJECT_NAME}}` after the
  plugin merge step. PostgreSQL/Redis/Celery overlays are listed; MySQL is not
  (`scripts/lib/common.sh:553-563`).
- `scripts/lib/common.sh::show_interactive_mode_error()` enumerates the
  user-facing service flags in its non-interactive help output. `--postgresql`
  is listed; `--mysql` is not (`scripts/lib/common.sh:679`).
- The README quickstart uses `--postgresql -y` as the canonical service
  example. There is no MySQL counterpart (`README.md:45`).
- `tests/setup_create_manifest.bats` verifies that `--create-manifest` rejects
  `--postgresql` (a stand-in for "any service flag"). MySQL has no equivalent
  guard (`tests/setup_create_manifest.bats:105-109`).
- `tests/setup_service_selection.bats` has two PostgreSQL `plugin_post_copy`
  integration tests but only one for MySQL — the "does not pollute
  `dockerComposeFile` with the overlay" assertion exists for postgres only
  (`tests/setup_service_selection.bats:238-295` vs. `:474-531`).

The design referenced by this delta is documented in:

- `../shared/architecture.md` :: Module Structure (services/{mysql,…})
- `../shared/api-spec.md` :: `setup.sh` flag table (already lists `--mysql`)
- `../shared/sequence.md` :: `setup.sh --monorepo` (postgres is one example;
  the same flow applies to mysql)

This issue does not introduce new abstractions. It closes the parity gap so
maintenance can stop branching by database choice, and so a future contributor
reading the codebase sees both DB plugins as equally first-class.

## Architecture Overview (delta)

No architectural change. Five small mechanical edits across the integration
layer:

1. Extend a hardcoded file list in `replace_placeholders()`.
2. Extend a hardcoded help-text block in `show_interactive_mode_error()`.
3. Extend a documentation block in `README.md`.
4. Add one missing rejection test (mirror).
5. Add one missing `plugin_post_copy` integration test (mirror).

All five edits add a MySQL line / block next to the existing PostgreSQL one;
none modifies behavior of code that PostgreSQL relies on.

## Module Structure (delta)

Files modified:

```
scripts/lib/common.sh                   # FR-1, FR-2 — extend two hardcoded lists
README.md                               # FR-3 — add MySQL quickstart example
tests/setup_create_manifest.bats        # FR-4 — add `--create-manifest --mysql` rejection test
tests/setup_service_selection.bats      # FR-5 — add MySQL "no overlay in dockerComposeFile" test
```

No files created, no files renamed, no new directories.

## Interface Design (delta)

### Public API / Functions

No public API changes. The Rust crate is untouched. The existing shell helpers
keep their signatures:

| Name | Signature | Description |
| --- | --- | --- |
| `replace_placeholders` | `replace_placeholders <target_dir> <project_name>` | unchanged behavior; the internal file list grows by one entry |
| `show_interactive_mode_error` | (no args) | unchanged behavior; the printed help block grows by one line |

### Type Definitions (delta)

None.

## Data Flow

The five edits sit at the points already exercised by the existing PostgreSQL
flow. The diagram below highlights where each FR lands; it is not a new flow.

See `flowchart.md` for the mapping of each FR to its insertion point in the
existing pipeline.

## Error Handling

No new error paths. `set -euo pipefail` and the existing
`/.claude/rules/shell.md` conventions cover the modified shell sites without
change. The new bats tests use the existing `[[ "$status" -eq 1 ]]` and
`assert_*` patterns from neighboring tests.

## Implementation Notes

### FR-1 — extend `replace_placeholders()` file list

`scripts/lib/common.sh:553-563`. Add `"${target_dir}/docker-compose.mysql.yml"`
between the existing `docker-compose.postgresql.yml` and
`docker-compose.redis.yml` lines, preserving alphabetical-among-DB order
(postgres before mysql is not alphabetical, but ordering follows "DB engines
first, then redis, then celery"; placing mysql immediately after postgresql
matches that grouping).

The functional impact under normal operation is small — `plugin_post_copy`
already deletes the overlay file after merging. The fix is primarily defensive
(in case cleanup is interrupted) and consistency-driven (so a future
contributor cannot infer "mysql was deliberately excluded"). Note that
`docker-compose.yml` itself is in the list, so the merged content's
`{{PROJECT_NAME}}` placeholders ARE already replaced via that entry.

### FR-2 — add `--mysql` to `show_interactive_mode_error()` help

`scripts/lib/common.sh:679`. Add a new `echo "  --mysql               Include MySQL database support"` line directly after the
`--postgresql` line. Match the indentation, column alignment (flag left-padded
to ~22 chars before the description), and tone of the surrounding lines
exactly. The existing `--neo4j` line is preserved unchanged — it is unrelated
to this issue's scope.

### FR-3 — README quickstart MySQL example

`README.md:33-50`. Two sub-options were considered:

- (a) Add a parallel MySQL example next to the existing `--postgresql -y`
  monorepo example.
- (b) Add a MySQL example to the single-mode quickstart (around line 21).

This issue takes (a): the monorepo block is the only place where any service
flag currently appears in the README, so duplicating its shape keeps the diff
local and the prose minimal. A small comment-style hint
("`--postgresql` or `--mysql`") avoids visually doubling the block.

Concrete edit: replace the existing single-line `--postgresql -y` invocation
with two lines (or a clear "or `--mysql`" annotation) so the reader sees both
as equally first-class.

### FR-4 — `--create-manifest --mysql` rejection test

`tests/setup_create_manifest.bats`. Mirror of the `@test "--create-manifest
rejects service flags"` block at line 105:

```bats
@test "--create-manifest rejects --mysql" {
    run bash "$SETUP_SH" --create-manifest --mysql -y
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"--create-manifest does not accept service flags"* ]]
}
```

Placed immediately after the postgresql variant so a reader scanning the file
sees both DB rejection tests next to each other.

### FR-5 — MySQL `plugin_post_copy` overlay cleanup test

`tests/setup_service_selection.bats`. Mirror of the postgresql test at line
238 (`@test "plugin_post_copy does not add docker-compose.postgresql.yml to
dockerComposeFile"`). Same setup (base `docker-compose.yml` with
`working_dir: /workspace`, base `devcontainer.json` with `dockerComposeFile:
["../docker-compose.yml"]`, `runServices: ["testapp"]`), then:

- copy `docker-compose.mysql.yml` instead of postgresql,
- source `templates/services/mysql/plugin.sh` instead of postgresql,
- assert `dockerComposeFile | length == 1` and `dockerComposeFile[0] ==
  "../docker-compose.yml"` (i.e. the mysql overlay was NOT inserted into the
  array).

Placed in the existing `# MySQL plugin_post_copy Integration Tests` section
(`tests/setup_service_selection.bats:471-473`), right before the existing
`adds DB service to runServices` test, so the section ends up with the same
test pair as the PostgreSQL section.

### Style and conventions

- All shell edits keep `set -euo pipefail`, `local`, `[[ ]]`, 4-space indent
  per `/.claude/rules/shell.md`.
- bats tests use the same `mktemp -d` + `assert_success` + `rm -rf "$temp_dir"`
  pattern as their postgresql counterparts.
- No new files, no new helpers, no new fixtures.

### Out of scope (as documented in the issue)

- `--neo4j` cleanup in `show_interactive_mode_error()` — Neo4j has no template;
  removal is a separate concern.
- `<project>-db` collision when `--postgresql` and `--mysql` are both
  selected.
- Idempotency fix for `mysql/plugin.sh::plugin_post_copy` (#265 follow-up
  TODO).
- `docs/design/shared/sequence.md` postgres-flavored examples.
