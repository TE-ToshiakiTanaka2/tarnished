# Design: #261 Apply Codex CLI setup to workspace so `/review` can run in this repo

## Context

The `/review` Claude Code skill (`/workspace/.claude/skills/review/SKILL.md`) delegates code review to OpenAI Codex CLI (`codex exec`/`codex review`) and refuses to run if `codex` is not on `$PATH`. The boilerplate generator at `templates/codex/` already ships everything a downstream project needs to install and configure Codex (`AGENTS.md`, `.codex/config.toml`, Node.js LTS devcontainer feature, `setup_codex.sh`, the `# Codex CLI (track shared config only)` gitignore block, the `Bash(codex:*)` Claude permission). The tarnished workspace itself, however, has none of these applied — the templates are produced here but not consumed here, so `/review` cannot be exercised (dogfooded) against this repo.

Two artifacts in `templates/codex/` are also out of date relative to the more mature `git@github.com:TE-ToshiakiTanaka2/elsur.git` setup:

1. `templates/codex/.codex/config.toml` pins `model = "gpt-5.3-codex"` while elsur runs `model = "gpt-5.4"` with `model_reasoning_effort = "high"`.
2. `templates/codex/.devcontainer/scripts/setup_codex.sh` is a naive `npm install -g @openai/codex` that fails with EACCES on systems where Node was installed by `ghcr.io/anthropics/devcontainer-features/claude-code:1.0` (Node lands at `/usr/lib/node_modules`, which is root-owned). elsur's version probes the npm global prefix for write permission and falls back to `sudo -E npm install -g`. tarnished's devcontainer uses the same `claude-code:1.0` feature, so the elsur path is the only one that works here.

The relevant slices of the shared layer this issue acts on:

