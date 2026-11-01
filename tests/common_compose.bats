#!/usr/bin/env bats

# merge_docker_compose_services must work with the real yq (mikefarah, go-yaml),
# which rejects unrendered `{{NAME}}` placeholders at the start of a line.

load 'libs/bats-support/load'
load 'libs/bats-assert/load'

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

setup() {
    source "${SCRIPT_DIR}/scripts/lib/common.sh"
    TEST_DIR="$(mktemp -d)"
    FAKE_BIN="${TEST_DIR}/bin"
    mkdir -p "$FAKE_BIN"
    # Fake yq: parser-like failure on "{{", otherwise concatenate the inputs
    # (skipping the expression argument).
    cat > "${FAKE_BIN}/yq" <<'YQ'
#!/bin/bash
files=("${@:3}")
for f in "${files[@]}"; do
    if grep -q '{{' "$f"; then
        echo "Error: bad file '$f': go-yaml load error in parser: did not find expected key" >&2
        exit 1
    fi
done
cat "${files[@]}"
YQ
    chmod +x "${FAKE_BIN}/yq"
    printf 'services:\n  app:\n    image: base\n' > "${TEST_DIR}/base.yml"
}

teardown() {
    rm -rf "$TEST_DIR"
}

@test "fake yq reproduces the CI parser failure on raw placeholders" {
    run env PATH="${FAKE_BIN}:${PATH}" yq eval-all 'x' "${SCRIPT_DIR}/templates/services/postgresql/docker-compose.postgresql.yml"
    assert_failure
}

@test "merge_docker_compose_services merges placeholder overlays via yq and keeps placeholders" {
    PATH="${FAKE_BIN}:${PATH}"
    run merge_docker_compose_services "${TEST_DIR}/base.yml" \
        "${SCRIPT_DIR}/templates/services/postgresql/docker-compose.postgresql.yml" "${TEST_DIR}/out.yml"
    assert_success
    run grep -c '{{PROJECT_NAME}}-db:' "${TEST_DIR}/out.yml"
    assert_output "1"
    run grep -c '__TARNISHED_PH_' "${TEST_DIR}/out.yml"
    assert_output "0"
    run bash -c "ls '${TEST_DIR}' | grep -c tmp"
    assert_output "0"
}

@test "merge_docker_compose_services cleans temp files and fails when yq fails" {
    PATH="${FAKE_BIN}:${PATH}"
    printf 'services:\n  {{BAD\n' > "${TEST_DIR}/bad.yml"
    printf '#!/bin/bash\nexit 1\n' > "${FAKE_BIN}/yq"
    run merge_docker_compose_services "${TEST_DIR}/base.yml" "${TEST_DIR}/bad.yml" "${TEST_DIR}/out.yml"
    assert_failure
    run bash -c "ls '${TEST_DIR}' | grep -c tmp"
    assert_output "0"
}

@test "service scaffold with yq on PATH renders compose without placeholders" {
    local dest="${TEST_DIR}/ci-postgresql"
    mkdir -p "$dest"
    cd "$dest"
    run env PATH="${FAKE_BIN}:${PATH}" bash "${SCRIPT_DIR}/setup.sh" --postgresql -y ci-postgresql
    assert_success
    run grep -c '{{' "${dest}/docker-compose.yml"
    assert_output "0"
    run grep -c '^  ci-postgresql-db:' "${dest}/docker-compose.yml"
    assert_output "1"
}
