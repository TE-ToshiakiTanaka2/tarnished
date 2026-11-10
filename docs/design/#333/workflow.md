# Workflow: #333 chore: rebind lifecycle roles to Fable 5.2 (high) / Opus 5.5 (designer high, executor medium)

Literal value edits across mirrored configuration plus one regression test. The order exists so the delegation table (Step 3) is written against values that are already in the channel files, and the mutation check (Step 5) runs against a test that already passes. `docs/design/shared/{data-model,api-spec}.md` are regenerated in the design commit and are not edited during implementation.

Helper used in several checks — prints a file's YAML frontmatter:

```bash
fm() { awk 'NR==1 && $0=="---" {f=1; next} f && $0=="---" {exit} f' "$1"; }
```

## Implementation Steps

### Step 1: Orchestrator channel — `.claude/settings.json` (FR-1, NFR-3)

- **Action**: In both files change `"model": "claude-fable-5-1"` to `"model": "claude-fable-5-2"` and insert `"effortLevel": "high",` on the next line (2-space indent, same as the file). Change nothing else.
- **Files**: `.claude/settings.json`, `templates/claude/.claude/settings.json`
- **Depends on**: nothing
- **Done when**:
  - `jq -r '.model, .effortLevel' .claude/settings.json` and the same on the template both print `claude-fable-5-2` then `high`
  - `cmp .claude/settings.json templates/claude/.claude/settings.json` exits 0 (not enforced by `verify-mirrors.sh`, but required: the workspace refreshes this file from the template)
  - `diff <(git show develop:.claude/settings.json | jq -S 'del(.model, .effortLevel)') <(jq -S 'del(.model, .effortLevel)' .claude/settings.json)` prints nothing (NFR-3), and the same for the template path
  - `git diff --numstat develop -- .claude/settings.json templates/claude/.claude/settings.json` shows `2	1` for each file

### Step 2: Delegated-agent channels — frontmatter (FR-2, FR-3, FR-7)

- **Action**: `designer.md`: add `effort: high` directly after `model: claude-opus-5-5[1m]`. `executor.md`: change `model: claude-sonnet-5-5` to `model: claude-opus-5-5` and add `effort: medium` directly after it. Apply the identical edit to the template copies (or copy the workspace file over the template). Bodies unchanged; `code-reviewer.md` untouched.
- **Files**: `.claude/agents/designer.md`, `templates/claude/.claude/agents/designer.md`, `.claude/agents/executor.md`, `templates/claude/.claude/agents/executor.md`
- **Depends on**: nothing
- **Done when**:
  - `fm .claude/agents/designer.md | grep -cx -e 'model: claude-opus-5-5\[1m\]' -e 'effort: high'` prints `2`
  - `fm .claude/agents/executor.md | grep -cx -e 'model: claude-opus-5-5' -e 'effort: medium'` prints `2`
  - `cmp .claude/agents/designer.md templates/claude/.claude/agents/designer.md && cmp .claude/agents/executor.md templates/claude/.claude/agents/executor.md`
  - `git diff --quiet develop -- .claude/agents/code-reviewer.md templates/claude/.claude/agents/code-reviewer.md`

### Step 3: Model binding table — delegation skill (FR-4, NFR-2)

- **Action**: Apply the four edits specified in [design.md](./design.md) :: "Exact edits" to the `## Model binding` section: the "model and reasoning effort" opening sentence and Claude-only frontmatter clause, the five-column table (Role / Model channel / Model / Effort channel / Effort), the rewritten orchestrator paragraph (`effortLevel` accepted set, `modelSettings` precedence), and the new effort-precedence paragraph after the model precedence table. Copy the result to the template mirror.
- **Files**: `.claude/skills/_shared/delegation/SKILL.md`, `templates/claude/.claude/skills/_shared/delegation/SKILL.md`
- **Depends on**: Steps 1, 2 (the table states their values)
- **Done when**:
  - The table matches the channel files:
    ```bash
    s=.claude/skills/_shared/delegation/SKILL.md
    grep -F "| \`orchestrator\` | \`.claude/settings.json :: model\` | \`$(jq -r .model .claude/settings.json)\` | \`.claude/settings.json :: effortLevel\` | \`$(jq -r .effortLevel .claude/settings.json)\` |" "$s"
    grep -F "| \`designer\` | \`.claude/agents/designer.md\` frontmatter \`model:\` | \`claude-opus-5-5[1m]\` | \`.claude/agents/designer.md\` frontmatter \`effort:\` | \`high\` |" "$s"
    grep -F "| \`executor\` | \`.claude/agents/executor.md\` frontmatter \`model:\` | \`claude-opus-5-5\` | \`.claude/agents/executor.md\` frontmatter \`effort:\` | \`medium\` |" "$s"
    ```
    each prints exactly one line
  - `grep -c 'CLAUDE_CODE_EFFORT_LEVEL' "$s"` ≥ 1 and `grep -c 'modelSettings' "$s"` ≥ 1
  - `scripts/verify-mirrors.sh` ends with `all mirror pairs are byte-identical`

### Step 4: `effortLevel` round-trip test (FR-6)

- **Action**: Add the test below to `tests/common_json.bats`, directly after `@test "merge_claude_settings preserves unrelated top-level keys across repeated merges"` (before the `dedups hooks` test). It mirrors the `.model` test's shape — first merge, re-merge of the same overlay — and adds the add-module path, where the overlay is a language fragment without `effortLevel`. The fixture value is `xhigh`, deliberately not a shipped pin, so the test is never a second declaration site (NFR-2) and needs no edit on a future re-pin.
- **Files**: `tests/common_json.bats`
- **Depends on**: nothing (independent of Steps 1-3)
- **Done when**: `bats tests/common_json.bats` passes, including the new test. (If the `bats` mise shim errors on this machine, run the installed binary directly, e.g. `~/.local/share/mise/installs/bats/1.14.0/bats-core-1.14.0/bin/bats`.)

