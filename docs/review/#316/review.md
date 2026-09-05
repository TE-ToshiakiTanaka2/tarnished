---
repository: "TE-ToshiakiTanaka2/tarnished"
issue_number: 316
branch: "bugfix/TE-ToshiakiTanaka2/#316/preserve-project-ownership-during-ai-updates"
reviewed_head: "211ebd6c1d426932d2a2146e62a8ba6748931956"
base_ref: "develop"
base_commit: "c78bb7afd71e029503262dcf3d30f8d5e6ae4e4b"
merge_base: "c78bb7afd71e029503262dcf3d30f8d5e6ae4e4b"
issue_body_sha256: "09c92d33ac68e638bfd1cc05fc682c8a8b8a60e05398b5dd1d03345b4ca897e7"
timestamp: "2026-09-05T13:10:37.342327+00:00"
reviewer_model: "gpt-6-astra"
reviewer_reasoning_effort: "high"
review_status: "report-only"
verified_head: null
reviewer: "Independent Codex CLI 0.153.4, fresh context, read-only"
reviewer_configuration: "Runtime verified against project .codex/config.toml"
review_scope: "Deep: 36 files, 3624 additions, 1881 deletions; prior review artifacts excluded"
orchestrator_verdict: "REQUEST_CHANGES"
finding_counts: {"Critical": 0, "Major": 4, "Minor": 7}
additional_reviewer: "Claude Fable 5.1 (claude-fable-5-1; runtime verified)"
---

# Independent review — original output

## Review Summary

**Overall**: REQUEST_CHANGES

Reviewed `211ebd6c1d426932d2a2146e62a8ba6748931956` against base `c78bb7afd71e029503262dcf3d30f8d5e6ae4e4b`, both the supplied raw Issue #316 requirements and design, all nine review criteria, and applicable AGENTS.md invariants.

The positive ownership policy, conservative legacy migration, retained deletion intent, and per-file refresh substantially improve preservation. Syntax checks, ShellCheck at error severity, all mirror comparisons using a read-only adaptation, catalog exclusions, and legacy helper digest checks passed.

No files were changed. Prior review results and `.claude/scheduled_tasks.lock` were excluded. Writable-fixture tests were not run; the findings below were traced through code and read-only probes.

## Critical Issues

None.

## Major Issues

- **[scripts/lib/manifest.sh:583](/workspace/scripts/lib/manifest.sh:583) — Upgrade can overwrite or prune a helper edited after its initial hash comparison.**  
  `apply_decisions_for_scope` hashes the destination at `setup.sh:2318`, then passes only the decision and paths to `manifest_apply`. If an editor or another agent saves the helper after that comparison, replacement checks only path safety before `mv`; pruning at line 621 likewise performs no content recheck. The new edit can therefore be overwritten or deleted despite the preservation contract in FR-5. A read-only probe with mutation commands stubbed confirmed both operations proceed without another hash check.

  Pass the expected current and desired hashes into `manifest_apply`. Recheck the destination immediately before replacement/deletion, verify temporary-copy bytes, and preserve the previous baseline when either check fails. Add deterministic fixture tests that change the destination between decision and application.

## Minor Issues

- **[templates/core/.devcontainer/scripts/refresh-assets.sh:374](/workspace/templates/core/.devcontainer/scripts/refresh-assets.sh:374) — The prescribed overlay conflict recovery can repeatedly conflict.**  
  Suppose the recorded baseline is A, upstream advances to B, and the developer has local changes C. Following README line 171—save C in the sidecar, copy upstream B into the live file, then rerun—leaves `current=B`, `old=A`, and `desired=C`. Because `base_hash` is calculated only without prior state, refresh rejects B again, despite its exact upstream match. A read-only probe reproduced this outcome.

  Make the warning and documentation describe recovery compatible with the decision table: when retaining an overlay, explicitly place the chosen effective overlay bytes in the live destination so `current == desired` permits adoption. Document upstream-only recovery separately and add a regression covering the published recovery steps with an existing baseline.

## Suggestions

None.

# Orchestrator verification and additional findings

The original independent output above is preserved verbatim. The orchestrator checked its claims against code and separately exercised disposable fixtures. The prior review is retained in Git history at `211ebd6c1d426932d2a2146e62a8ba6748931956`; it was not supplied to this reviewer. Current repository code, the fetched target and the decoded issue-body digest stayed unchanged throughout this run.

## Additional Major: escaped filename hashes poison refresh state

