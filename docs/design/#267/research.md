# Research: #267 — GitHub Actions Node.js 20 → Node.js 24 migration

External research used to ground the version-pin decisions for #267. Issue-specific (no expected reuse beyond this migration), so saved here rather than `shared/research/`.

## Question 1 — Authoritative timeline

Source: [GitHub Changelog: Deprecation of Node 20 on GitHub Actions runners](https://github.blog/changelog/2025-09-19-deprecation-of-node-20-on-github-actions-runners/) (2025-09-19).

| Date | Event |
| --- | --- |
| **2026-06-02** | Node 24 becomes the default runtime — JavaScript actions are forced to Node 24 even when their `action.yml` declares `runs.using: node20` |
| **Fall 2026 (≈2026-09-16)** | Node 20 fully removed from runners |

Direct quote on early opt-in:

> If you'd like to test Node24 ahead of time, set `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24=true` as an `env` in your workflow or as an environment variable on your runner machine to force the use of Node24.

Direct quote on the temporary post-cutover escape hatch:

> After June 2, 2026, you can temporarily continue using Node 20 by setting `ACTIONS_ALLOW_USE_UNSECURE_NODE_VERSION=true`, though this will only function until Node 20 is fully removed later that fall.

The `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24` env var can be scoped:

- Workflow-level `env:` block — applies to all jobs/steps in that file
- Job-level `env:` block — applies to a single job
- Runner machine env (self-hosted) — applies to every workflow on that runner

GitHub-hosted runners (`ubuntu-latest`) already have Node 24 available; the env var only switches which runtime the action body executes under.

## Question 2 — Per-action `runs.using` verification

Verified against each repository's `action.yml` `runs.using:` field at the time of writing (April 2026). The "earliest Node-24 major" rule (issue body, Option 1) yields these targets:

| Action | From | Earliest Node-24 major | Verified `runs.using` (action.yml) | Released | Notes |
| --- | --- | --- | --- | --- | --- |
| `actions/checkout` | `v4` | **`v5`** | `node24` | 2025-08 | v5.0.0 release notes: "Update actions checkout to use node 24" — pure runtime bump. v6 also runs on Node 24 but adds an unrelated credential-persist-to-`$RUNNER_TEMP` change that bumps the minimum Actions Runner to 2.329.0; not needed for our usage. |
| `actions/cache` | `v4` | **`v5`** | `node24` | 2025-08 | "`actions/cache@v5` runs on the Node.js 24 runtime and requires a minimum Actions Runner version of 2.327.1." Cache-key format is unchanged from v4; existing caches written by v4 are readable by v5 readers in our usage (same key derivation in `hashFiles('**/Cargo.lock')`). |
| `actions/github-script` | `v7` | **`v8`** | `node24` | 2025-09 | v8 release notes: requires runner ≥2.327.1; **no breaking API changes** documented relative to v7. v9 (2026-04) is ESM-only for `@actions/github` — `require('@actions/github')` fails at runtime, and a script-level `const getOctokit = ...` collision now errors. Our scripts call `await github.rest.issues.createComment(...)` only, so v8 is the safe pick; v9 not chosen. |
| `actions/upload-artifact` | `v4` | **`v6`** | `node24` (default) | 2025-12 | v5 added Node-24 support but kept `runs.using: node20` as default; v6 is the first major where `runs.using: node24` ships in `action.yml`. v7 (2026-02) adds an unrelated `archive: false` flag for direct file uploads — not needed here. |
| `softprops/action-gh-release` | `v2` | **`v3`** | `node24` | 2026-Q1 | Release notes: "Use `v3` on GitHub-hosted runners and self-hosted fleets that already support the Node 24 Actions runtime." All inputs we currently set (`tag_name`, `name`, `prerelease`, `generate_release_notes`, `files`) are present in v3 with identical semantics. v2.6.2 is the final Node-20 major; remaining on v2 is only viable until 2026-09. |

Actions verified to be **out of scope**:

| Action | Type | Why not affected |
| --- | --- | --- |
| `dtolnay/rust-toolchain@stable` | composite (`runs.using: composite`) | Composite actions invoke shell scripts on the runner directly; they have no Node runtime of their own. Unaffected by the deprecation. |
| `taiki-e/install-action@cargo-llvm-cov` | composite | Same as above — used only in `release-erd.yml` to install `cargo-llvm-cov`. |

## Question 3 — `actions/checkout@v5` vs `@v6` selection

`v5` was selected over `v6` (also Node-24-native) because `v6.0.0` includes a non-trivial behavior change:

> Persist creds to a separate file — credentials now store under `$RUNNER_TEMP` rather than in local git config

This is a credential-handling change for Docker container action scenarios and bumps the minimum Actions Runner to 2.329.0. None of our workflows use Docker container actions, but pinning to `v5` gets us off Node 20 with strictly fewer behavioral changes — fewer variables when triaging any post-merge regression. We can revisit `v6` separately when (and if) we have a reason to.

This matches the issue body's "earliest Node-24 major" guidance.

## Question 4 — `actions/github-script@v8` vs `@v9`

`v8` selected over `v9` because v9 introduced two scripted-API changes:

1. `require('@actions/github')` no longer works (the package became ESM-only).
2. A `const getOctokit = ...` declaration in the script body now collides with the new injected `getOctokit` factory.

Our 6 `actions/github-script` invocations across `auto-tag.yml`, `pr-project-status.yml`, and `project-integration.yml` use only the standard injected `github`/`context` API (e.g., `github.rest.issues.createComment(...)`), so v9 would also work — but v8 is the strictly smaller change and matches the "earliest Node-24 major" rule.

## Question 5 — Migration strategy: bump-only vs env-var pre-flight

The issue lists three options:

1. Bump action versions to Node-24 majors (preferred).
2. Set `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24=true` to verify before bumping.
3. Combination — (2) first, then (1).

We adopt **Option 1 directly**, skipping the env-var pre-flight, because:

- The action authors have done the runtime upgrade work; their v5/v6/v8/v3 majors *are* the Node-24-native code paths. Forcing v4/v7/v2 onto Node 24 via the env var would test a code path the authors are not expected to support past 2026-09.
- All five target majors landed >30 days ago and have been adopted by the broader ecosystem (verified via the freyja migration in [freyja#325](https://github.com/TE-ToshiakiTanaka2/freyja/pull/325) which used the same target set).
- Adding the env var temporarily and then removing it doubles the PR review surface for no diagnostic value once we are committed to the bump.
- Workflow-level `env:` does not apply to reusable workflows transparently — downstream consumers calling our workflows would see the runtime they configure, not ours. So even if the env var helped tarnished verify, it wouldn't propagate to freyja.

Mitigation for the lost pre-flight signal: stage the bumps in a single PR but rely on tarnished's own CI (which runs `auto-tag.yml`, `pr-project-status.yml`, and `project-integration.yml` on every push) to surface any regression on the PR itself before merge. This is functionally equivalent to a verification pass.

## Question 6 — Downstream impact (freyja and similar)

tarnished's `.github/workflows/auto-tag.yml`, `pr-project-status.yml`, `project-integration.yml`, and `project-label-routing.yml` are consumed by downstream repos via `workflow_call`:

```yaml
uses: TE-ToshiakiTanaka2/tarnished/.github/workflows/auto-tag.yml@develop
```

When `workflow_call` invokes a reusable workflow, the **callee's** action pins are what execute. So bumping action versions inside tarnished's reusable workflows automatically clears the deprecation warning on every consumer's CI run — no downstream change required.

Confirmed via [freyja#323](https://github.com/TE-ToshiakiTanaka2/freyja/issues/323) / [freyja#325](https://github.com/TE-ToshiakiTanaka2/freyja/pull/325): freyja's own `python-quality-check.yml` migrated three Node-20 actions; the remaining deprecation annotations on freyja's CI runs come from tarnished's reusable workflows (this issue's scope).

The acceptance criterion "at minimum, freyja's calls to `auto-tag.yml`, `pr-project-status.yml`, and `project-integration.yml` keep succeeding after the bump" is achievable with a no-op downstream change set.

## Question 7 — Templates (`templates/github-actions/*`, `templates/languages/*/*.yml`)

Out of scope for #267 (per issue body's "Inventory across all six files in `.github/workflows/`"), but the same Node-20 deprecation applies to:

- `templates/github-actions/auto-tag/.github/workflows/auto-tag.yml`
- `templates/github-actions/project-integration/.github/workflows/{project-integration,pr-project-status,project-label-routing}.yml`
- `templates/languages/python/.github/workflows/python-quality-check.yml` (uses `actions/checkout@v4`, `astral-sh/setup-uv@v5`, `actions/upload-artifact@v4`)
- `templates/languages/node/.github/workflows/node-quality-check.yml` (uses `actions/checkout@v4`, `pnpm/action-setup@v4`, `actions/setup-node@v4`, `actions/upload-artifact@v4`)
- `templates/languages/deno/.github/workflows/deno-quality-check.yml` (uses `actions/checkout@v4`, `denoland/setup-deno@v2`, `actions/upload-artifact@v4`)
- `templates/languages/latex/.github/workflows/build-pdf.yml` (uses `actions/checkout@v4`, `actions/upload-artifact@v4`)
- `templates/languages/rust/.github/workflows/rust-quality-check.yml` (mirror of the root file)

Newly scaffolded downstream projects inherit Node-20 action pins from these templates until the templates are also updated. **Recommendation**: open a follow-up issue to track the template migration, ideally before 2026-06-02 so projects scaffolded between now and then do not start with deprecated pins. The template upgrade is mostly mechanical (the same five action bumps for templates that mirror the root, plus separate verification for `astral-sh/setup-uv`, `pnpm/action-setup`, `actions/setup-node`, `denoland/setup-deno`).

## Sources

- [GitHub blog: Deprecation of Node.js 20 on GitHub Actions runners](https://github.blog/changelog/2025-09-19-deprecation-of-node-20-on-github-actions-runners/) — authoritative timeline + env-var guidance
- [actions/checkout@v5 action.yml](https://raw.githubusercontent.com/actions/checkout/v5/action.yml) — confirmed `runs.using: node24`
- [actions/cache@v5 action.yml](https://raw.githubusercontent.com/actions/cache/v5/action.yml) — confirmed `runs.using: node24`
- [actions/github-script@v8 action.yml](https://raw.githubusercontent.com/actions/github-script/v8/action.yml) — confirmed `runs.using: node24`
- [actions/upload-artifact@v6 action.yml](https://raw.githubusercontent.com/actions/upload-artifact/v6/action.yml) — confirmed `runs.using: node24`
- [softprops/action-gh-release@v3 action.yml](https://raw.githubusercontent.com/softprops/action-gh-release/v3/action.yml) — confirmed `runs.using: node24`, all inputs unchanged
- [actions/checkout releases](https://github.com/actions/checkout/releases) — v5/v6 changelog
- [actions/cache releases](https://github.com/actions/cache/releases) — v5 changelog
- [actions/github-script releases](https://github.com/actions/github-script/releases) — v8/v9 breaking-change details
- [actions/upload-artifact releases](https://github.com/actions/upload-artifact/releases) — v5/v6/v7 runtime details
- [softprops/action-gh-release releases](https://github.com/softprops/action-gh-release/releases) — v3 changelog
- [freyja#325](https://github.com/TE-ToshiakiTanaka2/freyja/pull/325) — sibling-repo precedent for the same migration
