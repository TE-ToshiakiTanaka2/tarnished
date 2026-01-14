# Implementation Workflow: Fix bats-core Installation

**Issue**: #20
**Branch**: `bugfix/TE-ToshiakiTanaka2/#20/fix-bats-not-installed`

## Phase 1: post.sh Modification

### Task 1.1: Add setup_bats function

**File**: `.devcontainer/scripts/post.sh`

**Steps**:
1. Add `setup_bats()` function after the Test Environment Setup section
2. Function should:
   - Check if bats is already installed
   - Install via apt-get if not present
   - Output status messages

**Acceptance Criteria**:
- [ ] Function handles idempotency (skip if already installed)
- [ ] Uses same installation method as CI (apt-get)
- [ ] Outputs clear status messages

### Task 1.2: Integrate setup_bats call

**Steps**:
1. Call `setup_bats` in the Test Environment Setup section
2. Place before git submodules initialization

**Commit**: `fix(devcontainer): add bats-core installation to post.sh`

---

## Phase 2: Makefile Modification

### Task 2.1: Add ensure-test-deps target

**File**: `Makefile`

**Steps**:
1. Create new target `ensure-test-deps`
2. Check bats command availability
3. Check git submodules initialization
4. Auto-install/init if missing

**Acceptance Criteria**:
- [ ] Checks bats existence silently
- [ ] Checks submodules initialization
- [ ] Installs bats if missing
- [ ] Initializes submodules if missing
- [ ] Provides clear output during installation

### Task 2.2: Update test targets

**Steps**:
1. Add `ensure-test-deps` as prerequisite to `test-unit`
2. Add `ensure-test-deps` as prerequisite to `test-integration`
3. Add `ensure-test-deps` as prerequisite to `test-e2e`

**Commit**: `fix(makefile): add automatic test dependency check`

---

## Phase 3: Verification

### Task 3.1: Test bats installation

**Steps**:
1. Verify `bats --version` works
2. Run `make test-unit` and verify success
3. Run `make test-e2e` and verify success

### Task 3.2: Test fallback mechanism

**Steps**:
1. Simulate missing bats (if possible in current environment)
2. Verify Makefile auto-installs dependencies
3. Verify tests run after auto-install

**Commit**: N/A (verification only)

---

## Phase 4: Documentation

### Task 4.1: Commit design and workflow docs

**Steps**:
1. Add design document to git
2. Add workflow document to git
3. Create documentation commit

**Commit**: `docs: add design and workflow for issue #20`

---

## Execution Order

```
Phase 1.1 → Phase 1.2 → Commit
    ↓
Phase 2.1 → Phase 2.2 → Commit
    ↓
Phase 3.1 → Phase 3.2 → Verify
    ↓
Phase 4.1 → Commit
```

## Dependencies

- Phase 2 can be done independently of Phase 1
- Phase 3 depends on both Phase 1 and Phase 2
- Phase 4 should be done last

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| apt-get requires sudo | Use sudo in both post.sh and Makefile |
| Network issues during install | post.sh already handles network gracefully |
| Submodules not initialized | Check and init in ensure-test-deps |
