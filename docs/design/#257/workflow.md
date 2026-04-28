# Workflow: #257 Separate shared and issue-specific design artifacts

## Implementation Steps

### Step 1: Define migration skill

- **Action**: Create `_shared/design-migration/SKILL.md` describing the one-shot bootstrap procedure: list existing `docs/design/#{issue}/` directories (handling both `#NNN` and `NNN` naming), read each `design.md`, and synthesize `shared/architecture.md`, `data-model.md`, `api-spec.md`, `class.md`, `sequence.md`. Existing per-issue files MUST be preserved.
- **Files**:
  - `.claude/skills/_shared/design-migration/SKILL.md` (new)
- **Depends on**: nothing
- **Done when**: SKILL.md exists, references `_shared/branch/SKILL.md` style, lists invocation conditions, and specifies that it is idempotent.

### Step 2: Update `/design` skill (in-repo)

- **Action**: Edit `.claude/skills/design/SKILL.md` to:
  1. Add Phase 1.5 "Migration check" referencing `_shared/design-migration`.
  2. Add Phase 2 "Load shared" — read all of `docs/design/shared/*`.
  3. Modify Phase 3 (Research) — distinguish issue-specific (`#{issue}/research.md`) vs cross-cutting (`shared/research/<lib>.md`).
  4. Modify Phase 4 (Design) — write `#{issue}/design.md` with self-contained "Context" section (option b). Class-diagram changes go to `shared/class.md` snapshot, issue-local control flow stays in `#{issue}/flowchart.md`.
  5. Modify Phase 5 (Workflow) — unchanged location (`#{issue}/workflow.md`).
  6. Add Phase 6 "Snapshot" — regenerate `shared/architecture.md`, `data-model.md`, `api-spec.md`, `class.md`, `sequence.md` in full. Explicitly forbid append-style updates (NFR-1).
  7. Update directory-structure illustration, workflow Mermaid graph, commit template, and report template.
- **Files**:
  - `.claude/skills/design/SKILL.md`
- **Depends on**: Step 1 (SKILL.md references the migration skill)
- **Done when**: All FR-3 phases are described in the skill text. The phrase "snapshot" appears with an explicit prohibition on changelog-style updates. The directory illustration shows `shared/` and `#{issue}/`.

### Step 3: Update `/implement` skill (in-repo)

- **Action**: Edit `.claude/skills/implement/SKILL.md` Phase 1 to read both `docs/design/shared/*` and `docs/design/#{issue}/*` instead of just the per-issue directory.
- **Files**:
  - `.claude/skills/implement/SKILL.md`
- **Depends on**: Step 2 (the shared/ structure must be defined before implement can rely on it)
- **Done when**: Phase 1 explicitly mentions both directories. Behavior degrades gracefully when `shared/` is empty (warn, continue).

### Step 4: Mirror skill changes to templates

- **Action**: Apply Steps 1-3 to `templates/claude/.claude/skills/` byte-for-byte. While doing so, also reconcile the pre-existing drift from #248 (`Execute /erd:*` → `Load /erd:* and follow inline`) so that the in-repo and template versions are aligned.
- **Files**:
  - `templates/claude/.claude/skills/_shared/design-migration/SKILL.md` (new)
  - `templates/claude/.claude/skills/design/SKILL.md`
  - `templates/claude/.claude/skills/implement/SKILL.md`
- **Depends on**: Steps 1-3
- **Done when**: `diff -r .claude/skills/ templates/claude/.claude/skills/` returns no output (modulo any deliberate template-only differences, which are explicitly listed in the PR description if present).

### Step 5: Run migration locally and verify

- **Action**: Execute the migration described in Step 1: read `docs/design/{#228,#230,#240,#242,#244,#249,#257,246,255}/design.md` and synthesize `docs/design/shared/*`. Sanity-check the result manually for major omissions.
- **Files**:
  - `docs/design/shared/architecture.md` (new)
  - `docs/design/shared/data-model.md` (new)
  - `docs/design/shared/api-spec.md` (new)
  - `docs/design/shared/class.md` (new)
  - `docs/design/shared/sequence.md` (new)
  - (Optional) `docs/design/shared/research/<library>.md` if any cross-cutting research is identified
- **Depends on**: Step 1
- **Done when**: All five `shared/*` files exist and contain non-trivial synthesized content. Existing `docs/design/#{issue}/` directories are unchanged (verified by `git status`).

### Step 6: Smoke-test against an existing issue

- **Action**: Pick a closed issue that already has design artifacts (e.g., #255). Mentally walk through `/design <closed_issue>` with the new skill text and verify (a) shared/* is read first, (b) the design output makes sense, (c) snapshot regeneration of shared/* would not regress.
- **Files**: (none modified — verification only)
- **Depends on**: Steps 2, 5
- **Done when**: A short note in the PR description confirms the walkthrough succeeded.

### Step 7: Update auxiliary documentation

- **Action**: Search for references to the old `docs/design/#{issue}/` structure in `README.md`, `CLAUDE.md`, and other top-level docs. Update where relevant.
- **Files**:
  - `README.md` (if referenced)
  - `templates/claude/CLAUDE.md` (if referenced)
  - any other doc surfaced by `grep -r "docs/design"`
- **Depends on**: Step 4
- **Done when**: No stale references to the old structure remain.

### Step 8: Commit and PR

- **Action**: Commit changes per the repo's commit-style conventions, push, and open a PR titled `refactor(design): separate shared and issue-specific design artifacts (#257)`.
- **Files**: (none — git operations)
- **Depends on**: Steps 1-7
- **Done when**: PR is open, linked to #257, with description noting (a) migration was run, (b) parity between `.claude/skills/` and `templates/claude/.claude/skills/` is verified, (c) Step 6 walkthrough result.

## Task Dependencies

```
Step 1 ──→ Step 2 ──→ Step 3 ──→ Step 4 ──→ Step 7 ──→ Step 8
   │                                            ↑
   └──→ Step 5 ──→ Step 6 ─────────────────────┘
```

- Steps 1, 5 are independent of Steps 2-3 (skill text vs. data migration); they can run in parallel after Step 1 is done.
- Step 4 must wait for 2 and 3 to be stable (else mirroring will need re-doing).
- Step 6 depends on both Step 2 (skill text) and Step 5 (shared/* exists to test against).

## Test Strategy

### "Tests" for skill / documentation changes

This issue introduces no executable code. Verification is by manual review and walkthrough:

- **Skill self-consistency**: Each `SKILL.md` MUST list its phases coherently, with file destinations matching `api-spec.md`. Reviewer reads the SKILL.md top-to-bottom and confirms.
- **Parity check**: `diff -r .claude/skills/ templates/claude/.claude/skills/` returns no unexpected differences.
- **Migration result review**: A reviewer reads `docs/design/shared/architecture.md` and confirms it accurately reflects the cumulative project state.
- **Walkthrough**: Reviewer mentally runs `/design <some-future-issue>` against the new skill and confirms each phase has a clear instruction.

### Edge cases to cover (in the SKILL.md text)

- **Empty repo** (no prior `#{issue}/` directories) — `shared/*` is created lazily on first `/design`.
- **shared/ exists but partial** (e.g., only `architecture.md`) — `/design` reads what exists, regenerates the missing files at Phase 6.
- **Mixed directory naming** (`#228` vs `246`) — migration reads both formats; new `/design` always uses `#NNN`.
- **Re-running migration** — idempotent; overwrites with latest synthesis.
- **`shared/` content shrinks during snapshot regeneration** (e.g., a class is removed) — explicitly allowed; git history retains the prior state.