Location: `templates/core/.devcontainer/scripts/refresh-assets.sh:299` (also the workspace mirror).

GNU `sha256sum` prefixes its output with a backslash when a filename contains a backslash. `hash_file` takes the first space-delimited token without normalizing or validating it. The path validators accept that filename. If an upstream file and its existing destination have identical bytes, adoption records `sha256: "\\<digest>"` instead of a 64-character hexadecimal value. The next invocation rejects the entire state in `load_state`, blocking all mappings. A new copy also fails because its ordinary temporary filename produces a different hash token.

Reproduction: create identical `assets/skill\name.md` and `.claude/skills/skill\name.md` in separate temporary source/project roots, configure that mapping, and invoke the unchanged updater twice with `--source-dir`. First run reports success and persists a backslash-prefixed digest; second run warns `invalid refresh state` and stops all refreshes. Full local output: `/tmp/tarnished-316-rereview-filename-proof.txt`.

Correction: hash file contents through standard input (or normalize the checksum output correctly), validate the digest before saving state, and cover first installation plus exact-match adoption/repeat refresh for escaped filenames. Classification: **Major**, because one accepted filename can persistently block every AI asset update (FR-6/FR-7).

## Additional Minor: dry-run mutates the existing cache index

Location: `templates/core/.devcontainer/scripts/refresh-assets.sh:167` (also the workspace mirror).

`validate_cache` invokes ordinary `git status` even during dry-run. Git refreshes and writes index stat metadata when a tracked file's timestamps changed but its bytes stayed identical. This contradicts the documented no-persistent-cache-write dry-run contract; application contents remain preserved.

Reproduction: create a clean local Git upstream/cache, change only a cached tracked file's mtime, hash `.git/index`, then run `refresh-assets.sh --project-root <fixture> --dry-run` using that existing cache. Its index SHA-256 changed while the command reported a preview. Full local output: `/tmp/tarnished-316-rereview-dryrun-proof.txt`.

Correction: suppress Git's optional locks/index refresh writes with `git --no-optional-locks ... status` during dry-run (or all read-only cache checks), and test index byte/metadata preservation with an existing cache. Classification: **Minor**.

## Verification of independent findings

- **Major, concurrent helper edit:** confirmed the call site supplies no expected content hashes. A disposable fixture replaced the target with a developer edit immediately after copying the staged helper to its temporary file. `manifest_apply UPDATE` returned success and overwrote that edit. The independent reviewer additionally verified the prune path with read-only mutation stubs. Local fixture output: `/tmp/tarnished-316-rereview-race-proof.txt`.
- **Minor, overlay recovery:** reproduced actual updater runs with baseline A, upstream B and local C. After saving C in the sidecar and copying B to the live destination as README instructs, the next refresh still reported a conflict and left B in place. Output: `/tmp/tarnished-316-rereview-overlay-proof.txt`. The correction should align recovery instructions with the preservation decision table rather than silently weaken conflict checks.
- Independent verification passed Bash syntax, error-level ShellCheck, all 21 mirror pairs, catalog manifest exclusions, and legacy updater digest checks. All nine criteria and both ground truths were assessed.
- Existing broad Bats/Rust/CI successes for this unchanged implementation were reused; they do not cover the newly reproduced edge cases. No broad suite was repeated solely because a new review was requested.

## Fixes Applied

None — this is a review-only request. Both Major findings and both Minor findings remain unresolved; no source edits, fix commits, pushes, PR edits or merges were performed. Only this review artifact was updated. The preexisting untracked `.claude/scheduled_tasks.lock` remains untouched.

The current review is **REQUEST_CHANGES / report-only**, and does not establish readiness for merge. The two Major findings should be corrected and verified before approval.


# Additional independent review — Claude Fable 5.1

The user explicitly requested this additional reviewer. The prompt contained the same committed code, issue requirements and design, but excluded every prior review result. No model fallback was configured. The final usage record confirms the review was generated by `claude-fable-5-1`; the CLI also used an internal Haiku helper, which was not the reviewer. Effort was left at the CLI default because neither project nor user settings specify it.

