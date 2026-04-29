# Workflow: #261 Apply Codex CLI setup to workspace

## Implementation Steps

### Step 1: Author `/workspace/.codex/config.toml`

- **Action**: Create a new file at `/workspace/.codex/config.toml` with the four keys defined in `design.md::Interface Design (delta) :: /workspace/.codex/config.toml (new)`. Verbatim model line: `model = "gpt-5.4"`. Verbatim reasoning line: `model_reasoning_effort = "high"`.
- **Files**: `/workspace/.codex/config.toml` (new)
- **Depends on**: nothing
- **Done when**: file exists, `cat .codex/config.toml | head -1` shows the comment header, `grep -E '^model = "gpt-5.4"$' .codex/config.toml` succeeds.

### Step 2: Author `/workspace/AGENTS.md`

- **Action**: Create `/workspace/AGENTS.md` following the section contract in `design.md::Interface Design (delta) :: /workspace/AGENTS.md (new) — section contract`. Reuse `templates/codex/AGENTS.md`'s wording for the generic 6-axis baseline, then add the tarnished-specific `## Project-Specific Checks` section covering plugin-system contract, shell rules, gitignore policy, template directory contract, and post.sh integration invariants.
- **Files**: `/workspace/AGENTS.md` (new)
- **Depends on**: nothing (parallel-safe with Step 1)
- **Done when**: file exists, `grep -E '^# Tarnished — Code Review Agent$' AGENTS.md` succeeds, `grep -E '^## Project-Specific Checks$' AGENTS.md` succeeds, the file mentions all four invariants by name (plugin contract, shell rules, gitignore policy, post.sh integration).

### Step 3: Port `setup_codex.sh` from elsur

- **Action**: Create `/workspace/.devcontainer/scripts/setup_codex.sh`. Body is a verbatim port of elsur's version (`gh api repos/TE-ToshiakiTanaka2/elsur/contents/.devcontainer/scripts/setup_codex.sh`), defining a single `setup_codex()` function that: (a) returns `0` and warns if `npm` missing; (b) returns `0` if `codex` already on `$PATH`; (c) checks `npm root -g`, decides `sudo -E` based on writability of the prefix dir (or its parent if missing); (d) runs `npm install -g @openai/codex`; (e) returns `0` regardless of install outcome with appropriate `[WARN]` log on failure. The decision tree is captured in `flowchart.md`.
- **Files**: `/workspace/.devcontainer/scripts/setup_codex.sh` (new, executable)
- **Depends on**: nothing (parallel-safe with Steps 1, 2)
- **Done when**: file exists, `chmod +x` applied, `bash -n .devcontainer/scripts/setup_codex.sh` (syntax check) succeeds, `shellcheck .devcontainer/scripts/setup_codex.sh` returns no errors.

### Step 4: Wire Node.js feature into devcontainer.json

- **Action**: Edit `/workspace/.devcontainer/devcontainer.json` to add `"ghcr.io/devcontainers/features/node:1": { "version": "lts" }` inside the `"features"` block. Place after the existing `claude-code:1.0` entry. Preserve all other features, customizations, and the trailing `postCreateCommand`. Validate JSON.
- **Files**: `/workspace/.devcontainer/devcontainer.json` (modified)
- **Depends on**: nothing (parallel-safe)
- **Done when**: `python3 -m json.tool .devcontainer/devcontainer.json > /dev/null` succeeds (note: the file uses C-style `//` comments; use `jq` with `--seq` or pre-strip comments — see "Test Strategy"); `grep -F 'ghcr.io/devcontainers/features/node:1' .devcontainer/devcontainer.json` succeeds.

### Step 5: Hook `setup_codex` into post.sh

- **Action**: Append the `# Codex CLI Setup` block to `/workspace/.devcontainer/scripts/post.sh` immediately before the final `echo "Post-creation setup complete!"` line. Verbatim block per `design.md::Interface Design (delta) :: post.sh (modified) — appended block`. Preserve the existing `# Claude Code Plugin Setup` block above it.
- **Files**: `/workspace/.devcontainer/scripts/post.sh` (modified)
- **Depends on**: Step 3 (the file that gets sourced must exist)
- **Done when**: `grep -E '^# Codex CLI Setup$' .devcontainer/scripts/post.sh` returns a single match, `bash -n .devcontainer/scripts/post.sh` succeeds, the final `echo "Post-creation setup complete!"` line is still last.

### Step 6: Add `Bash(codex:*)` to Claude permissions

- **Action**: Edit `/workspace/.claude/settings.json` to add `"Bash(codex:*)"` as the sole entry of `permissions.allow`. Preserve the entire existing `permissions.deny` array byte-for-byte and the entire `hooks` object byte-for-byte.
- **Files**: `/workspace/.claude/settings.json` (modified)
- **Depends on**: nothing (parallel-safe)
- **Done when**: `jq '.permissions.allow' .claude/settings.json` returns `["Bash(codex:*)"]`, `jq '.permissions.deny | length' .claude/settings.json` returns `6` (unchanged from before), `jq '.hooks' .claude/settings.json` is structurally unchanged.

### Step 7: Append codex whitelist block to `.gitignore`

- **Action**: Append the `# Codex CLI (track shared config only)` block (3 lines: marker + `.codex/*` + `!.codex/config.toml`) to `/workspace/.gitignore`. Idempotency-check first: if `grep -q "^# Codex CLI (track shared config only)$" .gitignore` returns true, do nothing.
- **Files**: `/workspace/.gitignore` (modified)
- **Depends on**: nothing (parallel-safe with Steps 1–6)
- **Done when**: `grep -cE '^# Codex CLI \(track shared config only\)$' .gitignore` returns exactly `1`, `git check-ignore .codex/auth.json` exits 0 (file would be ignored if present), `git check-ignore .codex/config.toml` exits 1 (file is NOT ignored).