- `shared/architecture.md::Module Structure` — the workspace gains root-level `AGENTS.md` and `.codex/`, plus a new `setup_codex.sh` under `.devcontainer/scripts/`. The shell layered shape (`setup.sh → common.sh → plugin.sh`) is unaffected; this issue does not touch the plugin runtime.
- `shared/architecture.md::Cross-cutting Concerns` — the existing **Idempotency** invariant (`set -e` in `post.sh` requires non-fatal failures to `return 0`) governs how `setup_codex()` reports npm/network failures. The existing **Gitignore policy (#259)** already specifies the `# Codex CLI (track shared config only)` block and its marker; the workspace simply gains that block.
- `shared/api-spec.md::Setup / Plugin Surface` — `templates/codex/plugin.sh::plugin_post_copy` and `setup_plugins.sh` already document their contracts. This issue adds a new function, `setup_codex()` in `setup_codex.sh`, alongside them.

No new Rust types, no GitHub-API surface change, no config-schema migration on the `erd` side.

## Architecture Overview (delta)

The change is "apply boilerplate to ourselves" — pure file additions and line-level edits in workspace configuration, plus a 4-line model bump in `templates/codex/.codex/config.toml` so the boilerplate inherits the same modern default.

The Codex CLI does not run inside `setup.sh`. It runs inside the devcontainer post-create flow (`post.sh`), in the same place `setup_plugins.sh` runs. The new `setup_codex()` function is hooked in after `setup_plugins`, mirroring the integration point already documented in `templates/codex/plugin.sh::plugin_post_copy`.

Two new operational invariants enter the workspace:

1. **Sudo-aware npm install (NFR-1)** — `setup_codex.sh` must work under both writable-prefix (e.g., nvm-managed Node) and root-prefix (e.g., `claude-code:1.0` feature) configurations. The decision is made at install time by inspecting `npm root -g`. See `flowchart.md` for the decision tree.
2. **Non-blocking failure (NFR-2)** — Network failures, missing npm, or sudo refusal must `return 0` with a `[WARN]` log so `set -e` in `post.sh` does not abort the whole post-create. This mirrors `setup_plugins.sh`'s contract per `shared/api-spec.md::Setup / Plugin Surface`.

Template parity (FR-7) is in scope because the model line is the only thing diverging between `templates/codex/.codex/config.toml` and what we want the workspace to use. Splitting the bump into a separate issue would leave the boilerplate generating stale defaults for other projects; rolling it into this issue is one extra line.

## Module Structure (delta)

```
.                                            # workspace root
├── AGENTS.md                                # NEW — Codex review-agent definition for tarnished
├── .codex/
│   └── config.toml                          # NEW — gpt-5.4 + reasoning_effort=high + on-request + workspace-write
├── .devcontainer/
│   ├── devcontainer.json                    # MOD — add ghcr.io/devcontainers/features/node:1 (lts)
│   └── scripts/
│       ├── setup_codex.sh                   # NEW — sudo-aware npm install of @openai/codex
│       └── post.sh                          # MOD — append `# Codex CLI Setup` block invoking setup_codex
├── .claude/
│   └── settings.json                        # MOD — permissions.allow += "Bash(codex:*)"
├── .gitignore                               # MOD — append `# Codex CLI (track shared config only)` block
└── templates/
    └── codex/
        └── .codex/
            └── config.toml                  # MOD — model gpt-5.3-codex → gpt-5.4 + reasoning_effort=high
```

No deletions. No file moves. No new subdirectories beyond `/workspace/.codex/`. The plugin runtime (`templates/codex/plugin.sh`) is **not** modified — its existing copy/post-copy hooks already produce equivalent files when run against a downstream project; this issue just hand-applies the equivalent shape to the tarnished workspace itself.

## Interface Design (delta)

### Public Surface

| Surface | Form | Description |
| --- | --- | --- |
| `setup_codex()` | shell function in `.devcontainer/scripts/setup_codex.sh` | No args. Always returns `0`. Idempotent: skips install when `codex` is already on `$PATH`. Logs a `[WARN]` and returns `0` on missing npm, npm-install failure, or sudo-required-but-unwritable conditions. |
| post.sh integration | append-only block in `.devcontainer/scripts/post.sh` | After the existing `# Claude Code Plugin Setup` block, source `setup_codex.sh` and call `setup_codex`. Same `${SCRIPT_DIR}` pattern as the Claude block; no re-export of `SCRIPT_DIR`. |
| `Bash(codex:*)` permission | entry in `.claude/settings.json :: permissions.allow` | Allows Claude to invoke any `codex` subcommand without per-call approval. Required by `/review` because the skill streams a long prompt into `codex exec - --sandbox read-only`. |

### File Schemas (delta)

#### `/workspace/.codex/config.toml` (new)

```toml
# Project-level Codex CLI configuration
# See: https://developers.openai.com/codex/config-advanced/

# Always-latest model with high reasoning effort for review quality
model = "gpt-5.4"
model_reasoning_effort = "high"

# Approval policy: require approval for all actions
# Options: "untrusted", "on-request", "on-failure", "never"
approval_policy = "on-request"

# Sandbox mode: restrict file writes to workspace only
# Options: "workspace-write", "danger-full-access"
sandbox_mode = "workspace-write"
```

Fields are flat top-level TOML (no `[table]` headers required). All four keys are optional from Codex's perspective; we set them to lock in deterministic behavior across machines.

#### `/workspace/templates/codex/.codex/config.toml` (modified)

Same shape as above. The change is only the `model` line and the new `model_reasoning_effort` line. Approval and sandbox policies stay identical so existing downstream projects do not see a behavior shift on next regeneration.

#### `/workspace/AGENTS.md` (new) — section contract

The file MUST contain:

| Section | Purpose |
| --- | --- |
| `# Tarnished — Code Review Agent` | Title; identifies project + agent role |
| `## Review Responsibilities` → `### What to Check` | Generic 6-axis baseline (correctness, security, error handling, edge cases, code style, performance) |
| `## Project-Specific Checks` | tarnished-specific axes: plugin-system contract (`plugin_name` / `plugin_description` / `plugin_copy` / `plugin_post_copy`); shell rules from `.claude/rules/shell.md` (`#!/bin/bash`, `set -euo pipefail`, 4-space indent, `[[ ]]`, quoted expansions); `.gitignore` policy (block markers, idempotency); template directory contract (`templates/<flavor>/{AGENTS.md,plugin.sh,...}`); devcontainer post.sh integration (`source ${SCRIPT_DIR}/<setup>.sh` pattern + `set -e` non-fatal-return-0 invariant) |
| `## Output Format` | The `Critical / Major / Minor / Suggestions` markdown skeleton (matches `shared/api-spec.md` review output convention used by `/review`) |

Generic axes follow `templates/codex/AGENTS.md`'s wording verbatim so reviewers reading both files see the same baseline. Project-specific axes are tarnished-only and not pushed into the template (downstream projects should not inherit our plugin-system rules).

#### `/workspace/.gitignore` (modified) — block contract

Append the existing block from `shared/api-spec.md::Setup / Plugin Surface :: templates/codex/plugin.sh::plugin_post_copy — gitignore step (#259)`:

```
# Codex CLI (track shared config only)
.codex/*
!.codex/config.toml
```

Marker line is `# Codex CLI (track shared config only)` (line-anchored). Idempotency: only append if `grep -q "^# Codex CLI (track shared config only)$"` returns false.

#### `/workspace/.claude/settings.json` (modified) — JSON delta

Add exactly `"Bash(codex:*)"` to `permissions.allow`. Preserve existing entries (currently empty `[]`); preserve the entire `deny` list and `hooks` block byte-for-byte.

#### `/workspace/.devcontainer/devcontainer.json` (modified) — feature delta

Add inside `"features": { ... }`:

```json
"ghcr.io/devcontainers/features/node:1": {
    "version": "lts"
}
```

Place after the existing `claude-code:1.0` entry (alphabetical or "added-last" — both are fine; existing file is not strictly alphabetical).

#### `/workspace/.devcontainer/scripts/post.sh` (modified) — appended block

```bash
# -----------------------------------------------------------------------------
# Codex CLI Setup
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/setup_codex.sh" ]]; then
    source "${SCRIPT_DIR}/setup_codex.sh"
    setup_codex
fi
```

Insert immediately before the final `echo "Post-creation setup complete!"` line so the success message reflects the full setup. The local `SCRIPT_DIR` reassignment is redundant with the `# Claude Code Plugin Setup` block above; keep it anyway to make the block independently relocatable (and to mirror what `templates/codex/plugin.sh::plugin_post_copy` writes into downstream projects). Idempotency note: this block is hand-edited (not auto-appended by a function), so a future re-run of any setup helper must not re-append it — there is no marker `grep` here because the file lives in the workspace, not in a generator.

## Data Flow

Two flows added to the system, both detailed in `shared/sequence.md` after Phase 7:

1. **Devcontainer post-create (extended)** — `post.sh` invokes `setup_codex` after `setup_plugins`. `setup_codex` checks `command -v codex`; if absent, probes npm and `npm root -g`, decides on `sudo -E`, runs `npm install -g @openai/codex`, logs results, returns `0` regardless of outcome. (Decision tree: `flowchart.md`.)
2. **`/review` execution (already documented in shared/sequence.md as "Claude Code skill workflow")** — Claude Code invokes `codex exec - --sandbox read-only` (custom mode) or `codex review --base develop` (built-in). `Bash(codex:*)` permission allows the call without prompting. Codex reads `/workspace/.codex/config.toml` (model, sandbox, approval) and `/workspace/AGENTS.md` (review role). Output is captured by Claude and saved to `docs/review/#{issue}/review.md`.

## Error Handling

| Source | Failure mode | Handling |
| --- | --- | --- |
| `setup_codex.sh` | `npm` not found | Log `[WARN] npm not found. Skipping Codex CLI installation.` Return `0`. |
| `setup_codex.sh` | `npm root -g` returns empty | Log warning, attempt install without sudo. (Matches elsur's behavior — better to try than silently skip.) |
| `setup_codex.sh` | Install fails (network / npm) | Log `[WARN] Failed to install Codex CLI ...`. Return `0`. |
| `setup_codex.sh` | Sudo required but not available | `sudo -E npm install` exits non-zero; same `[WARN]` path as above. Return `0`. |
| `/review` (downstream) | `codex` not on `$PATH` after rebuild | The skill's "Prerequisites Check" already detects this and shows install instructions. Not a new error. |
| `/review` (downstream) | `codex` not authenticated | Codex itself prompts; skill surfaces the prompt. Not a new error. |

There is no "Codex required" hard failure introduced by this issue. The devcontainer continues to come up even if Codex install fails, and `/review` was already gated on Codex availability.

## Implementation Notes

- **Why hand-edit instead of running `templates/codex/plugin.sh` against `/workspace`** — `plugin.sh` assumes a fresh downstream target with empty/standard `.devcontainer/`, `.claude/settings.json`, and `.gitignore`. The tarnished workspace already has its own customized versions of all three. The `merge_*` helpers in `scripts/lib/common.sh` handle JSON merge for downstream targets but they are designed to be invoked from `setup.sh`, not against the host repo. Hand-editing each of the 5 modified files keeps existing customizations intact and is simpler than wiring a new "self-apply" mode into setup.sh.
- **Why bump the template model in this issue (FR-7)** — Splitting the bump into a follow-up issue would leave the boilerplate generating stale defaults for any project created between this issue's merge and the follow-up. The bump is 4 characters (`5.3-codex` → `5.4`) plus one new line (`model_reasoning_effort`), which is too small to justify its own issue.
- **Why `model_reasoning_effort = "high"`** — Code review benefits substantially from deeper reasoning (matching elsur's choice). The token cost is paid only when `/review` runs, which is opt-in per branch.
- **Why no `/workspace/.codex/auth.json` is shipped** — Codex's auth flow writes to `~/.config/codex/` (or wherever the CLI determines), not the project `.codex/`. Authentication is per-developer; we never commit it. The `.codex/*` + `!.codex/config.toml` whitelist guards this even if the path assumption ever changes.
- **Backwards compatibility** — Existing developers who already rebuilt the devcontainer before this change have neither Node nor Codex installed. After this change, a devcontainer rebuild adds both. Developers who never rebuild still see no change; `/review` simply continues to refuse with the existing "Codex CLI is required" message.
- **No tests added on the Rust side** — This issue does not touch the `erd` crate. Verification is operational: rebuild devcontainer, confirm `codex --version`, run `/review` against a small diff, confirm Codex output is captured. Workflow doc covers this.
