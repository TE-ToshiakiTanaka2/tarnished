# Design: #273 fix(post): skip Claude plugin install when not authenticated to prevent first-run failure

## Context

Both copies of `setup_plugins.sh` are sourced from `post.sh` under `set -e`:

- **Workspace** (`/workspace/.devcontainer/scripts/setup_plugins.sh`) — runs against the tarnished repo itself; the dogfooded variant (#249, #255) wraps every `claude plugins ...` call in an `if`-guard and returns `0` on every per-plugin failure.
- **Template** (`/workspace/templates/claude/.devcontainer/scripts/setup_plugins.sh`) — copied verbatim into downstream Claude-flavor projects by `setup.sh` (templates/claude plugin); calls `claude plugins install <name>@claude-plugins-official -s project` **without** an `if`-guard, so any non-zero exit from `claude` directly trips `set -e` in `post.sh`.

The shared layer (`docs/design/shared/architecture.md` :: "Cross-cutting Concerns / Idempotency", and `docs/design/shared/sequence.md` :: "devcontainer plugin install (#249, #255)") already establishes the invariant: under `set -e`, `setup_plugins.sh` MUST `return 0` even when individual plugins fail. The bug here is two-fold:

1. The template variant violates the existing invariant (no `if`-guard around the install).
2. Both variants assume `claude` is authenticated; on a brand-new container with no `~/.claude/.credentials.json`, every `claude plugins ...` invocation fails with a non-zero exit before any meaningful work happens. Even when the workspace variant absorbs the failure inside its `if`-guard, the user still sees a wall of misleading "Warning: failed to register/install" output and pays the cost of attempting every plugin in turn.

The fix preserves all existing behavior for already-authenticated users and adds an explicit pre-flight authentication gate.

## Architecture Overview (delta)

A new helper `is_claude_authenticated()` is added to **both** `setup_plugins.sh` files (workspace and template) — kept in sync per the workspace-dogfooding convention (`architecture.md` :: "Workspace Codex dogfooding (#261)" describes the same pattern for `setup_codex.sh`). The helper performs a single, dependency-free check: `[[ -s "$HOME/.claude/.credentials.json" ]]`.

`setup_plugins()` calls it immediately after the existing `command -v claude` prerequisite check. If the helper returns non-zero, `setup_plugins` prints a one-line guidance message ("Claude is not yet authenticated; run `claude` to log in, then re-run `.devcontainer/scripts/setup_plugins.sh`") and `return 0`s, leaving `post.sh` to proceed normally to `setup_codex` and any subsequent steps.

In addition (defense-in-depth — independent of the auth gate), the template variant's three bare `claude plugins install` calls are restructured into `try_install_plugin()`-style `if`-guarded wrappers, mirroring the workspace variant. The marketplace check from #255 (`ensure_claude_marketplace`) is also adopted by the template so its first-run flow no longer relies on installs to implicitly register the marketplace.

After this change, the two files are structurally identical except for cosmetic differences (comment wording). This intentional convergence simplifies future edits and matches the dogfooding pattern described in `shared/architecture.md` :: "Workspace Codex dogfooding (#261)".

## Module Structure (delta)

```
.devcontainer/scripts/
├── post.sh                   # Unchanged
├── setup_plugins.sh          # MODIFIED: add is_claude_authenticated() + early-return guard
└── setup_codex.sh            # Unchanged

templates/claude/.devcontainer/scripts/
└── setup_plugins.sh          # MODIFIED: add is_claude_authenticated() + early-return guard
                              #           + adopt try_install_plugin / ensure_claude_marketplace
                              #             (defense-in-depth alignment with workspace variant)
```

No new files. No changes to `post.sh` (the source pattern continues to invoke `setup_plugins`). No changes to `setup_codex.sh`. No changes to `templates/claude/plugin.sh` (the plugin's `plugin_copy` already vendors `setup_plugins.sh` verbatim).

## Interface Design (delta)

### New functions (both `setup_plugins.sh` files)

| Name | Signature | Description |
| --- | --- | --- |
| `is_claude_authenticated` | `() -> int` | Returns `0` iff `$HOME/.claude/.credentials.json` exists and is non-empty. Pure check, no I/O beyond `[[ -s … ]]`. |

### Modified functions

| Name | Change | Description |
| --- | --- | --- |
| `setup_plugins` (both files) | Add early-return after `command -v claude` check | If `is_claude_authenticated` returns non-zero, print one-line guidance and `return 0`. |
| `setup_plugins` (template only) | Adopt workspace variant's structure | Replace bare `claude plugins install …` calls with `try_install_plugin "<name>" "claude-plugins-official" "${plugins_output}"`. Add `ensure_claude_marketplace "anthropics/claude-plugins-official"` (early-return-on-failure with `return 0`). |
| `try_install_plugin` (template, new) | Mirror workspace variant verbatim | Same signature: `(plugin_name, marketplace, plugins_output)`. Always returns `0` so per-plugin failures do not crash `post.sh`. |
| `ensure_claude_marketplace` (template, new) | Mirror workspace variant verbatim | Same signature: `(marketplace_repo)`. Returns `1` only on registration failure. |

### Type Definitions (delta)

None.

## Data Flow

`post.sh` sources `setup_plugins.sh`, which immediately decides whether to attempt any `claude` invocation at all:

1. `command -v claude` — prerequisite check (existing, unchanged).
2. **NEW:** `is_claude_authenticated` — credentials file check.
3. If unauthenticated: print guidance, `return 0`. `post.sh` continues to `setup_codex`.
4. If authenticated: existing flow — `ensure_claude_marketplace` → `claude plugins list` → per-plugin `try_install_plugin`.

The auth check is the minimum gate that prevents `claude plugins …` from ever being called on an unauthenticated system. It does not attempt to validate that the credentials are still good (token revocation, expiry) — that case falls back to the existing per-plugin failure isolation in `try_install_plugin` / `ensure_claude_marketplace`. This two-layer strategy (gate + isolation) intentionally mirrors `architecture.md` :: "Cross-cutting Concerns / Plugin failures".

## Error Handling

| Condition | Detection | Response |
| --- | --- | --- |
| `claude` CLI not on `$PATH` | `command -v claude` (existing) | Print `[Warning] Claude Code CLI is not installed`, `return 0` |
| **`~/.claude/.credentials.json` missing or empty (NEW)** | `[[ -s "$HOME/.claude/.credentials.json" ]]` | Print `Claude is not yet authenticated; run \`claude\` to log in, then re-run .devcontainer/scripts/setup_plugins.sh`, `return 0` |
| Marketplace registration fails (e.g. credentials present but expired) | `ensure_claude_marketplace` non-zero | Print `Warning: failed to register marketplace …`, `return 0` from `setup_plugins` (existing in workspace variant; new in template variant) |
| Per-plugin install fails | `try_install_plugin` (existing in workspace; new in template) | Print `Warning: failed to install <name> plugin`, continue to next plugin |

All paths exit `setup_plugins` with `0`, preserving the `set -e` / non-fatal contract documented in `shared/architecture.md` :: "Cross-cutting Concerns / Idempotency / Plugin failures".

## Implementation Notes

- **Detection signal stability**: `~/.claude/.credentials.json` is the OAuth credential file written by `claude` after a successful interactive login. It is created on first login and persists across container rebuilds when `~/.claude/` is mounted from the host (the standard devcontainer pattern). The `[[ -s … ]]` check (file exists AND non-empty) is robust against partial-write edge cases and against the rare case of a zero-byte placeholder file. This is the same check used implicitly by `claude` itself when it decides whether to prompt for login — we are not introducing a new detection convention, just gating on it earlier.

- **Why not `claude auth status` (or similar)**: The user explicitly requested the file-existence approach (no network calls, no subprocess overhead, no risk of hanging on a transient network error). This also avoids depending on a `claude` subcommand whose name or exit code could change across versions — `~/.claude/.credentials.json` has been the credential location since Claude Code's introduction.

- **Workspace + template parity**: The two `setup_plugins.sh` files MUST stay structurally identical (modulo comments) after this change, mirroring the workspace-Codex dogfooding pattern (#261). A future bug or improvement applied to one MUST be applied to the other in the same commit. This keeps the workspace's own first-run experience aligned with what downstream Claude-flavor projects see.

- **`set -e` interaction**: All new code paths are inside function bodies invoked via `setup_plugins; …` from `post.sh`. Because `setup_plugins` is the last statement in the source-and-call block (`source setup_plugins.sh; setup_plugins`) and is contractually required to return `0`, the existing `set -e` semantics are preserved without touching `post.sh`.

- **Idempotency**: The auth check is idempotent by construction (read-only). Re-running `setup_plugins.sh` after `claude` login will pass the gate and proceed to the existing idempotent install flow (marketplace check uses `claude plugins marketplace list | grep -q`, plugin checks use `claude plugins list | grep -q`).

- **Edge case — credentials present but expired**: Out of scope for this issue. The existing per-plugin error isolation will absorb the failure and emit warnings; the user will see "Warning: failed to register marketplace" / "Warning: failed to install …" and can re-run after `claude` re-authentication. A more sophisticated check (e.g. probing token validity) is not justified by the user impact; the file-existence gate handles the dominant first-run case.

- **Edge case — `$HOME` unset or unusual**: `setup_plugins.sh` is sourced by `post.sh` which runs as the devcontainer's non-root user. `$HOME` is always set in that context. Defensive quoting (`"$HOME/.claude/.credentials.json"`) per `.claude/rules/shell.md`.

- **Output style**: Uses the existing `echo "  - …"` indented-bullet style of `setup_plugins.sh`. No new output helpers (`print_info`, etc.) — those exist in `scripts/lib/common.sh` for the `setup.sh` orchestrator and are not in scope here. Consistency with existing block.
