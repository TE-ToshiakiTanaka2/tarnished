# Code Review: #273

- **Branch**: bugfix/TE-ToshiakiTanaka2/#273/skip-claude-plugin-install-when-not-authenticated
- **Base**: develop (merge base: b104dff)
- **Review scope**: Medium (~107 lines of shell code; total diff 494/-47 dominated by design docs)
- **Reviewed at**: 2026-05-08T08:11:08Z
- **Reviewer**: Codex CLI (gpt-5.4, reasoning effort high)

---

### Warnings (should fix)
- [.devcontainer/scripts/setup_plugins.sh:109] and [templates/claude/.devcontainer/scripts/setup_plugins.sh:109] `plugins_output=$(claude plugins list 2>/dev/null)` is still an unguarded simple command under `set -e`. In Bash, a failed command substitution in an assignment exits unless it is wrapped by a conditional, so `post.sh` can still abort before `setup_codex` if `claude plugins list` fails after the auth/marketplace gates. That means the new "always return 0 / per-plugin failures are isolated" contract is not actually true yet. Wrap this in an `if ! plugins_output=$(...); then ...; return 0; fi` path, mirroring the rest of the best-effort flow.

### Suggestions (nice to have)
- [docs/design/#273/workflow.md:89] Manual verification is reasonable for the narrow missing-credentials fix, but this script's behavior depends on subtle Bash `set -e` semantics. A tiny smoke test for "no credentials" and "`claude plugins list` fails" would give much better regression protection than docs-only verification.

### Positive
- The new auth gate is placed before any `claude plugins ...` call, which addresses the first-run unauthenticated case directly.
- Aligning the template copy with the workspace copy removes the previous divergence in failure handling and makes future fixes easier to keep in sync.

Verdict: REQUEST_CHANGES

---

## Fixes Applied

- **Warning fix** — Wrapped `plugins_output=$(claude plugins list 2>/dev/null)` in an `if`-guard with `return 0` on failure, symmetric with the marketplace registration failure path. Applied to BOTH `.devcontainer/scripts/setup_plugins.sh` and `templates/claude/.devcontainer/scripts/setup_plugins.sh` (workspace ↔ template parity preserved; verified by `diff` and by the new bats parity test).
- **Suggestion** — Added `tests/setup_plugins.bats` with 7 cases:
  1. `is_claude_authenticated` — missing credentials → non-zero
  2. `is_claude_authenticated` — empty (zero-byte) credentials → non-zero
  3. `is_claude_authenticated` — non-empty credentials → zero
  4. `setup_plugins` — missing credentials → skips with guidance, `claude` never invoked (verified via PATH-shim mock + invocation log)
  5. `setup_plugins` — `claude plugins list` failure under `set -e` → returns 0 (regression guard for the warning)
  6. `setup_plugins` — marketplace registration failure under `set -e` → returns 0
  7. `setup_plugins.sh` workspace ↔ template byte-identical parity (regression guard for the #273 invariant)
- All 7 tests pass locally (verified with `bats-support` / `bats-assert` set up the same way as the rest of the project's bats suite).
- Synced `docs/design/shared/api-spec.md` (added plugins-list failure error row) and `docs/design/shared/sequence.md` (added plugins-list query failure branch to the devcontainer plugin install flow). Per-issue `docs/design/#273/design.md` and `workflow.md` updated to reflect the actual implementation.
- Commit: `261f305 fix: address review feedback for #273`
