# Code Review: #276

- **Branch**: bugfix/TE-ToshiakiTanaka2/#276/suppress-spurious-curl-23-from-remote-bootstrap
- **Base**: develop (merge base: 81dd52a)
- **Review scope**: Medium (~51 lines of code + ~265 lines of tests + ~650 lines of docs = 969 total)
- **Reviewed at**: 2026-05-13
- **Reviewer**: Codex CLI (codex-cli 0.128.0)

---

## Codex Review Output

### Warnings (should fix)
- [plugin.sh:41](/workspace/templates/github-actions/project-integration/plugin.sh) The new cross-subshell error channel is a predictable file in shared `/tmp` (`tarnished-gh-last-error.$$`), and `_gh_run()` truncates/writes it at [lines 56-58](/workspace/templates/github-actions/project-integration/plugin.sh). That is a local file-clobber primitive: another user/process can pre-create a symlink at that path and have setup overwrite any file writable by the caller. Use `mktemp` once for the shared file path, or better, restructure the callers so the documented in-process `GH_LAST_ERROR` variable can be used instead of a world-visible file.
- [plugin.sh:43](/workspace/templates/github-actions/project-integration/plugin.sh) This plugin is sourced, but it installs a bare `EXIT` trap every time it loads. That replaces any existing shell cleanup hook. `setup.sh` already registers its own EXIT cleanup in [setup.sh:2077](/workspace/setup.sh); sourcing this plugin later in an upgrade flow can stomp that trap and leak the upstream temp checkout. A sourced plugin should not unconditionally replace the parent shell's EXIT trap.

### Suggestions (nice to have)
- [design.md:52](/workspace/docs/design/#276/design.md) and [api-spec.md:28](/workspace/docs/design/#276/api-spec.md) still specify a transient `GH_LAST_ERROR` string, but the implementation and tests now depend on `GH_LAST_ERROR_FILE`. If the file-based approach is kept, the design docs need to be updated to match.
- [setup_remote_bootstrap.bats:77](/workspace/tests/setup_remote_bootstrap.bats) The behavioral regression test never invokes `curl`; it does `cat "$SETUP_SH" | bash`. That exercises the pipe-detection path, but it cannot catch the original `curl (23)` emitter. Either rename the test to reflect what it actually proves or add a `curl file://... | bash` style harness.

### Positive
- [setup.sh:68](/workspace/setup.sh) The bootstrap fix itself is minimal and correct: redirecting the exec'd shell's stdin to `/dev/null` is the right way to sever the inherited `curl | bash` pipe without changing local invocation behavior.
- [plugin_interactive_setup](/workspace/templates/github-actions/project-integration/plugin.sh) The caller-side move to `_print_gh_warning` does address the original `set -e` failure mode for normal `gh` auth/API errors and preserves the manual fallback path.

`bats` is not installed in this environment, so I could not execute the new test files; the review is based on static inspection and shell-level spot checks.

**Final verdict: REQUEST_CHANGES**

---

## Fixes Applied

All four items addressed in commit `1bef170` (`fix: address review feedback for #276`).

- **W1 (predictable /tmp path)** — `GH_LAST_ERROR_FILE` is now obtained via `mktemp -t tarnished-gh-last-error.XXXXXX` (unpredictable name, 0600 perms). `_gh_run` and `_print_gh_warning` tolerate an empty path (degraded no-capture mode) so the helpers stay functional if mktemp fails.
- **W2 (sourced plugin stomped on caller's EXIT trap)** — Removed the `trap "rm -f ..." EXIT` from the plugin. The per-PID tempfile is small and uniquely named; we let the OS clean it. Verified by spot-check: sourcing the plugin no longer overwrites a pre-existing EXIT trap.
- **S1 (design docs lagged implementation)** — Updated `docs/design/#276/{design,api-spec}.md` and the shared layer (`architecture.md`, `api-spec.md`, `sequence.md`) to describe `GH_LAST_ERROR_FILE` (file-based), the `mktemp` rationale, and the deliberate absence of the EXIT trap. `GH_LAST_ERROR` no longer appears anywhere in the design corpus.
- **S2 (misleading bats test name)** — Renamed the behavioral bootstrap test to "pipe-fed invocation completes cleanly through clone-and-exec" and added a comment clarifying that the test does not invoke real curl (the EPIPE is timing-dependent). The static-invariant test above it is what actually pins the `< /dev/null` redirect. Also silenced SC2030/SC2031 false positives in `project_integration_gh.bats` with an explanatory disable.

### Verification
- `shellcheck` on `plugin.sh` + both bats files: clean (exit 0).
- `bats` (12 cases): all pass.
- EXIT-trap spot-check: a pre-existing `trap "echo OLD-TRAP-PRESERVED" EXIT` survives sourcing `plugin.sh`.
- `mktemp` produces a 0600-perm file with a random suffix (verified locally).

Commit: `1bef170`

