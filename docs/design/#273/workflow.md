# Workflow: #273 fix(post): skip Claude plugin install when not authenticated to prevent first-run failure

## Implementation Steps

### Step 1: Add `is_claude_authenticated` helper to workspace `setup_plugins.sh`

- **Action**: Add a small helper function `is_claude_authenticated()` at the top of the workspace `setup_plugins.sh` (above `ensure_claude_marketplace`). Implementation: `[[ -s "$HOME/.claude/.credentials.json" ]]`. Add a header comment describing the contract (returns 0 iff file exists and is non-empty).
- **Files**: `/workspace/.devcontainer/scripts/setup_plugins.sh`
- **Depends on**: nothing
- **Done when**: Function exists, follows `.claude/rules/shell.md` (quoting, `[[ ]]`, comment header).

### Step 2: Wire the auth gate into workspace `setup_plugins()`

- **Action**: Inside `setup_plugins()` in the workspace file, immediately after the existing `command -v claude` block (and before `echo "  - Claude Code CLI detected"`), add an `is_claude_authenticated` check that prints the three-line guidance message and `return 0`s when unauthenticated. Also drop or relocate the existing `echo "  - Claude Code CLI detected"` so the auth-fail path does not produce a misleading "detected" message followed immediately by a "not authenticated" message.
- **Files**: `/workspace/.devcontainer/scripts/setup_plugins.sh`
- **Depends on**: Step 1
- **Done when**: Calling `setup_plugins` with `~/.claude/.credentials.json` absent produces only the guidance message and exits 0; calling it with credentials present is byte-identical to pre-change behavior.

### Step 3: Mirror Steps 1–2 in the template `setup_plugins.sh`

- **Action**: Add `is_claude_authenticated` and the auth gate to the template variant. Use the **same** helper body and the **same** guidance wording so the two files stay in sync.
- **Files**: `/workspace/templates/claude/.devcontainer/scripts/setup_plugins.sh`
- **Depends on**: nothing (parallelizable with Steps 1–2, but logically follows so the workspace version is the reference)
- **Done when**: The two `setup_plugins.sh` files differ only in cosmetic comment wording (verified via `diff`).

### Step 4: Adopt `ensure_claude_marketplace` and `try_install_plugin` in the template variant

- **Action**: Copy `ensure_claude_marketplace()` and `try_install_plugin()` from the workspace variant into the template variant verbatim. Replace the three bare `claude plugins install …` calls in `setup_plugins()` (context7, serena, playwright) with `try_install_plugin "<name>" "claude-plugins-official" "${plugins_output}"`. Replace the implicit-marketplace assumption with an explicit `ensure_claude_marketplace "anthropics/claude-plugins-official"` early-return-on-failure wrapper at the top of `setup_plugins`. Update the file's leading docstring to describe the failure policy block (matching the workspace variant's wording).
- **Files**: `/workspace/templates/claude/.devcontainer/scripts/setup_plugins.sh`
- **Depends on**: Step 3
- **Done when**: The template variant matches the workspace variant structurally. `diff` shows only cosmetic differences. The bare `claude plugins install` lines are gone.

### Step 5: Manually verify the first-run flow

- **Action**: Simulate the bug locally:
  ```bash
  # Save credentials (so we can restore)
  test -f "$HOME/.claude/.credentials.json" && cp "$HOME/.claude/.credentials.json" /tmp/.creds.bak
  rm -f "$HOME/.claude/.credentials.json"
  bash -c 'set -e; source /workspace/.devcontainer/scripts/setup_plugins.sh; setup_plugins; echo "STILL ALIVE"'
  # Restore
  test -f /tmp/.creds.bak && cp /tmp/.creds.bak "$HOME/.claude/.credentials.json"
  ```
  Verify output ends with `STILL ALIVE` (i.e. `set -e` did NOT abort) and includes the new "not yet authenticated" guidance line.
- **Files**: (test only, no edits)
- **Depends on**: Steps 1–2
- **Done when**: `STILL ALIVE` is printed; no "Warning: failed to register marketplace" lines appear; `claude plugins …` is never invoked (verifiable by capturing `claude` invocation count via a wrapper, or simply by inspecting the script output for absence of the marketplace banner).

### Step 6: Manually verify the normal flow (regression check)

