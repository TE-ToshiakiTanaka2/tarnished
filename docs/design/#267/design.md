# Design: #267 chore(ci): migrate GitHub Actions off Node.js 20 before 2026-06-02 forced cutover

## Context

(Self-contained slice of `../shared/architecture.md` and `../shared/api-spec.md` — intentional duplication so this delta reads on its own.)

tarnished ships **two distinct distribution channels** for GitHub Actions workflows:

1. **Root `.github/workflows/*` (6 files)** — tarnished's own CI **and** the canonical reusable-workflow source for downstream consumers. Files: `auto-tag.yml`, `pr-project-status.yml`, `project-integration.yml`, `project-label-routing.yml`, `release-erd.yml`, `rust-quality-check.yml`. The first three are the freyja-style reusable workflows invoked via `uses: TE-ToshiakiTanaka2/tarnished/.github/workflows/<name>.yml@develop`.

2. **`templates/github-actions/*` and `templates/languages/*/...yml`** — files that `setup.sh` copies *verbatim* into a downstream project at scaffold time. Independent of the root workflows; lives in the `setup.sh` plugin pipeline (see `shared/architecture.md` :: "Module Structure" / "Layer Boundaries").

Issue #267's scope is exactly **channel (1)** — the 6 root workflow files. Channel (2) is identified for follow-up (`research.md` :: Question 7) but explicitly out of scope here, matching the issue's inventory section.

The deprecation timeline (`research.md` :: Question 1):

- **2026-06-02** — Node.js 24 becomes the default; Node-20 actions silently switched to Node 24 by the runner.
- **2026-09-16** (≈) — Node 20 fully removed; Node-20-pinned actions hard-fail.

Today (2026-04-30), the deprecation surfaces as an annotation on every workflow run in this repo and on every freyja CI run that consumes our reusable workflows.

## Architecture Overview (delta)

This is a **dependency-version refresh** with no logic changes. We bump five third-party JavaScript actions across six workflow files to their earliest Node-24-native major versions.

The migration follows the issue body's Option 1 (version bump) directly, skipping Option 2/3 (env-var pre-flight) — see `research.md` :: Question 5 for rationale. Net effect:

- Tarnished's own CI (push to `develop`, PRs targeting `develop`, issue events, release dispatches) loses the Node-20 deprecation annotation.
- Downstream consumers calling our reusable workflows (`auto-tag.yml`, `pr-project-status.yml`, `project-integration.yml`) lose the annotation transparently — `workflow_call` executes the callee's pins, so freyja and any other consumer get the upgrade with zero downstream change.

No new layer, module, type, or surface is introduced. The cumulative shared documents (`shared/architecture.md`, `shared/api-spec.md`, `shared/data-model.md`) are touched only to record the runtime-pin change in the existing "Cross-cutting Concerns" / migrations table; `shared/class.md` and the existing flow sequences are unchanged.

## Module Structure (delta)

No directories added or removed. Modified files are six existing YAML files:

```
.github/workflows/
├── auto-tag.yml                # checkout, cache, github-script
├── pr-project-status.yml       # checkout, cache, github-script
├── project-integration.yml     # checkout, cache, github-script
├── project-label-routing.yml   # checkout, cache
├── release-erd.yml             # checkout, cache, upload-artifact, action-gh-release
└── rust-quality-check.yml      # checkout, cache
```

## Interface Design (delta)

### Action version pins (the change set)

Authoritative target table — each row is a pure `@vN` → `@vM` substitution across the workflow files listed in "Occurrences":

| Action | From | To | Action `runs.using` after | Occurrences | Files |
| --- | --- | --- | --- | --- | --- |
| `actions/checkout` | `@v4` | `@v5` | `node24` | 17 | all 6 workflow files |
| `actions/cache` | `@v4` | `@v5` | `node24` | 12 | all 6 workflow files |
| `actions/github-script` | `@v7` | `@v8` | `node24` | 6 | `auto-tag.yml`, `pr-project-status.yml`, `project-integration.yml` |
| `actions/upload-artifact` | `@v4` | `@v6` | `node24` | 1 | `release-erd.yml` |
| `softprops/action-gh-release` | `@v2` | `@v3` | `node24` | 1 | `release-erd.yml` |

**Total**: 37 line edits across 6 files. (Issue body said 33 — recount on freshly inventoried HEAD — see `workflow.md` :: Step 1 for the exact tally and verification.)

Out of scope for the version bump (composite actions, no Node runtime):

- `dtolnay/rust-toolchain@stable` — composite, used in 4 of 6 files.
- `taiki-e/install-action@cargo-llvm-cov` — composite, `release-erd.yml` only.

### `runs.using` selection rule

For each action we pin to the **earliest major version whose `action.yml` declares `runs.using: node24`** (verified per-action — `research.md` :: Question 2). Rationale: smallest behavioral delta beyond the runtime upgrade. Specifically:

- `actions/checkout@v5` over `@v6` — v6 changes credential persistence (`research.md` :: Question 3).
- `actions/github-script@v8` over `@v9` — v9 makes `@actions/github` ESM-only and reserves `getOctokit` (`research.md` :: Question 4); we don't trip either, but v8 is the strictly smaller change.
- `actions/upload-artifact@v6` over `@v7` — v7 adds `archive: false` direct upload, which we don't use.

### Type Definitions (delta)

None. No new entities, configs, or schemas. The tarnished data model and Rust crate are unchanged.

