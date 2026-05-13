# API Specification: #273 fix(post): skip Claude plugin install when not authenticated to prevent first-run failure

## Functions (delta)

| Name | Signature | Description |
| --- | --- | --- |
| `is_claude_authenticated` | `() -> int` | New helper. Returns `0` iff `$HOME/.claude/.credentials.json` exists and is non-empty (`[[ -s … ]]`). Pure, no side effects, no subprocess calls. Added to **both** `setup_plugins.sh` files. |
| `try_install_plugin` | `(plugin_name, marketplace, plugins_output) -> 0` | (Template variant only — adopted from workspace variant.) Installs one plugin via `claude plugins install <name>@<marketplace> -s project`; absorbs failures so siblings continue. Always returns `0`. Workspace variant unchanged. |
| `ensure_claude_marketplace` | `(marketplace_repo) -> int` | (Template variant only — adopted from workspace variant.) Idempotent registration of a marketplace; returns `1` only on registration failure. Workspace variant unchanged. |

## Modified contracts

### `setup_plugins()` (both files)

Add a third pre-flight gate after `command -v claude`:

```bash
setup_plugins() {
    # 1. Existing prerequisite
    if ! command -v claude &> /dev/null; then
        echo "  - Warning: Claude Code CLI is not installed"
        echo "  - Plugin setup requires Claude Code"
        echo "  - Skipping plugin setup"
        return 0
    fi

    # 2. NEW pre-flight: skip cleanly when not authenticated
    if ! is_claude_authenticated; then
        echo "  - Claude Code CLI detected, but not yet authenticated"
        echo "  - To install Claude plugins, run \`claude\` to log in,"
        echo "    then re-run .devcontainer/scripts/setup_plugins.sh"
        echo "  - Skipping plugin setup"
        return 0
    fi

    # 3. Existing flow (marketplace + per-plugin install)
    # ...
}
```

### Existing contract preserved

> Contract: under `set -e` (in `post.sh`), this script MUST `return 0` even when individual plugins fail; surface them as warnings.

This contract — already documented in `docs/design/shared/api-spec.md` :: "templates/claude/.devcontainer/scripts/setup_plugins.sh" — is preserved unchanged. The new auth gate is an additional `return 0` path; it does not alter the contract.

## Behavior matrix

| Initial state of `~/.claude/.credentials.json` | Pre-#273 behavior (template variant) | Post-#273 behavior (both variants) |
| --- | --- | --- |
| Missing | `claude plugins install` exits non-zero → `set -e` aborts `post.sh` → `setup_codex` never runs | `is_claude_authenticated` returns 1 → guidance message → `return 0` → `post.sh` proceeds to `setup_codex` |
| Empty (zero-byte) | Same as missing | Same as missing (`[[ -s … ]]` rejects zero-byte) |
| Present, valid | Plugin install succeeds | Plugin install succeeds (no behavior change) |
| Present, expired | Plugin install fails inside `if`-guard (workspace) / aborts (template, pre-#273) | Auth gate passes (file exists), then existing per-plugin error isolation absorbs the failure; user sees "Warning: failed to install …" warnings and can re-run after re-auth |

## Input / Output

### `is_claude_authenticated`

| Input | Type | Description |
| --- | --- | --- |
| (none) | — | Reads `$HOME` from environment |

| Output | Type | Description |
| --- | --- | --- |
| Exit code | `0` \| `1` | `0` = credentials file exists and is non-empty; `1` = otherwise |
| stdout / stderr | (silent) | No output. Caller is responsible for printing guidance. |

## Error Handling

| Error | Code/Type | Description |
| --- | --- | --- |
| `~/.claude/.credentials.json` missing | (handled by caller; not an error) | `is_claude_authenticated` returns 1; `setup_plugins` prints guidance and returns 0 |
| `~/.claude/.credentials.json` exists but is zero-byte | (handled by caller; not an error) | Same as above; `[[ -s … ]]` is the guard |
| `$HOME` unset | (does not occur in devcontainer post-create) | Defensive quoting (`"$HOME/.claude/.credentials.json"`) prevents word-splitting; the `[[ -s … ]]` test on an empty path returns false → treated as unauthenticated |

No new error variants in the project's Rust error type or shell exit codes. The change is entirely additive at the shell-function level.
