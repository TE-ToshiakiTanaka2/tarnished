# Review: #325 Replace devcontainer features with mise runtimes, Dockerfile OS packages, and post.sh AI CLI installs

```yaml
repository: TE-ToshiakiTanaka2/tarnished
issue_number: 325
review_status: complete
reviewed_head: 6db2ba49dd46a311bf32367bb0251a849096e1bd
verified_head: 3f4c8cac40deb252d7eeef9a63e72bf384927f99
base_ref: develop
base_commit: 423b0e53bd50a11c12a8c50739d6769658ac1291
merge_base: 423b0e53bd50a11c12a8c50739d6769658ac1291
issue_body_sha256: 453b11eae4d6bf9895e07ba2eb77002408394835411a7cc57989124e5100be98
```

- **Branch**: `feature/TE-ToshiakiTanaka2/#325/replace-devcontainer-features-with-mise-runtimes`
- **Base**: `develop` @ `423b0e5` (merge base `423b0e5`)
- **Scope**: Large — 62 implementation files, +3315 / −747 (excluding `docs/design/**`); all nine criteria plus architecture adherence
- **Timestamp**: 2026-11-01T15:45:09Z
- **Reviewer**: Claude-native `code-reviewer` subagent (**fallback review**). Resolution ladder: no explicit flag; `.tarnished/agent-profile.json` carries unrendered `{{...}}` placeholders (treated as absent); Codex CLI 0.163.0 is installed but `codex login status` reports "Not logged in", so under `/flow` the run fell through to the Claude-native reviewer. Model: inherited agent definition (`code-reviewer.md`, session model claude-fable-5-1); reasoning effort: default.
- **Run context**: `/flow` (review stage), executed from worktree `/tmp/tarnished-325`. Working tree clean at review time; the committed diff is the full review input.
- **Environment limitation**: `docker` unavailable in the review environment — image build, the `bash -c` / `bash -ic` version checks, the post-create `claude --version`, arm64, and `scripts/ci/smoke-runtimes.sh` were reviewed statically; `.github/workflows/scaffold-build.yml` is the automated check on the PR.

## Review Output (verbatim)

## Review Summary

**Overall**: APPROVE

Scope verified: full diff `423b0e5..6db2ba4` (62 implementation files) against `/tmp/tarnished-325/docs/design/#325/{design,api-spec,workflow}.md` and the Requirements section of issue #325. Checks run read-only in the worktree:

- `bash scripts/verify-mirrors.sh` — all pairs byte-identical, including the four new helper pairs and `docker/Dockerfile.dev` ≡ core template.
- bats: `common_mise`, `common_postsh`, `common_json`, `setup_plugins`, `setup_cli_helpers`, `setup_mise_scaffold`, `plugin_idempotency`, `setup_service_selection`, `setup_upgrade`, `setup_create_manifest`, `setup_zed` (257/257 pass) plus `common_zed`, `manifest`, `setup_maintenance` (102/102 pass).
- Live check of the mise release: `SHASUMS256.txt` for v2026.10.25 lists `<sha>  ./mise-v2026.10.25-linux-{x64,arm64}`, matching the `grep " ./${asset}\$"` line in the Dockerfile; the minisign key in `ARG MISE_MINISIGN_PUBKEY` is identical to `jdx/mise:minisign.pub`.
- GitHub Actions tags `actions/checkout@v5`, `docker/setup-buildx-action@v4`, `docker/build-push-action@v7` all exist.

Limitation: `docker` is unavailable here, so the image build, the FR-2/FR-3/FR-5 acceptance commands (`node --version` in `bash -c` and `bash -ic`, `claude --version` after post-create), the arm64 path, and `scripts/ci/smoke-runtimes.sh` were reviewed statically only. `shellcheck` is also not installed. The CI workflow in this branch is the automated check for those; the verdict assumes it goes green on the PR.

### Critical (must fix)
No findings.

### Major (must fix before PR)
No findings.