### Step 8: Update `templates/codex/.codex/config.toml` model

- **Action**: Edit `/workspace/templates/codex/.codex/config.toml` to change `model = "gpt-5.3-codex"` → `model = "gpt-5.4"` and add a new line `model_reasoning_effort = "high"` immediately below it (matching the structure of `/workspace/.codex/config.toml` from Step 1). Update the comment line above `model =` to say "Always-latest model with high reasoning effort for review quality" (replacing "Use the latest Codex model").
- **Files**: `/workspace/templates/codex/.codex/config.toml` (modified)
- **Depends on**: nothing (parallel-safe with Steps 1–7)
- **Done when**: `grep -E '^model = "gpt-5.4"$' templates/codex/.codex/config.toml` succeeds and `grep -E '^model_reasoning_effort = "high"$' templates/codex/.codex/config.toml` succeeds.

### Step 9: Verification — devcontainer rebuild + Codex smoke

- **Action**: Rebuild the devcontainer (`Dev Containers: Rebuild Container` in VS Code, or `devcontainer rebuild` CLI). Confirm post.sh ran the Codex setup. Then verify Codex itself is callable.
- **Files**: none (operational)
- **Depends on**: Steps 1, 4, 5
- **Done when**: `command -v codex` returns a path, `codex --version` prints a version (no error), the post.sh log contains `Setting up OpenAI Codex CLI...` and ends with `Codex CLI setup complete.`, and `cat /workspace/AGENTS.md` is readable from inside the container.

### Step 10: Verification — `/review` end-to-end smoke

- **Action**: Run `/review` against the diff produced by Steps 1–8 themselves (this branch vs. `develop`). Confirm Claude reaches the Codex CLI, captures its output, and offers fixes.
- **Files**: `docs/review/#261/review.md` is produced (per `/review`'s save step) — but do not commit it as part of this issue's design phase. It belongs to the implement/review phase.
- **Depends on**: Step 9
- **Done when**: `/review` does not error out at the "Prerequisites Check" step, Codex returns a structured review (Critical / Warnings / Suggestions / Positive sections), and the review file is saved under `docs/review/#261/`.

## Task Dependencies

- **Steps 1–4, 6, 7, 8 are mutually independent** and can be done in parallel.
- **Step 5 depends on Step 3** — `post.sh` sources `setup_codex.sh`; the source target must exist.
- **Step 9 depends on Steps 1, 4, 5** — Codex needs `/workspace/.codex/config.toml` (Step 1), Node feature (Step 4), and the post.sh hook (Step 5) all in place to actually install on rebuild.
- **Step 10 depends on Step 9** — cannot smoke-test `/review` without `codex` on `$PATH`.

A natural batching for `/implement`: do Steps 1–8 in a single edit pass (they touch 8 distinct files with no internal coupling beyond the source-target relationship between 3 and 5), then commit, then run Steps 9 and 10 as the final verification.

## Test Strategy

### Unit-level (no test framework, just shell checks)

- `bash -n` syntax check on `setup_codex.sh` and the modified `post.sh`.
- `shellcheck` on `setup_codex.sh` (Step 3 done-criterion).
- `jq`-based assertions on `.claude/settings.json` (Step 6 done-criteria) — this also serves as a regression check that we did not perturb `permissions.deny` or `hooks`.
- `grep -c` on `.gitignore` (Step 7 done-criterion) to confirm exactly one marker.
- For `devcontainer.json` (Step 4): the file uses C-style `//` comments which strict JSON parsers reject. Use `npx --yes json5 < .devcontainer/devcontainer.json > /dev/null` (or `jq` after `sed -e 's://.*$::g'`) for syntax validation. Manually visual-check the diff to confirm the Node feature was added in the right block.

### Integration-level (operational, not automated)

- **Devcontainer rebuild** — Step 9. The full chain runs: `claude-code:1.0` feature installs Node at `/usr/lib/node_modules`, `setup_codex.sh` detects the root-owned prefix and uses `sudo -E npm install -g @openai/codex`. Watch the log for the sudo path being taken.
- **`/review` smoke** — Step 10. Validates that Claude → `codex exec` → output capture works end-to-end with the new permission entry and the new `.codex/config.toml`.

### Edge cases to cover (during Step 9 verification)

- **Already-installed codex** — re-run `setup_codex` manually after Step 9; confirm it logs "Codex CLI already installed: <version>" and skips reinstall (idempotency, NFR-2 secondary).
- **Network failure during install** — not easily simulated, but verify the failure path by reading the script: `npm install` exit code propagates, `[WARN] Failed to install Codex CLI` is logged, function returns `0`.
- **Sudo refusal** — also not easily simulated in normal operation, but confirm the script does NOT use `set -e` in a way that aborts the function on `sudo -E npm install` failure. Visual code review of the ported script.
- **`.codex/auth.json` accidentally committed** — `git check-ignore .codex/auth.json` (Step 7 done-criterion) is the regression guard.
- **Existing developers who don't rebuild** — Step 9 documents that `/review` continues to refuse cleanly with the pre-existing "Codex CLI is required" message; no behavior change for them.

### Out of scope for this issue

- Automated CI for `/review` itself — `/review` is human-triggered.
- Pinning Codex CLI version — we install the latest published `@openai/codex` so we always get the most recent client. If pinning becomes desirable, that is a separate issue.
- A `setup.sh --self-apply` mode that re-runs `templates/codex/plugin.sh` against the workspace — see `design.md::Implementation Notes :: Why hand-edit instead of running templates/codex/plugin.sh against /workspace`.