```json
{
  "repository": "TE-ToshiakiTanaka2/tarnished",
  "issue_number": 316,
  "branch": "bugfix/TE-ToshiakiTanaka2/#316/preserve-project-ownership-during-ai-updates",
  "reviewed_head": "211ebd6c1d426932d2a2146e62a8ba6748931956",
  "base_ref": "develop",
  "base_commit": "c78bb7afd71e029503262dcf3d30f8d5e6ae4e4b",
  "merge_base": "c78bb7afd71e029503262dcf3d30f8d5e6ae4e4b",
  "issue_body_sha256": "09c92d33ac68e638bfd1cc05fc682c8a8b8a60e05398b5dd1d03345b4ca897e7",
  "timestamp": "2026-09-05T13:27:24.589145+00:00",
  "reviewer": "Claude Code 2.1.261",
  "reviewer_model": "claude-fable-5-1",
  "reviewer_effort": "CLI default (unset in project/user settings)",
  "review_status": "report-only",
  "reviewer_model_verified": "claude-fable-5-1 (runtime init and final modelUsage)",
  "reviewer_effort_verified": "not exposed; CLI default, no effort override",
  "allowed_tools": [
    "Read",
    "Glob",
    "Grep"
  ],
  "raw_verdict": "REQUEST_CHANGES",
  "raw_finding_counts": {
    "Critical": 0,
    "Major": 2,
    "Minor": 8,
    "Suggestions": 5
  }
}
```

## Original Claude output (verbatim)

Verification is complete; I'm now compiling the review from the evidence gathered.

## Review Summary

**Overall**: REQUEST_CHANGES

The branch delivers the core of #316 well: the runtime refresh no longer mirror-deletes, ownership is positive and provenance-based, legacy v1 claims are dropped rather than trusted, and the Bats matrix in `tests/refresh_assets.bats`, `tests/setup_maintenance.bats`, `tests/setup_upgrade.bats`, and `tests/manifest.bats` covers most of the design's validation table. Two Major portability regressions in the host-side maintenance path (macOS and symlinked filesystem prefixes) block approval because they make `--refresh`, `--upgrade`, and `--create-manifest` fail on hosts the project documents as supported.

## Critical Issues

None.

## Major Issues

- [scripts/lib/common.sh:282-305, templates/core/.devcontainer/scripts/refresh-assets.sh:66-81] **Symlink rejection is applied to every absolute-path prefix, not just the project-relative part.** `manifest_safe_path` splits `"${root#/}/$rel"` and returns 1 if any component (including ancestors of the root) is a symlink; `ordinary_path` does the same for `PROJECT_ROOT`, `SOURCE_DIR`, `CONFIG_PATH`, and `CLONE_DIR` before they are canonicalized. Concrete trigger: on macOS `mktemp -d` returns `/var/folders/...` and `/var` is a symlink to `/private/var`, so `manifest_recording_start "$staging_dir"` (setup.sh:2167, :2218) fails inside the `bash -e` child and every `--upgrade` / `--create-manifest` aborts with "Staging failed". The same happens on Linux hosts where `/home` is a symlink (Fedora Silverblue) or the project lives under `/tmp` on macOS: `validate_maintenance_target` reports "Unsafe project marker", and `refresh-assets.sh` reports "unsafe/unavailable project root" (line 507). Scaffolding is also affected because `_recording_destination_safe` now runs for every copy during `main` (setup.sh:2823). Correction: resolve roots once with `pwd -P`/`realpath` and only walk components *below* the validated root for symlink/type checks; the design's requirement is about symlinks inside source/target/overlay/state, not the host filesystem prefix.

- [setup.sh:1772, setup.sh:1813, templates/core/.devcontainer/scripts/refresh-assets.sh:149,196,224,299,328,485,497] **Host-side `--refresh` depends on GNU-only tools while the rest of setup.sh deliberately supports macOS.** `run_refresh` uses `mv -fT` (BSD `mv` has no `-T`), and the updater it invokes hard-requires `sha256sum`, `realpath -m`, and `mv -T`, exiting 0 with "sha256sum not found" on macOS so the AI refresh silently does nothing; setup then fails at the `mv -fT` for the config or helper with `mv: illegal option -- T`. README.md:10 advertises macOS support and `common.sh::sha256_file` (lines 85-90) plus `replace_placeholders` (line 926) carry explicit Darwin branches, so a bare `setup.sh` rerun in an existing project is now broken on macOS hosts. Correction: in setup.sh use `sha256_file` and plain `mv -f` (or `mv` after an explicit `-e` check); in the updater fall back to `shasum -a 256` and avoid `-T`/`realpath -m` (use `cd`/`pwd -P` for existing dirs, `printf` join for non-existing ones), or document that `--refresh` requires GNU coreutils and fail fast with a clear error instead of `exit 0`.

## Minor Issues