### Minor (fix when cheap)
- `setup.sh:3040` — The add-module epilogue prints "New runtimes were added to mise.toml. Install them with `mise install`" unconditionally. For a second module of an already-declared language, or a latex module (no mise entry), nothing was added and the hint is misleading. Gate it on whether any `mise_toml_ensure` call actually wrote (e.g. have the helper set a flag, or check `mise.toml` mtime/hash before and after the post-copy pass).
- `.github/workflows/scaffold-build.yml:64-66` and `tests/setup_mise_scaffold.bats:159` — The design/workflow table specifies the celery entry as `--celery` alone ("celery auto-enables python + redis"); the branch passes `--lang python --celery` with an inline comment that `--celery` alone does not add Python non-interactively. The deviation is reasonable but undocumented in the design, and the bats test is still titled "auto-enabled python and redis" while explicitly passing `--lang python`. Either amend `docs/design/#325/workflow.md` and the test title, or make `--celery -y` imply python so the design holds.

### Suggestions (nice to have)
- `scripts/lib/common.sh:1023` — `post_sh_add_block` unconditionally runs `body="$(cat)"`. A future caller that forgets the heredoc hangs on an interactive terminal with no diagnostic. A cheap guard (`if [[ -t 0 ]]; then print_error "...body on stdin"; return 1; fi`) would make the contract self-enforcing.
- `templates/claude/.devcontainer/scripts/setup_plugins.sh:169` — `claude plugin install <id> --scope project` writes to `.claude/settings.json`, which is refresh-managed. If Claude Code re-serialises the file (key order, indentation), the next `refresh-assets.sh` run sees differing bytes, creates a backup and replaces it. This is the same behaviour the old `-s project` had, so it is not a regression, but worth a sentence in `docs/setup.md` or a follow-up to consider `--scope user` for the fallback install.
- `templates/claude/.devcontainer/scripts/setup_plugins.sh:132-133` — The `claude plugin list --json | jq -r '.[].id'` shape is unverifiable without the CLI (the previous script never parsed JSON). The failure mode is benign (installed set treated as empty, install retried idempotently), which is the right design; a one-line comment recording the expected JSON shape and CLI version would help the next maintainer when the CLI output changes.
- `.github/workflows/scaffold-build.yml` — An 11-entry docker-build matrix on every PR push could use a `concurrency` group (`${{ github.workflow }}-${{ github.ref }}`, `cancel-in-progress: true`) to avoid stacking builds.

### Positive
- `mise_toml_ensure` (`scripts/lib/common.sh:841-964`) is a careful TOML-aware insert without a parser: it correctly ignores `[[array]]` tables, stops `last` at a `[tools.x]` sub-table so the new key does not land inside it, treats quoted keys / table form / top-level dotted keys as "present", keeps CRLF, and writes atomically via `mktemp` + `mv`. The bats suite exercises every one of those branches, including the commented-out `# node = "20"` edge case named in the workflow.
- `post_sh_add_block` with the "before" lists in `templates/core/plugin.sh`, `templates/codex/plugin.sh`, `templates/claude/plugin.sh` makes the FR-3 order independent of plugin load order, and `common_postsh.bats` proves the full core → claude → codex sequence and the "developer already moved a block" no-reorder case.
- The Dockerfile honours NFR-4 end to end: minisign over SHASUMS then `sha256sum -c` for mise, fingerprint-checked `signed-by` keyring for gh, everything above `SHELL` kept POSIX (asserted by `_assert_install_contract`), no `latest`, no `sh` symlink, `USER vscode` at the end, and the `github_token` BuildKit secret scoped to a single `RUN`.
- `install_npm_global_cli` probes with `<cmd> --version` rather than `command -v` (D7), refuses a non-writable prefix instead of escalating, and `setup_cli_helpers.bats` mocks `sudo` and asserts it is never called on any path.
- Requirement traceability is complete against the issue: FR-1..FR-13 and NFR-1..NFR-6 each have a code artifact and a test or CI check; the design's correction to NFR-2 (post.sh blocks arrive via the documented migration, not `--upgrade`) is consistent with the issue's own Constraints and is covered by `setup_upgrade.bats`. The workspace dogfood files, `devcontainer-lock.json` deletion, `verify-mirrors.sh` pairs (going beyond the issue by also pinning `Dockerfile.dev`), `asset-parity.yml` path filter, and the AGENTS.md §1/§4/§5/§7 updates are all present.

## Orchestrator Triage