### API surface (delta)

None. Inputs/outputs of every workflow stay byte-equivalent:

- `auto-tag.yml`'s `workflow_call.inputs` (`config-path`, `erd-version`) and `secrets` — unchanged.
- `pr-project-status.yml`'s `workflow_call.inputs` (`pr-number`, `config-path`, `erd-version`) and `secrets.PROJECT_TOKEN` — unchanged.
- `project-integration.yml`'s `workflow_call.inputs` (`issue-number`, `config-path`, `erd-version`) and `secrets.PROJECT_TOKEN` — unchanged.
- `project-label-routing.yml`'s `workflow_call.inputs` (`issue-number`, `label-name`, `config-path`, `erd-version`) — unchanged.
- `release-erd.yml`'s `workflow_dispatch.inputs.tag` — unchanged.
- All `permissions:` blocks — unchanged.

`shared/api-spec.md` :: "Workflow Triggers" therefore needs only an additive note (action runtime pinned to Node 24), not a row change.

## Data Flow

No control-flow change in any workflow. All six workflows execute the same step graph; only the Docker image used to host the JavaScript action body switches from `node20` to `node24`.

For the three reusable workflows (`auto-tag.yml`, `pr-project-status.yml`, `project-integration.yml`), the consumer's `workflow_call` invocation transparently picks up the new runtime — no downstream change is required (`research.md` :: Question 6).

## Error Handling

No new error paths. The only conceivable post-bump failure modes:

1. **`actions/cache@v5` cache miss** — if cache key derivation changed. Mitigation: keys are derived from `hashFiles('**/Cargo.lock')`, which is independent of cache action version. Verified equivalent across v4/v5.
2. **`softprops/action-gh-release@v3` input rejection** — if v3 dropped any input we set. Mitigation: verified all five inputs we use (`tag_name`, `name`, `prerelease`, `generate_release_notes`, `files`) are still present in v3 (`research.md` :: Question 2). Compatible.
3. **`actions/github-script@v8` API drift** — the six script bodies use `github.rest.issues.createComment(...)` exclusively. v8 is documented to have no API change vs v7.
4. **Self-hosted runner too old** — only relevant if a downstream consumer runs on a self-hosted runner older than `2.327.1`. Tarnished and freyja both run on `ubuntu-latest` (GitHub-hosted, current). Mitigation: documented in commit message and PR body so downstream consumers can self-diagnose.

Roll-back path: the change is six files of pure version pin substitutions. A single-commit revert restores prior state with no data implications. Cache entries written by v4 are readable by v5 and vice versa.

## Implementation Notes

- **Single-PR delivery**. The 37 substitutions are atomic; staging would not yield a useful intermediate state. Splitting per-action would amplify CI runs (each PR re-runs the same suite) without isolating regressions because the bumps are independent.
- **No "FORCE_JAVASCRIPT_ACTIONS_TO_NODE24" workflow env**. The pre-flight verification path (Issue Option 2) is skipped — running the new majors directly through tarnished's own CI on the PR is functionally equivalent and simpler to review (`research.md` :: Question 5).
- **Verification leverages existing CI signals**. tarnished's own push of this branch fires `rust-quality-check.yml`; opening the PR fires `pr-project-status.yml`; the PR being merged will later fire `auto-tag.yml`. That's three of six files exercised end-to-end before merge. `release-erd.yml` is `workflow_dispatch`-only — verified manually post-merge by triggering a `-rc` release. `project-integration.yml` and `project-label-routing.yml` fire on issue events — already exercised by issue #267 itself (the project-integration check ran on issue creation, see issue comment).
- **Acceptance criterion "no new flakiness"** is hard to prove proactively; it's verified by observing two clean runs of each affected workflow post-merge and the absence of the deprecation annotation.
- **No coordination needed with freyja**. Once merged to `develop`, freyja's next CI run automatically picks up the new pins via `workflow_call`. No downstream change set, no version bump on the freyja side.
- **Templates remain on Node-20 pins** (out of scope per issue body). Recommendation in `research.md` :: Question 7 is to open a follow-up issue tracking the same upgrade in `templates/github-actions/*` and the language workflow templates.

## Acceptance criteria mapping

Mapping the issue's acceptance criteria to the implementation:

| Criterion (from issue) | How verified |
| --- | --- |
| All workflow files no longer trigger the Node.js 20 deprecation annotation on a fresh CI run | Open the PR; confirm no annotation on the `rust-quality-check.yml` and `pr-project-status.yml` jobs spawned by the PR open. Post-merge, confirm on the `auto-tag.yml` run that fires from the merge commit. |
| `rust-quality-check.yml` matrix continues to pass on `develop` | PR run + post-merge `develop` run both green. |
| Reusable workflows continue to function for downstream consumers (freyja calls to `auto-tag.yml`, `pr-project-status.yml`, `project-integration.yml`) | Post-merge, freyja's next push triggers its consumption of these workflows; confirm green run. No freyja-side change required. |
| `release-erd.yml` still publishes artifacts and creates the GitHub Release with `softprops/action-gh-release@v3` | Post-merge, manually `workflow_dispatch` `release-erd.yml` against a test `-rc` tag; confirm the binary, sha256, and Release entry are produced. |
| No new flakiness or behavioral change | Two consecutive clean runs of each affected workflow post-merge, plus a clean freyja CI run. |
