# Orchestrator Review: #325 design artifacts

Reviewed against the issue's Requirements (FR-1..FR-13, NFR-1..NFR-6, Constraints) at design time, before the design commit. Authoring was delegated to the `designer` subagent; this review ran inline in the orchestrator session.

## Rounds

- Round 0: full review of `design.md`, `api-spec.md`, `workflow.md`, `flowchart.md`, `research.md`, `shared/research/mise.md`, and the regenerated `shared/*` snapshot.
- Re-dispatches used: 0 of 2. No blocking finding.

## Verification performed

- `scripts/lib/common.sh::merge_claude_settings` deep-merges `$base * $overlay` before overriding `permissions` / `hooks`, so D18 ("no code change, add tests") holds for FR-7; `merge_claude_settings_hooks` also starts from `$base * {...}`.
- `templates/core/plugin.sh` and `templates/agent-workflows/plugin.sh` exist, so the Module Structure's core edits are addressable.
- `setup.sh` accepts `-y|--yes` (line ~908), which the CI workflow design relies on.
- No `## Issue #N` section was appended to any `docs/design/shared/*.md` (snapshot discipline kept).
- `shared/architecture.md` now states the install contract and drops the "Dockerfile.dev is minimal deps for devcontainer features" claim.

## Requirement coverage

Every FR and NFR maps to a concrete design element in `design.md` "Requirement traceability"; spot checks on FR-1 (D17 merge change is required for the `has("features") == false` acceptance), FR-3 (block order proof under current plugin load order), FR-4 (per-version npm prefix, no sudo, `setup_sudo_path` and the `sh` symlink removed), FR-5 (user-entry protection semantics), FR-8 (settings-driven fallback, no `-y`), FR-12 (11-entry matrix incl. the `workspace` dogfood build) all hold.

## Findings

### Blocking

None.

### Worth noting (carried into the implementation dispatch)

1. **NFR-2 wording in the issue was wrong, the design is right.** `post.sh` is developer-owned and excluded from manifest eligibility, so new `post.sh` blocks cannot ship through `--upgrade`; only the helper scripts do. The issue body is corrected to say so (orchestrator edit at design time); the design's migration steps in `docs/maintenance.md` cover the wiring.
2. **Security constants must be re-sourced at implementation.** `ARG MISE_MINISIGN_PUBKEY` and `ARG GH_KEYRING_FINGERPRINT` carry concrete values in the design and in `shared/research/mise.md`. The executor must fetch both from the official pages (mise install docs; GitHub CLI Linux install docs) at implementation time, confirm they match, and cite the source URL in a Dockerfile comment.
3. **python `[env]` semantics differ from the former Dockerfile `ENV`.** Values declared in `mise.toml [env]` apply to processes started through shims or an activated shell, not to a process that execs the interpreter by absolute path (e.g. an editor extension). The impact is limited to `PYTHONDONTWRITEBYTECODE` / `PYTHONUNBUFFERED` (`.pyc` files, buffering); accepted. `docs/setup.md` should state it in one sentence.
4. **Pre-existing Mermaid fixes in `shared/sequence.md`.** The designer repaired nine pre-#325 diagrams that failed to parse because of semicolons in message text. Accepted as part of the snapshot regeneration; noted here so the diff is not mistaken for scope creep.
5. **CI post-create smoke on `core`** runs the whole `post.sh` (git/SSH setup with `CI=1`, asset refresh attempting an upstream fetch). Expected to be noisy but non-fatal; if it proves flaky, restrict the smoke to sourcing `setup_mise.sh` + `setup_claude.sh` directly.

## Decisions accepted as made

D1 (mise python + uv with `UV_PYTHON`), D2 (no generated `.tool-versions`), D3 (minisign-verified release binary), D5 (per-version npm prefix), D9 (`post_sh_add_block` with before-markers), D11 (`build-essential` in core), D13 (`USER vscode`), D17 (`features` as ordinary key), D20 (unpinned CLIs with env override), D22 (extra CI entries). All are consistent with the user's settled decisions and the issue's Constraints.