| # | Severity | Finding | Disposition |
| --- | --- | --- | --- |
| 1 | Minor | add-module `mise install` hint printed unconditionally | Fix (cheap): gate on whether `mise_toml_ensure` wrote anything |
| 2 | Minor | celery CI entry / test title diverge from the design's `--celery`-only wording | Fix (cheap): amend `docs/design/#325/workflow.md` and the test title; keep `--lang python --celery` |
| S1 | Suggestion | `post_sh_add_block` stdin guard | Apply (cheap) |
| S2 | Suggestion | `--scope project` interaction with refresh-managed settings | Apply: one sentence in `docs/setup.md` |
| S3 | Suggestion | document expected `claude plugin list --json` shape | Apply: comment in `setup_plugins.sh` (both mirror copies) |
| S4 | Suggestion | `concurrency` group on `scaffold-build.yml` | Apply (cheap) |

No Critical or Major findings; nothing deferred.

## Second independent review — Codex CLI

- **Reviewer**: Codex CLI 0.163.0 (model: gpt-6-astra, reasoning effort: high) — both values resolved from `.codex/config.toml` in the issue worktree and passed explicitly (`-c model`, `-c model_reasoning_effort`, `--strict-config`); a minimal runtime check confirmed the backend accepts them. Requested by the user after authenticating Codex (`codex login status`: "Logged in using ChatGPT"); the Claude-native review above was already complete at that point.
- **Reviewed head**: `59b6fa049bd95b1c04d81edad0cf93b3fe0ad00e` (the Claude review's findings already applied in `59b6fa0`); base `develop` @ `423b0e53bd50a11c12a8c50739d6769658ac1291`.
- **Invocation**: review prompt (design.md, issue Requirements, commit list, implementation diff excluding `docs/design/**` and `docs/review/**`) piped to `codex exec - -C /tmp/tarnished-325 --sandbox read-only`. Timestamp: 2026-11-01T15:53:35Z.
- **Independence**: the prompt contained no output from the Claude-native review and no orchestrator analysis.

### Codex output (verbatim)

### Critical (must fix)

None found.

### Major (must fix before PR)

- [scripts/lib/common.sh:934](/tmp/tarnished-325/scripts/lib/common.sh:934) **Adding runtimes can invalidate developer-owned TOML.** Given valid `tools.node = "24"`, adding `pnpm` appends `[tools]`, which illegally redeclares the table. Likewise, `'node' = "24"` is not recognized and receives a duplicate entry. Confirmed using the actual awk transformation and Python’s TOML parser. Preserve these representations and validate output before replacement. Add regression coverage for sibling insertion and literal-quoted keys; existing tests miss both paths.

- [templates/languages/node/plugin.sh:185](/tmp/tarnished-325/templates/languages/node/plugin.sh:185) **Missing pnpm still aborts post-create.** The new branch warns that pnpm is absent, then runs `pnpm install` whenever `package.json` exists. Under `set -e`, this exits 127 and prevents subsequent Codex/plugin setup. The monorepo variant has the same problem. Guard dependency installation and version reporting behind pnpm availability, and test the generated block with Node available but pnpm absent.

- [templates/services/redis/plugin.sh:203](/tmp/tarnished-325/templates/services/redis/plugin.sh:203) **The Redis flavor violates NFR-4’s build-only root requirement.** It still emits `sudo apt-get` into post-create. Although unchanged and consistent with the design, this misses the issue’s explicit requirement. Move `redis-tools` installation into `plugin_dockerfile` using the shared helper. Add `redis-cli` to the Redis CI smoke checks, which currently check only core tools.

### Minor (fix when cheap)

- [.github/workflows/scaffold-build.yml:107](/tmp/tarnished-325/.github/workflows/scaffold-build.yml:107) **The forbidden-symlink assertion does not fail CI.** Bash exempts `! grep` from `set -e`; the following successful check masks its failure. Reproduced with a matching forbidden line and an overall zero exit status. Use an explicit `if grep …; then exit 1; fi`.

- [templates/core/.devcontainer/scripts/setup_claude.sh:27](/tmp/tarnished-325/templates/core/.devcontainer/scripts/setup_claude.sh:27) **Directory creation bypasses the nonfatal helper contract.** If `mkdir -p "$HOME/.claude"` fails, `set -e` terminates the caller before `return 0`. Guard it with a warning and recovery hint, update the mirror, and cover the failure path.

### Suggestions (nice to have)

None beyond the fixes and regression tests above.

### Positive

- Shared CLI installation logic, executable version probes, and position-aware block insertion follow the design well.
- Manifest eligibility preserves the developer-owned install files.
- All 26 mirror pairs match.
- The Dockerfile includes signature/checksum verification; its mise public key matches the [upstream key](https://raw.githubusercontent.com/jdx/mise/main/minisign.pub).

Reviewed `59b6fa0` against `423b0e5`. Changed-file syntax and whitespace checks passed; focused in-memory reproductions confirmed the findings. Mirror checks used a read-only equivalent because the script requires temporary files. Bats was unavailable. Dockerfile and workflow review was static: builds, arm64 execution, and MySQL authentication remain unverified. No files were changed.

**Final verdict: REQUEST_CHANGES.**

### Orchestrator triage of the Codex findings

Every finding was reproduced by the orchestrator before triage (the `mise_toml_ensure` cases with `tomllib`, the node block by reading the generated text, the redis `sudo apt-get` line, the `! grep` errexit exemption).

| # | Severity | Finding | Disposition |
| --- | --- | --- | --- |
| C1 | Major | `mise_toml_ensure` appends a `[tools]` header after top-level dotted `tools.*` keys (invalid TOML) and does not recognise literal-quoted keys | Fix: dotted-key insertion when the section exists only in dotted form; strip single quotes; regression tests with `tomllib` validation |
| C2 | Major | node post.sh block runs `pnpm install` / `pnpm --version` after warning that pnpm is absent, aborting `post.sh` under `set -e` | Fix: guard on `command -v pnpm` in both block variants; test under `set -e` with no pnpm |
| C3 | Major | redis plugin still installs `redis-tools` with `sudo apt-get` from `post.sh` (NFR-4, FR-6) | Fix: move to `plugin_dockerfile` via `dockerfile_add_os_packages`; add `redis-cli` to the CI smoke; tests |
| C4 | Minor | `! grep` assertions in `scaffold-build.yml` are exempt from `set -e` | Fix: explicit `if grep ...; then exit 1; fi` |
| C5 | Minor | `mkdir -p "$HOME/.claude"` in `setup_claude.sh` can abort the caller | Fix: guard with `[WARN]`; mirror; test |

No finding deferred.

## Post-completion change: CI fix `bba1c4f` and its scoped review

After `review_status: complete` was recorded at `e30a1d9`, the first `scaffold-build.yml` run on PR #326 failed for the four service flavors in the **scaffold** step: `merge_docker_compose_services` runs `yq eval-all` on overlays that still carry `{{PROJECT_NAME}}` placeholders, and go-yaml rejects a line beginning with `{`. (Locally no `yq` is installed, so the fallback path masked it.) The executor committed `bba1c4f` (sentinel substitution around the yq merge, `tests/common_compose.bats`). Per `references/completion.md` an implementation change after `verified_head` requires a review of the changed scope, so a scoped Codex review of that single commit was run.

- **Reviewer**: Codex CLI 0.163.0 (model: gpt-6-astra, reasoning effort: high), `codex exec - -C /tmp/tarnished-325 --sandbox read-only`, prompt = the commit's diff plus the nine criteria; timestamp 2026-11-01T16:22:01Z.

### Codex output (verbatim, scoped to `bba1c4f`)

### Critical (must fix)

None.

### Major (must fix before PR)

- [common.sh:1317](/tmp/tarnished-325/scripts/lib/common.sh:1317): **Sentinel restoration is not lossless.** Verified with the exact sed expressions:
  - `{{PROJECT_NAME}}_{{PROJECT_NAME}}` becomes `{{PROJECT_NAME_____TARNISHED_PH_PROJECT_NAME}}`, which later rendering leaves unresolved. The greedy capture consumes the delimiter and subsequent sentinel.
  - Literal `__TARNISHED_PH_PROJECT_NAME__` becomes `{{PROJECT_NAME}}`, then the project name—even in a base file originally containing no placeholders.

  Use collision-checked tokens with unambiguous boundaries and restore only tokens actually introduced. Add regression cases for adjacent placeholders, underscore suffixes, and literal sentinel text.

### Minor (fix when cheap)

- [common.sh:1310](/tmp/tarnished-325/scripts/lib/common.sh:1310): The three predictable temporary paths are opened with truncating redirects and subsequently deleted without establishing ownership. Existing files at those paths are destroyed; symlinks are followed. Allocate private temporary files with `mktemp`, handling partial allocation failures and cleaning up only successfully allocated paths.

- [common_compose.bats:18](/tmp/tarnished-325/tests/common_compose.bats:18): The fake tests placeholder removal, **not go-yaml parsing or YAML merging**. It rejects even quoted placeholders and concatenates documents into duplicate `services:` mappings. Consequently, the scaffold assertions pass without establishing a usable Compose configuration. Keep the stub for failure injection, but add a real mikefarah-yq test that parses the rendered output and asserts both the original app and added service survive.

### Suggestions (nice to have)

- Extend failure tests to cover both preprocessing commands and output restoration under an explicit `set -euo pipefail` caller. Currently only yq failure is injected.

### Positive

- The guarded processing chain reaches cleanup on sed/yq failures under `set -e`; assuming cleanup succeeds, the existing error message and return code are preserved.
- Placeholder restoration runs regardless of whether the base contains placeholders.
- All five shipped Compose templates passed exact sed round-trip checks. Bash syntax and diff whitespace checks passed.
- Scope remained limited to this commit. Bats and real yq were unavailable; parser/serializer behavior was not executed. Requirement assessment used the supplied follow-up contract and local design context.

**Final verdict: REQUEST_CHANGES**

### Orchestrator triage

| # | Severity | Finding | Disposition |
| --- | --- | --- | --- |
| S-1 | Major | Sentinel restore regex is greedy across `_`-adjacent placeholders; literal sentinel text in input is mis-restored | Fix: boundary-safe sentinel (`tarnishedph-NAME-hptarnished`), collision check with fallback to the non-yq path, regression tests |
| S-2 | Minor | Predictable temp paths opened with truncating redirects | Fix: `mktemp`-allocated private files, cleanup only of allocated paths |
| S-3 | Minor | Fake-yq tests do not model go-yaml parsing or a real merge | Fix: add a real mikefarah yq v4 test (skipped when yq is absent) and run it locally with a downloaded yq binary |
| S-4 | Suggestion | Inject failures into the preprocessing/restore steps too | Apply |


## Fixes Applied

Both independent reviews were run under `/flow`, so fixes were applied by the `executor` subagent and verified by the orchestrator before being recorded here.

### Claude-native review findings → `59b6fa0` (`fix: address review feedback for #325`)

| # | Severity | Finding | Resolution |
| --- | --- | --- | --- |
| 1 | Minor | add-module `mise install` hint printed unconditionally | `mise_toml_ensure` sets `MISE_TOML_CHANGED=true` on a real write; `setup.sh` initialises it and prints the hint only when true; bats: already-declared language prints no hint |
| 2 | Minor | celery CI entry / test title diverged from the design wording | `docs/design/#325/workflow.md` matrix row and the bats test name now state `--lang python --celery` and why |
| S1 | Suggestion | `post_sh_add_block` stdin guard | `[[ -t 0 ]]` → `print_error`, return 1 (not unit-testable in bats; noted) |
| S2 | Suggestion | `--scope project` writes a refresh-managed file | One sentence added to `docs/setup.md` |
| S3 | Suggestion | expected `claude plugin list --json` shape undocumented | Comment added in both `setup_plugins.sh` copies |
| S4 | Suggestion | no `concurrency` group on the build matrix | Workflow-level `concurrency` added to `scaffold-build.yml` |

Orchestrator verification: diff of `59b6fa0` read hunk by hunk; `common_mise`, `common_postsh`, `setup_mise_scaffold`, `setup_plugins` bats green; mirrors identical.

### Codex review findings → `e30a1d9` (`fix: address Codex review feedback for #325`)

| # | Severity | Finding | Resolution |
| --- | --- | --- | --- |
| C1 | Major | `mise_toml_ensure` emitted a `[tools]` header after top-level dotted `tools.*` keys (invalid TOML) and missed literal-quoted keys | Dotted-key insertion (`tools.pnpm = ...`) when the section exists only in dotted form; single quotes stripped in key matching; `api-spec.md` steps 3/5 updated; bats cases validate the output with `tomllib` and cover `'node'` / `tools.'node'` |
| C2 | Major | node post.sh block ran `pnpm install` / `pnpm --version` after warning pnpm was absent, aborting `post.sh` under `set -e` | `HAS_PNPM` gate in both block variants, `pnpm install` failure downgraded to `[WARN]`; bats runs the generated blocks under `set -e` with a fake `node`, a `package.json` and no `pnpm` (both fail on the old code) |
| C3 | Major | redis plugin installed `redis-tools` with `sudo apt-get` from `post.sh` (NFR-4, FR-6) | `plugin_dockerfile` → `dockerfile_add_os_packages ... redis redis-tools`; sudo branch removed (warns to rebuild when `redis-cli` is missing); `redis-cli` added to the redis and celery CI smoke sets and to `smoke-runtimes.sh`; bats for the marker block, idempotency, and no `sudo` in generated `post.sh` (redis and celery scaffolds) |
| C4 | Minor | `! grep` assertions exempt from `set -e` in `scaffold-build.yml` | Explicit `if grep ...; then ... exit 1; fi` for both assertions (pre-existing `! grep` lines in older bats files are outside this branch and untouched) |
| C5 | Minor | `mkdir -p "$HOME/.claude"` could abort the caller | Guarded with `[WARN]` + manual hint in both mirror copies; bats case with an unwritable `HOME` asserts exit 0 and that the caller survives `set -e` |

Orchestrator verification of `e30a1d9`: the two TOML reproductions re-run against the new helper (`tools.pnpm = "12.16.1"` appended as a dotted key and accepted by `tomllib`; `'node'` kept with "Kept existing" message); node, redis, workflow and `setup_claude.sh` hunks read; `scripts/verify-mirrors.sh` byte-identical; full bats suite re-run by the orchestrator on `e30a1d9`: 480 ok, 0 failed, exit 0 (baseline on `develop` @ `423b0e5`: 364 ok, 0 failed).

### Scoped Codex review findings (on `bba1c4f`) → `f8a0e57`, `3f4c8ca`

| # | Severity | Finding | Resolution |
| --- | --- | --- | --- |
| S-1 | Major | Greedy sentinel restore across `_`-adjacent placeholders; literal sentinel text mis-restored | `f8a0e57`: sentinel `tarnishedph-NAME-hptarnished` with `-` boundaries outside the capture class; inputs containing the sentinel text fall back to the non-yq merge with a warning; bats: adjacent `_`/`-` placeholders, `_suffix`, placeholder-free base, literal-sentinel fallback |
| S-2 | Minor | Predictable temp paths | `f8a0e57`: `mktemp`-allocated private files; failed allocation cleans only what was allocated and returns 1 |
| S-3 | Minor | Fake-yq tests did not model a real merge | `f8a0e57`: real mikefarah yq v4 test (skips when absent) run locally with yq v4.47.1 (checksum-verified download): merged output keeps placeholders, renders to a compose file whose services are `demo` and `demo-db` and carries the overlay volume; end-to-end `setup.sh --postgresql -y` with real yq renders a parseable compose file |
| S-4 | Suggestion | Inject failures into every pipeline stage | `f8a0e57`: failure-injection test under `set -euo pipefail` for both `sed`s, `yq` and the restore step (rc=1, no temp files). `3f4c8ca`: the test's own `yq` stub was not executable, so PATH lookup bypassed it (real yq won, or the non-yq fallback ran); fixed with `chmod +x` plus a marker proving the yq pipeline is exercised; verified with and without a real yq, and in a 5× loop |

Orchestrator verification: `bba1c4f`, `f8a0e57` and `3f4c8ca` diffs read; the orchestrator's own full-suite run with the real yq on PATH exposed the `3f4c8ca` defect (488 ok / 1 not ok on `f8a0e57`); after `3f4c8ca` the executor's full-suite run with real yq is 489 ok / 0 not ok and the orchestrator re-ran `tests/common_compose.bats` with real yq (9 ok). CI on `bba1c4f` (PR #326): all 11 `scaffold-build` entries green, including the four service flavors (psql 17.11, MariaDB client 11.8.6, redis-cli 8.0.2, celery python 3.12.16 / uv 0.13.6), plus Rust quality, Integration Tests and mirror parity; CI on the final head is recorded in the PR.

### Completion (updated)

- Critical: none in any review. Major: 4 (3 Codex full review + 1 Codex scoped review), all fixed and verified. Minor: 6 total, all fixed. Suggestions: 5, all applied. Nothing deferred.
- `verified_head` is `3f4c8ca` (code head after the review fixes `59b6fa0`, `e30a1d9`, the CI fix `bba1c4f`, its scoped-review fixes `f8a0e57`, and the test fix `3f4c8ca`). Review-artifact commits contain no code and preserve freshness per `references/completion.md`.
- Still unverified in this environment (no `docker`): image build, `bash -c` / `bash -ic` runtime checks, post-create `claude --version`, arm64, MySQL client login. `.github/workflows/scaffold-build.yml` is the automated check for these on the PR; the `/pr` stage treats its result as part of readiness.