```bash
# effortLevel is the orchestrator's reasoning-effort pin (#333). It reaches a
# generated project through the claude template's settings overlay and must
# survive every later merge: the `setup.sh --upgrade` re-merge of the same
# overlay, and an add-module merge whose language fragment carries no
# effortLevel. The fixture value is not a shipped pin on purpose.
@test "merge_claude_settings preserves effortLevel across repeated merges" {
    local base_file="$SCRATCH/settings.json"
    local overlay_file="$SCRATCH/claude.json"
    local module_overlay="$SCRATCH/module.json"
    local first_output="$SCRATCH/first.json"
    local second_output="$SCRATCH/second.json"
    local third_output="$SCRATCH/third.json"

    cat > "$base_file" <<'JSON'
{
  "permissions": { "allow": [], "deny": [] },
  "hooks": { "PreToolUse": [] }
}
JSON

    cat > "$overlay_file" <<'JSON'
{
  "effortLevel": "xhigh",
  "permissions": { "allow": [], "deny": ["Bash(rm -rf /*)"] },
  "hooks": { "PreToolUse": [] }
}
JSON

    cat > "$module_overlay" <<'JSON'
{
  "permissions": { "allow": ["Bash(cargo:*)"], "deny": [] },
  "hooks": { "PostToolUse": [] }
}
JSON

    # Scaffold: the overlay supplies the key.
    run merge_claude_settings "$base_file" "$overlay_file" "$first_output"
    assert_success
    run jq -r '.effortLevel' "$first_output"
    assert_output "xhigh"

    # `setup.sh --upgrade`: the same overlay merged again.
    run merge_claude_settings "$first_output" "$overlay_file" "$second_output"
    assert_success
    run jq -r '.effortLevel' "$second_output"
    assert_output "xhigh"

    # Add-module: the overlay has no effortLevel; the base's value survives.
    run merge_claude_settings "$second_output" "$module_overlay" "$third_output"
    assert_success
    run jq -r '.effortLevel' "$third_output"
    assert_output "xhigh"
}
```

### Step 5: Prove the test fails when `effortLevel` is dropped (FR-6 acceptance)

- **Action**: Temporarily change the merge expression in `scripts/lib/common.sh::merge_claude_settings` from `($base * $overlay)` to `($base * $overlay | del(.effortLevel))`, run the new test, then revert the change.
- **Files**: `scripts/lib/common.sh` (temporary, reverted; never committed)
- **Depends on**: Step 4
- **Done when**:
  - With the mutation, `bats -f 'preserves effortLevel' tests/common_json.bats` fails at the first `assert_output "xhigh"`
  - After reverting, `git diff --quiet develop -- scripts/lib/common.sh` exits 0 and the same `bats -f` run passes
  - The PR body records that the mutation check was run

### Step 6: Whole-change verification (FR-5, FR-7, NFR-1, NFR-2, NFR-3)

- **Action**: Run the checks below on the final tree.
- **Files**: none
- **Depends on**: Steps 1-5
- **Done when**:
  - FR-5, over tracked files (`.tarnished/backups/` is gitignored restoration material that already holds the old IDs and is never edited): `git grep -n -e 'claude-fable-5-1' -e 'claude-sonnet-5-5' -- .claude .tarnished .codex templates docs/design/shared` prints nothing. Equivalent filesystem form: `grep -rn --exclude-dir=backups "claude-fable-5-1\|claude-sonnet-5-5" .claude .tarnished .codex templates/ docs/design/shared/` prints nothing
  - FR-7: `git diff --quiet develop -- .claude/agents/code-reviewer.md templates/claude/.claude/agents/code-reviewer.md .tarnished/agent-profile.json templates/agent-workflows/.tarnished/agent-profile.json`
  - NFR-1: `scripts/verify-mirrors.sh` passes
  - NFR-2: `git grep -n -e '"effortLevel"' -e '^effort:' -- . ':!docs' ':!tests'` lists only the two `settings.json` copies and the four designer/executor agent files; `git grep -l 'effortLevel' -- templates/languages templates/core templates/codex` prints nothing
  - NFR-3: the Step 1 `jq -S 'del(...)'` diffs still print nothing
  - Scope: `git diff --name-only develop...HEAD` lists only the files in [design.md](./design.md) :: Module Structure (plus the design commit's `docs/design/` paths)
  - Full suite: every `tests/*.bats` file passes (same `bats` invocation note as Step 4)

### Step 7 (best-effort, manual): Runtime smoke check

- **Action**: In a fresh Claude Code session in the workspace, confirm the session reports `claude-fable-5-2` and effort `high` (e.g. `/status` or `/model`), and that dispatching `designer` and `executor` raises no unknown-model or invalid-effort warning. Do not restart the devcontainer to do this: the workspace refresh pulls `develop` and would revert this branch's `.claude/` edits (restore with `git checkout -- <path>` if it happens).
- **Files**: none
- **Depends on**: Steps 1-3
- **Done when**: the outcome (confirmed, or not possible in this environment) is recorded in the PR body. A failure here is a blocker to raise with the orchestrator, not something to work around by changing a pin

## Test Strategy

- Unit: the Step 4 bats test, proven meaningful by the Step 5 mutation.
- Structural: `verify-mirrors.sh`, `cmp` on the unchecked settings pair, `jq`/`grep` assertions that the delegation table equals the channel files.
- Scope: `git diff`-based checks that FR-7 / NFR-3 files are untouched.
- Runtime: Step 7, best-effort; model and effort acceptance ultimately belong to the Claude Code runtime, not to static checks.