- **Action**: With `~/.claude/.credentials.json` present, run the same `setup_plugins` invocation. Verify it executes the marketplace check + `try_install_plugin` flow exactly as before.
- **Files**: (test only, no edits)
- **Depends on**: Steps 1–4
- **Done when**: The output is byte-identical (modulo any pre-existing dynamic content like timestamps) to a known-good prior run captured before the change.

### Step 7: Run shellcheck and existing test suite

- **Action**: `shellcheck /workspace/.devcontainer/scripts/setup_plugins.sh /workspace/templates/claude/.devcontainer/scripts/setup_plugins.sh`. Run the existing `tests/*.bats` suite to confirm no regression in unrelated scripts. (No new bats tests are added — the change is small and verified manually per the issue's task list.)
- **Files**: (test only, no edits)
- **Depends on**: Steps 1–4
- **Done when**: shellcheck reports no new findings; bats suite passes.

### Step 8: Update inline comments / docstrings

- **Action**: Review the leading comment block of each `setup_plugins.sh` and update the "Failure policy" / behavior summary to mention the auth-gate. Keep comments short — one or two new lines, no docstring inflation.
- **Files**: `/workspace/.devcontainer/scripts/setup_plugins.sh`, `/workspace/templates/claude/.devcontainer/scripts/setup_plugins.sh`
- **Depends on**: Steps 1–4
- **Done when**: The leading comment block accurately describes the auth-gate behavior in both files.

## Task Dependencies

```
Step 1 (workspace helper)
    └→ Step 2 (workspace gate)
              └→ Step 3 (template helper + gate)
                        └→ Step 4 (template defense-in-depth)
                                  ├→ Step 5 (verify first-run)
                                  ├→ Step 6 (verify normal flow)
                                  ├→ Step 7 (shellcheck + bats)
                                  └→ Step 8 (comments)
```

Steps 5–8 can run in parallel after Step 4. Steps 1–2 and 3 cannot reasonably parallelize because Step 3 must mirror the final shape of the workspace variant, and Step 4 builds on Step 3.

## Test Strategy

### Unit Tests

`tests/setup_plugins.bats` (added during `/review` follow-up) covers the post.sh `set -e` non-fatal-return-0 contract and the workspace ↔ template parity invariant:

- `is_claude_authenticated` returns non-zero for missing / empty credentials and zero for non-empty credentials.
- `setup_plugins` with no credentials prints guidance, returns 0, and never invokes `claude` (verified via PATH-shim mock).
- `setup_plugins` survives a `claude plugins list` failure under `set -e` (the residual exposure flagged in the Codex review).
- `setup_plugins` survives a marketplace-registration failure under `set -e`.
- The workspace and template `setup_plugins.sh` files are byte-identical (regression guard for the parity invariant).

The fixtures use a per-test `mktemp` `HOME` and a PATH-shim `claude` mock — no project-wide infrastructure needed beyond the bats helper libs already required by the other `tests/*.bats` fixtures (`bats-support`, `bats-assert`).

### Integration Tests

Manual integration tests cover both code paths:

- **First-run (unauthenticated) path** — Step 5. The critical assertion is "post.sh continues past the plugin step" — i.e. `setup_codex` runs after `setup_plugins` skips. This is the user-visible bug being fixed.
- **Normal (authenticated) path** — Step 6. Regression assertion: byte-equivalent to prior behavior.

### Edge Cases

- **Zero-byte `.credentials.json`** — `[[ -s … ]]` returns false, treated as unauthenticated. Same as missing file. Manually testable by `truncate -s 0 ~/.claude/.credentials.json` before invoking.
- **Credentials present but expired** — Auth gate passes (file exists), existing per-plugin error isolation handles the downstream failure. Manually testable by mutating the credentials file content; not blocking for this fix.
- **`$HOME` unset** — Treated as unauthenticated (defensive quoting; empty path fails `-s`). Not a real-world devcontainer scenario, but the code path is covered by the same guard.
- **Re-running after login** — Idempotent: helper is read-only, downstream flow uses existing `grep -q` idempotency for marketplace + plugin presence.

## Quality Checklist

- [ ] `shellcheck` clean on both files
- [ ] `.claude/rules/shell.md` compliance: `[[ ]]` over `[ ]`, `local` for function variables, double-quoted expansions, no `eval`
- [ ] Two `setup_plugins.sh` files structurally equivalent (`diff` shows only comment differences)
- [ ] First-run scenario validated (Step 5)
- [ ] Normal-run scenario validated (Step 6)
- [ ] No changes to `post.sh`, `setup_codex.sh`, or `templates/claude/plugin.sh`
