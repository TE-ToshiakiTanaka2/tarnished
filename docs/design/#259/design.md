# Design: #259 Expand `update_gitignore()` — whitelist `.claude/.codex`, ignore `.serena/screenshots`

## Context

`scripts/lib/common.sh` defines `update_gitignore(target_dir)`, called by `setup.sh` to seed a downstream project's `.gitignore` with entries the project should not commit. Today, this function appends one line — `.claude/settings.local.json` — guarded by a line-level `grep -q`. The Codex plugin (`templates/codex/plugin.sh::plugin_post_copy`) follows the same pattern and adds `.codex/config.local.toml`.

This is a **blacklist** approach: anything not explicitly listed is committable. As the `.claude/` and `.codex/` directories grow with local working artifacts (Serena MCP scratchpads, plugin caches, agent transcripts), each new local-file pattern has to be chased and added. The cumulative pressure shows up as accidental commits of personal/local content.

This issue inverts the default for those directories: each becomes a **whitelist block** — `.claude/*` and `.codex/*` are ignored entirely, and only the explicit set of project-tracked subdirectories/files is allow-listed back via `!path` lines. Two additional always-ignore directives (`.serena/`, `screenshots/`) cover language-agnostic developer artifacts.

The plugin-separation architecture is preserved (per `shared/architecture.md::Module Structure`):

- Universal entries (`.claude/*`, `.serena/`, `screenshots/`) → `scripts/lib/common.sh::update_gitignore()` because every downstream project gets `.claude/`, and `.serena/` / `screenshots/` are language-agnostic.
- Codex-specific entries (`.codex/*`) → `templates/codex/plugin.sh` because only Codex users have a `.codex/` directory.

The relevant slice of `shared/data-model.md` for this issue is the "Schemas / Migrations" table — `.gitignore` is a generated artifact whose evolution is tracked there.

## Architecture Overview (delta)

The change is purely in two existing shell call sites. No new modules, no new files, no new function signatures. The body of `update_gitignore()` and the gitignore section of `templates/codex/plugin.sh::plugin_post_copy` is restructured from "append one named file" to "append a small block of related lines, idempotent at the **block** level via a comment-marker `grep -q`."

The operational invariant changes from line-level idempotency (one `grep` per ignore line) to block-level idempotency (one `grep` per block, keyed on a comment marker that the function itself writes). This is stricter — a block has multiple lines and the user may legitimately add their own lines between them, so per-line `grep` is no longer the right primitive. Marker-based detection avoids false-positive duplicate appends without inspecting every line of the block.

User-authored additions outside our blocks remain untouched (FR-7) — the function only ever appends.

## Module Structure (delta)

```
scripts/lib/common.sh
└── update_gitignore()                    # Modified: replace single-line append with three blocks
                                          #   - Block 1: .claude/* whitelist (FR-1)
                                          #   - Block 2: .serena/ ignore (FR-2)
                                          #   - Block 3: screenshots/ ignore (FR-3)
                                          # Drop pre-existing `.claude/settings.local.json` line (FR-5)

templates/codex/plugin.sh
└── plugin_post_copy()
    └── gitignore section                 # Modified: replace `.codex/config.local.toml` line
                                          # with Block 4: .codex/* whitelist (FR-4, FR-5)
```

No file additions, no file deletions, no new functions, no new exported variables.

## Interface Design (delta)

### Public API / Functions

| Name | Signature | Description |
| --- | --- | --- |
| `update_gitignore` | `update_gitignore <target_dir>` | (signature unchanged) Appends three idempotent blocks to `${target_dir}/.gitignore`: `.claude/*` whitelist, `.serena/`, `screenshots/`. Each block guarded by its own comment-marker `grep -q`. |
| (codex) `plugin_post_copy` gitignore step | (no signature; inline shell) | Appends one idempotent block to `${target_dir}/.gitignore`: `.codex/*` whitelist. Marker-guarded. |

The function signature does not change — only the body. Callers (`setup.sh`) need no updates.

### Block Templates (literal contract)

The exact strings appended to `.gitignore` are part of the on-disk contract — `grep -q` keys off the marker line, so changing it later would re-trigger the block append on existing projects. See [api-spec.md](./api-spec.md) for the literal block contents and marker patterns.

### Type Definitions (delta)

None. The change is in shell behavior, not data structures.

## Data Flow

`setup.sh` runs once per invocation (or per re-run on an existing project). Within that invocation:

1. `setup.sh` calls `update_gitignore "${target_dir}"` (existing call site, unchanged).
2. `update_gitignore`:
   1. Ensures `${target_dir}/.gitignore` exists (`touch` if missing).
   2. For each of the three blocks: `grep -q` the marker → append the block if absent.
3. If the Codex plugin is selected, `plugin_post_copy` runs after step 2 and applies the same pattern for the `.codex/*` block.

Re-running `setup.sh` on an already-bootstrapped project (FR-6, NFR-2) finds every marker present, every `grep -q` succeeds, and no block is appended a second time. User-authored content between or after blocks is preserved (FR-7).

The flow is rendered as a sequence in `../shared/sequence.md` and as a flowchart (this issue's per-block branching) in [flowchart.md](./flowchart.md).

## Error Handling

No new error cases. The function continues to be best-effort:

- If `${target_dir}/.gitignore` cannot be written, the existing `>>` redirection fails and propagates (callers run under `set -euo pipefail`). No special handling added.
- If `grep` fails for reasons other than "marker not found" (file unreadable), behavior matches today's: `! grep -q ...` evaluates true, the block is appended. This is consistent with the existing line-level logic and acceptable in the controlled `setup.sh` environment.

## Implementation Notes

- **Marker design (FR-6)**: Each block's first line is a comment marker that `grep -q` keys on, **anchored** to start-of-line via `^`. The chosen markers are listed in `api-spec.md`. They are part of the on-disk contract; any rename in a later release re-triggers append on existing projects, which is acceptable but should be deliberate.
- **Why block-level, not line-level**: A whitelist block has 8 lines. Line-level `grep -q` would require eight separate checks and would silently insert duplicates if the user removed (say) `!.claude/skills/`. Block-level keying tells the function "this block is owned; leave it alone."
- **Whitelist contents (FR-1)**: Mirror the directories that exist in `templates/claude/.claude/` today and are intended to be project-tracked: `commands/`, `skills/`, `scripts/`, `agents/`, `rules/`, `hooks/`, plus the file `settings.json`. New project-tracked subdirectories MUST be added to this list explicitly — that is the trade-off of the whitelist approach (acknowledged as a Risk Factor in the issue).
- **Codex whitelist contents (FR-4)**: Only `.codex/config.toml` is project-tracked. `config.local.toml` and any future local files are ignored by default.
- **Style (NFR-1)**: 4-space indent, `[[ ]]`, quoted variables, `set -euo pipefail` already in scope (callers). Inside the function, follow the existing append style (`echo "..." >> "$gitignore_file"`) rather than introducing heredocs — heredocs would require a different idempotency check and are gratuitous for ~10 lines of static text.
- **Output (NFR-3)**: The existing `print_info "Updating .gitignore..."` and `print_success ".gitignore updated"` wrap the function. No per-block messages — they would clutter setup output and the block-level idempotency is observable by reading `.gitignore`.
- **Self-referential gitignore for this repo**: Issue's "Tasks" lists "必要に応じてプロジェクト直下の `.gitignore` も同方針に揃える(別 PR でも可)". Decision: defer to a follow-up to keep this PR scope tight. The current `/workspace/.gitignore` already has `.serena/` and `.claude/settings.local.json`; aligning it would mean dropping the latter and adopting the whitelist block — easy but orthogonal.
- **TTY/non-TTY (NFR-2)**: `update_gitignore()` does no interactive I/O; trivially satisfied.

## Edge Cases

- **`.gitignore` ends without trailing newline**: Each block prepends a blank line (`echo ""`) before its marker, matching the existing style. Clean separation regardless of the previous file's terminator.
- **Block partially written (interrupted run)**: Theoretically possible if `setup.sh` is killed between `echo` calls. On re-run, `grep -q` for the marker succeeds (the marker line was the first one written, so it's present), and the partial block is not completed. Identical to today's behavior with the single-line append; acceptable.
- **User edits the block (e.g., removes `!.claude/skills/`)**: The function does not reconcile — once the marker is present, the block is left alone. Intentional (FR-7). The user "owns" the block once they edit it.
- **Marker comment exists in the user's content for unrelated reasons**: The marker strings are deliberately specific (`# Claude Code (track project configs only)`) to make accidental collision unlikely. If a collision does occur, the block is skipped and no duplicate is created — failure mode is "user-authored block wins."