- [scripts/lib/manifest.sh:130-142, setup.sh:1743] **A v2 manifest becomes unreadable, and bare rerun fails outright, as soon as any recorded path stops being eligible.** `manifest_read` rejects the whole file if a `files` key fails `_manifest_path_eligible`, and `run_refresh` returns 1 on read failure before any refresh happens. Adding a future entry to `MANIFEST_EXCLUDE_GLOBS` (the #286-style migration this codebase has already done once) would brick `--refresh`/`--upgrade` for every existing v2 project instead of dropping the claim with a warning, which is exactly what `apply_decisions_for_scope` (setup.sh:2269-2271) is written to do but can no longer reach. Correction: validate path *syntax* in `manifest_read`, and let callers drop ineligible entries with the existing warning.

- [scripts/lib/manifest.sh:63-79] **Language/service allowlist is duplicated by hand.** `manifest_options_valid` hardcodes `rust|python|node|deno|latex|go` and `celery|mysql|postgresql|redis`, separately from `AVAILABLE_LANGUAGES`/`AVAILABLE_SERVICES` in setup.sh:93,105 and `templates/languages/*`. Adding a language plugin without updating this jq makes every manifest for such projects "Invalid manifest scaffold options". Correction: build the allowlist from the setup.sh arrays (passed via `--argjson`) or from the directory listing under `templates/`.

- [setup.sh:1802-1821] **Missing-helper cases are misreported.** With a v2 trusted hash (or a tombstone) and the helper absent, the code falls into the `else` branch and prints "Container-start updater remains old or locally edited", although the file does not exist. Conversely, with no manifest and no helper at all, the helper is created (first alternative on line 1802) but nothing tells the developer that `post.sh`/`devcontainer.json` have no wiring to invoke it, so the "installed" updater never runs at container start. Correction: distinguish "absent, deletion preserved" from "edited/unknown", and when creating a helper where none existed, report that container-start wiring must be added manually.

- [templates/core/.devcontainer/scripts/refresh-assets.sh:537] **Summary omits conflicts/unknown/unsafe counts.** The design's Summary contract ("Counts plus conflicting/unknown/removed/unsafe paths") and the shared api-spec ("Summaries distinguish applied, unchanged, preserved conflicts/unknowns, removals and failures") are not met: only installed/removed counts are printed; conflicts are scattered `[WARN]` lines with no tally, so a developer scanning a container-start log cannot tell whether the run left pending decisions. Correction: count conflicts/unknown/unsafe/failed per `reconcile_file` branch and include them in the final line.

- [templates/core/.devcontainer/scripts/refresh-assets.sh:355-360,369-375,459-464,474-476] **Per-file process fan-out on every container start.** Each candidate spawns 3-5 `jq` processes plus `sha256sum` calls, and `persist_state` spawns one `jq` per entry. With the new default catalog (Claude commands/skills/agents/scripts, Codex skills, erd twice, seven workflow files) this is on the order of a couple of thousand subprocesses per `postStartCommand`, replacing what was one `rsync` per mapping. Correction: parse prior state once into associative arrays (`hash`, `origin`, `mapping`) with a single `jq -r @tsv` pass, and serialize state with one `jq` over a TSV stream.

- [templates/codex/plugin.sh:158-160, README.md "AI distribution, customization and migration"] **New Codex sidecar is gitignored by the shipped whitelist.** README directs developers to `.agents/skills.local` for explicit overrides, but the Codex gitignore block ignores `.agents/*` and only allows `.agents/skills/`, so the sidecar cannot be committed and never reaches teammates' or CI containers. Correction: add `!.agents/skills.local/` to the Codex block (new allow line, marker unchanged) or document the limitation.

- [tests/setup_maintenance.bats] **No behavioral test for the monorepo bare rerun.** Design item 3 says bare reruns select refresh "including monorepo roots" and `validate_maintenance_target` has a module-validation branch (setup.sh:1721-1734), but the maintenance suite never creates a `modules.json` target; only the hostile-module rejection is tested in `setup_create_manifest.bats`. Add a monorepo fixture asserting refresh runs, module trees are untouched, and `--add-module` still works there.

- [setup.sh:2664-2671, /workspace/.tarnished-manifest.json] **Bare `./setup.sh` inside the Tarnished checkout itself now rewrites the repository's own committed v1 manifest.** `existing_tarnished_project /workspace` is true, the updater warns about source/target overlap and exits 0, the mirrored helper is "current", and `manifest_write` replaces the committed v1 manifest with a v2 one containing only `refresh-assets.sh`. Correction: refuse maintenance when `$(pwd)` equals `$SCRIPT_DIR` (or its git toplevel) with a clear message.

## Suggestions

- [scripts/lib/manifest.sh:619-623, :575-589] Runtime `install_file`/removal re-hash the target immediately before `mv`/`rm`; `manifest_apply` PRUNE/UPDATE only rechecks path safety. Adding the same content recheck would give both mechanisms the "recheck immediately before mutation" property the design lists.
- [scripts/lib/refresh-legacy.json] Only two legacy helper digests are shipped. Any downstream copy of another historical revision of `refresh-assets.sh` will be reported as "old or locally edited" and require a manual copy. Consider generating the digest list from `git log -- templates/core/.devcontainer/scripts/refresh-assets.sh` at release time, and document in AGENTS.md section 6 that maintainers must append the previous default catalog to `managed_path_catalogs` whenever `refresh.json` defaults change, or the one-time migration stops recognizing it.
- [templates/core/.devcontainer/scripts/refresh-assets.sh:370-380] Legacy projects whose assets were kept "always latest" by the old script will see every since-changed file as a permanent conflict after migration, because adoption only compares against the *current* distribution. Since the cache is a git checkout, an exact-blob lookup against upstream history (`git hash-object` + `git cat-file -e`) would let proven-upstream bytes adopt safely and would materially reduce the one-time review burden FR-4 is trying to eliminate.
- [scripts/lib/common.sh:967-980] Fresh scaffolds commit `.tarnished/refresh-state.json` by default; README asks the developer to ignore it. A new marker-guarded block (no existing marker edited) in `update_gitignore` would seed this for new projects without rewriting user content.
- [docs/design/shared/data-model.md:24, templates/core/docker/Dockerfile.dev:11] The `RefreshConfig` summary row still shows the pre-#316 shape without `use_default_managed_paths`, and the Dockerfile still installs `rsync`, which nothing in the refresh path uses any more.

## Positive assessment

- The runtime decision table in `reconcile_file` (lines 333-403) matches the design table row for row, including overlay-origin deletion protection, user-deletion preservation, and adoption of an identical base before an overlay replaces it.
- Cache handling is genuinely conservative: origin, toplevel, dirty-tree, ancestry, and overlap checks precede any `fetch`/`reset`, cloning goes through a private temp dir, and `rm -rf` is only ever applied to that temp dir.
- `manifest_decide` was kept pure and the trust-stripping happens before it; v1 hashes never reach an overwrite/prune precondition, and `deleted_paths` tombstones are validated to be disjoint from `files`.
- The test suites exercise realistic failure injection (mocked `cp`, `mv`, `find`, `git`) and byte-level snapshots of project-owned files, which is the right shape for FR-8.
- Workspace/template mirrors (`refresh-assets.sh`, `refresh.json`, workflow contracts, skill files) are byte-identical by inspection of the diff and spot-checked line positions.

## Verification limitations

- Tests were not executed; findings on coverage come from reading the Bats files. No CI workflow runs Bats or ShellCheck (`.github/workflows/` contains only asset-parity and Rust/GitHub workflows), so there is no CI evidence for this branch either.
- The two `helper_hashes` digests in `scripts/lib/refresh-legacy.json` could not be recomputed without executing git; one matches the committed workspace v1 manifest, the other is unverified.
- `scripts/verify-mirrors.sh` was not run; mirror identity was checked by comparing the diff hunks and a handful of line-anchored greps.
- macOS behavior is inferred from documented BSD/GNU tool differences and the `/var -> /private/var` symlink, not from a live macOS run.

## Orchestrator dispositions for Claude findings

The raw verdict and severities above have not been rewritten. The following is the orchestrator's assessment after checking code and bounded fixtures. Both newly reported Major issues are accepted. Of Claude's eight Minor findings, five are accepted as current diagnostic, documentation, coverage or control-flow gaps; three are treated as suggestions rather than demonstrated current defects.

| Claude finding | Disposition / evidence |
| --- | --- |
| Major: symlinked host prefixes | Confirmed: `manifest_recording_start` returns 1 for an ordinary fixture project reached through a symlinked parent. This exposes a supported-host compatibility gap. The design also explicitly protects ancestors, so Claude's assertion that the design already excludes host prefixes is too narrow. A correction must define and validate a physical-root boundary while retaining checks inside project/source/state/overlay trees; it must not blindly remove symlink protection. macOS-specific filesystem examples were not tested on macOS. |
| Major: GNU-only host refresh | Accepted from code: host setup now calls the updater that requires `sha256sum`, `realpath -m`, `mv -T`, and setup itself uses `mv -fT`. Existing `sha256_file`/Darwin rendering branches and README's cross-platform support establish the compatibility expectation. This was a static portability check; no live macOS run occurred. |
| Minor: future v2 eligibility changes | Not a current defect: no currently shipped valid v2 path was shown to become ineligible in this branch. Current design requires strict v2 eligibility validation. Retain as a future schema-migration consideration; any relaxation must preserve positive ownership filtering at every writer. |
| Minor: duplicate language/service allowlists | The lists currently agree. Treat as an optional maintenance improvement rather than a present unsupported-plugin defect; no added plugin is rejected in this branch. |
| Minor: missing-helper diagnostics / wiring | Accepted diagnostic gap: a preserved missing trusted helper is reported as old/edited. For an installation without container hooks, creating a helper does not itself establish those hooks; guidance should distinguish these states while preserving project settings. |
| Minor: missing summary categories | Accepted design gap: the final runtime line reports installed/removed only, while the API contract calls for applied/unchanged/conflicts/unknowns/removals/failures. Warnings are present but not tallied. |
| Minor: subprocess fan-out | Unmeasured performance suggestion, not a demonstrated material regression. The current default source inventory has 64 candidates; Claude's estimate of a couple of thousand processes is not substantiated for the shipped catalog. Benchmark before redesigning serialization. |
| Minor: Codex sidecar gitignore | Confirmed `.agents/skills.local/example/SKILL.md` is ignored by the shipped whitelist. The plugin explicitly describes local overrides as ignored, so treat this as a missing documented limitation rather than silently changing that policy. If shared sidecars are intended, use a migration that reaches existing marker-guarded installations. |
| Minor: missing monorepo maintenance regression | Accepted test gap: other suites exercise monorepo bootstrap and earlier manual scaffold/add-module smoke tests passed, but there is no automated positive bare-refresh monorepo case in `setup_maintenance.bats`. No monorepo data-loss defect was demonstrated. |
| Minor: self-checkout manifest rewrite after rejected source | Confirmed in a disposable local clone, never `/workspace`: `setup.sh --refresh -y` warned that source/target overlap was unsafe, then returned 0 after rewriting the clone's v1 manifest (8 entries) to v2 (1 entry). Evidence: `/tmp/tarnished-316-fable51-selfhost-proof.txt`. Prevent subsequent maintenance writes after a rejected source/target boundary. |
| Suggestion: final content recheck | Duplicate of the confirmed Major from the Codex review and orchestrator race fixture. Keep the existing Major severity; Claude's lower classification does not clear the data-preservation issue. |
| Suggestion: expand historical helper/catalog inventory | Optional release-maintenance improvement. Existing documented conservative migration remains intentional. |
| Suggestion: historical Git-blob adoption | Not part of the accepted current design; exact matches against a selected distribution are deliberate. Merely finding an object in Git is insufficient proof of a path's distribution provenance. Any future implementation needs path/ref validation rather than relaxing ownership checks. |
| Suggestion: ignore generated refresh state | Optional improvement for new scaffolds. README already documents the local ignore step; changing append-only blocks needs an existing-project migration plan. |
| Suggestion: schema summary / rsync package cleanup | Optional documentation/cleanup work; no runtime correctness defect demonstrated. |

### Combined outcome and validation limits

- **REQUEST_CHANGES** remains the combined verdict. Confirmed unresolved findings now total **4 Major and 7 Minor**: the previous Codex/orchestrator report's 2 Major/2 Minor plus the newly accepted 2 Major/5 Minor above. Optional recommendations and duplicate findings are not added to those counts.
- Claude assessed all nine criteria and both independent ground truths, but had only Read/Glob/Grep. It did not execute Bats, ShellCheck, Git commands or the mirror script. Its statement about absent CI evidence concerns shell behavior; the existing PR does have passing Rust/asset-parity and related CI checks. Earlier local Bats/ShellCheck and all 21 mirror successes remain valid for unchanged code.
- The orchestrator checked the symlink-prefix behavior and Codex sidecar ignore rule using temporary fixtures, counted the shipped source candidates, and reproduced the self-checkout behavior in a disposable clone. Live macOS portability remains untested.
- The source tree, reviewed HEAD, fetched base and issue digest are unchanged. Only this review artifact has been updated; previous raw reviews are preserved. No fixes, commits, pushes, PR edits or merges were made in response to this additional review.
