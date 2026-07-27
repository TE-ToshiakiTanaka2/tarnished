# Workflow: #310 Make `/flow` reachable from a raw requirement

Dependency-ordered plan. Three authored files, each mirrored into `templates/` in the same commit; `scripts/verify-mirrors.sh` is the completion criterion throughout.

## Step 1 — Stage 1 ordered resolution (`.claude/skills/flow/SKILL.md`)

**Depends on**: nothing. Everything else assumes this shape.

- Replace the single resolution sentence at `:37` with the four-rule precedence list, `--from issue` first.
- Add the `--from issue` + `--issue N` contradiction rule.

**Done when**: `--from issue` reaches the issue stage without ever being asked for a number, and no-args reaches a two-way choice rather than a bare number prompt.

## Step 2 — Stage 2 carve-out and derivation row

**Depends on**: Step 1.

- Scope the branch resolve/fetch/checkout preamble (`:45`) to the number-carrying path.
- Add the derivation row: no number, requirement-first chosen → entry `issue`.
- State that the `issue` stage has no prerequisites, so the `--from` "prerequisites absent → stop" rule (`:65`) cannot dead-end it.
- Confirm task tracking (`:67`) stays live on both paths.

**Done when**: no step in Stage 2 presupposes a number on the requirement-first path.

## Step 3 — Issue → design approval gate (Stage 4)

**Depends on**: Steps 1-2.

- Add the gate after `/issue` returns, presenting the delta beyond the requirements summary already approved inside `/issue`, and offering "edit the issue, then proceed".
- Document the resume asymmetry against the design gate, with its reason.

**Done when**: the gate exists, its skip-on-resume behavior is stated, and the asymmetry reads as a decision.

## Step 4 — Remaining Claude-side surfaces

**Depends on**: Steps 1-3.

- Frontmatter description (`:3`): include the issue entry.
- Usage block: add a requirement-first example; reword `:21`.
- Error Handling (`:119`): align with the two-way choice.

**Done when**: nothing in the file still describes the lifecycle as starting at `design`.

## Step 5 — Codex projection parity

**Depends on**: Steps 1-4.

- `.agents/skills/flow/SKILL.md`: description (`:3`), Overview (`:10`), step 3 ordered resolution (`:17`), `$issue` in the step 6 list (`:19`), both gates in step 7 (`:20`).

**Done when**: the projection describes the same entry points and the same two gates as the operational spec.

## Step 6 — Contract layer

**Depends on**: Step 5.

- `.tarnished/workflows/flow.md`: state the issue entry and both approval gates at agent-neutral altitude.
- Correct the PR-state drift at `:21` — "pull request exists → nothing to do" versus the SKILL's open / merged / closed-unmerged distinction. Both landed in `292191c`; the SKILL was updated for the #308 Codex review finding and the contract was not.

**Done when**: the contract and the SKILL agree on entry points, gates, and PR states.

## Step 7 — Shared snapshot and mirrors

**Depends on**: all.

- Update `docs/design/shared/api-spec.md`'s lifecycle argument-surface entry with the resolution precedence.
- Mirror the three authored files into `templates/`.
- `bash scripts/verify-mirrors.sh`.

**Done when**: all mirror pairs are byte-identical.

## Step 8 — Verification

**Depends on**: all.

- `scripts/verify-mirrors.sh`
- `bats tests/*.bats`, `cargo fmt --check`, `cargo clippy -- -D warnings`, `cargo test` — expected unchanged, since this issue touches no executable code; run them to confirm exactly that.

**Done when**: no regression against the pre-change baseline.

## Test Strategy

No executable surface changes, so there is no new automated coverage to add. The invariant these files carry is mirror byte-identity, enforced by `verify-mirrors.sh` in CI via `asset-parity.yml`.

The behavioral claims are verified by tracing these invocations against the final text. Each must reach its intended entry without a spurious prompt, and none may run a stage before a gate that precedes it:

1. `/flow` — no arguments, from `develop`
2. `/flow --from issue`
3. `/flow --issue N` — from an unrelated branch
4. `/flow` — from a branch named `.../#<n>/...`
5. `/flow --from issue --issue N` — contradictory pair
6. `/flow --from implement` — forced later stage, no issue number
7. `/flow --from review` — issue exists, no review artifact yet
8. `/flow --issue N` — where N was already completed and its branch deleted by a merge

Cases 5-8 are the ones that expose ordering and short-circuit defects; the first four are the happy paths. This trace is the review's job and is enumerated here so it is not narrowed.
