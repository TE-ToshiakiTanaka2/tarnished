# Workflow: #259 Expand `update_gitignore()` — whitelist `.claude/.codex`, ignore `.serena/screenshots`

## Implementation Steps

### Step 1: Refactor `update_gitignore()` in `scripts/lib/common.sh`

- **Action**: Replace the body of `update_gitignore()` (currently lines ~414–433) with the new three-block structure. Drop the existing `.claude/settings.local.json` append (FR-5). Add three blocks, each guarded by `grep -q` on a comment marker (FR-6). Preserve the function signature, the surrounding `print_info` / `print_success` wrap, and the `touch` of a missing `.gitignore`.
- **Files**:
  - `scripts/lib/common.sh` (modified — only `update_gitignore()`)
- **Block contents**: see [api-spec.md](./api-spec.md) — Blocks 1, 2, 3.
- **Depends on**: nothing.
- **Done when**:
  - The function still has signature `update_gitignore <target_dir>`.
  - On a fresh `.gitignore`, running the function yields the three blocks in order: Claude whitelist, `.serena/`, `screenshots/`.
  - Re-running on the same `.gitignore` is a no-op (byte-identical).
  - The previous `.claude/settings.local.json` line and its comment are gone.
  - `bash -n scripts/lib/common.sh` passes.

### Step 2: Refactor gitignore step in `templates/codex/plugin.sh::plugin_post_copy`

- **Action**: Replace the existing `.codex/config.local.toml` append block (currently `templates/codex/plugin.sh:134-141`) with the `.codex/*` whitelist block guarded by its own marker (FR-4, FR-5, FR-6).
- **Files**:
  - `templates/codex/plugin.sh` (modified — only the gitignore section of `plugin_post_copy`)
- **Block contents**: see [api-spec.md](./api-spec.md) — Block 4.
- **Depends on**: nothing (independent of Step 1; the codex plugin runs after `update_gitignore` but does not depend on its block markers).
- **Done when**:
  - On a fresh `.gitignore`, the codex plugin appends exactly Block 4.
  - Re-running on the same `.gitignore` is a no-op.
  - The previous `.codex/config.local.toml` line and its comment are gone.
  - `bash -n templates/codex/plugin.sh` passes.

### Step 3: Smoke test — fresh target

- **Action**: From a scratch directory, run `setup.sh -y --lang node` (or any minimal flag set) into a temporary target. Inspect the generated `.gitignore` and verify all three blocks (and Block 4 if Codex is selected) are present, in the documented order, with the correct content.
- **Files**: none modified — verification only.
- **Depends on**: Steps 1, 2.
- **Done when**:
  - `cat <target>/.gitignore` shows Blocks 1–3 (and 4 with Codex).
  - No `.claude/settings.local.json` literal line is present (it's covered by Block 1).

### Step 4: Smoke test — idempotent re-run

- **Action**: Re-run `setup.sh` against the same target directory created in Step 3. Verify that `.gitignore` is byte-identical (`diff` is empty) before and after the re-run.
- **Files**: none modified — verification only.
- **Depends on**: Step 3.
- **Done when**:
  - `diff <gitignore-before> <gitignore-after>` is empty.

### Step 5: Smoke test — user-edited `.gitignore` preservation

- **Action**: After Step 3, append a user-authored line (e.g., `node_modules/`) and a user-authored comment (e.g., `# my own ignore`) to the generated `.gitignore`. Re-run `setup.sh`. Verify the user content is preserved and no duplicate blocks are added.
- **Files**: none modified — verification only.
- **Depends on**: Step 3.
- **Done when**:
  - User-authored lines are still present after re-run.
  - Each block marker still appears exactly once.

### Step 6: Smoke test — Codex plugin gating

- **Action**: Run `setup.sh` once without selecting the Codex plugin (default), once with it selected. Confirm Block 4 appears only in the Codex case.
- **Files**: none modified — verification only.
- **Depends on**: Step 2.
- **Done when**:
  - No-Codex run: Blocks 1–3 only.
  - With-Codex run: Blocks 1–4.

### Step 7: Commit

- **Action**: Single commit covering both file changes and the design artifacts (already on branch from `/design`).
- **Suggested message**:
  ```
  feat(scripts): whitelist .claude/.codex and ignore .serena/screenshots in update_gitignore

  Replace per-file blacklist entries in update_gitignore() and the Codex
  plugin gitignore step with marker-guarded whitelist blocks. Default-deny
  for .claude/* and .codex/*; explicit allowlist for project-tracked subdirs.
  Adds .serena/ and screenshots/ as always-ignored.

  Closes #259
  ```
- **Depends on**: Steps 1–6.
- **Done when**:
  - `git status` is clean post-commit.
  - The commit is on the `feature/.../#259/...` branch.

## Task Dependencies

```
Step 1 ──┐
         ├──> Step 3 ──> Step 4
Step 2 ──┘                │
                          ├──> Step 7
                Step 5 ───┤
                Step 6 ───┘
```

Steps 1 and 2 are independent and can be done in parallel. Steps 3–6 are smoke tests that depend on the implementation steps. Step 7 is the final commit.

## Test Strategy

This issue has no unit tests because:

- `update_gitignore()` is a thin wrapper around `echo "$line" >> "$file"` and `grep -q`. The logic is in idempotency markers and literal text — assertable by `cat`/`diff` against an expected file rather than by a unit-test harness.
- The repo does not currently have a Bats (or equivalent) suite for `scripts/lib/common.sh`. Introducing one for this one function is out of scope; the project conventions document smoke tests via `setup.sh` instead.

**Smoke tests** (Steps 3–6) cover:

- Fresh target: all blocks present, correct order, correct contents.
- Re-run: byte-identical idempotency.
- User-edit preservation: user content untouched; no duplicate blocks.
- Plugin gating: `.codex/*` block appears only with the Codex plugin selected.

**Edge cases to cover** (during Step 3 verification):

- `.gitignore` did not exist before (Step 3 default — `setup.sh` runs against fresh dir).
- `.gitignore` existed but was empty.
- `.gitignore` existed and had user content (Step 5).
- Trailing-newline absence in pre-existing `.gitignore`: blocks should still separate cleanly via the leading `echo ""`.
