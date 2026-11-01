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
    run grep -c 'tarnishedph-' "${TEST_DIR}/out.yml"
    assert_output "0"
    run bash -c "ls '${TEST_DIR}' | grep -c '^out.yml\.'"
    assert_output "0"
}

@test "merge_docker_compose_services cleans temp files and fails when yq fails" {
    PATH="${FAKE_BIN}:${PATH}"
    printf 'services:\n  {{BAD\n' > "${TEST_DIR}/bad.yml"
    printf '#!/bin/bash\nexit 1\n' > "${FAKE_BIN}/yq"
    run merge_docker_compose_services "${TEST_DIR}/base.yml" "${TEST_DIR}/bad.yml" "${TEST_DIR}/out.yml"
    assert_failure
    run bash -c "ls '${TEST_DIR}' | grep -c '^out.yml\.'"
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

# Passthrough yq: identity merge (concatenate), used to test sentinel round-trips.
passthrough_yq() {
    printf '#!/bin/bash\ncat "${@:3}"\n' > "${FAKE_BIN}/yq"
}

@test "sentinel restore is lossless for adjacent placeholders and suffixes" {
    PATH="${FAKE_BIN}:${PATH}"
    passthrough_yq
    printf 'x: {{A}}_{{A}}\ny: {{A}}-{{B}}\nz: {{A}}_suffix\nw: {{A}}{{B}}\n' > "${TEST_DIR}/ov.yml"
    run merge_docker_compose_services "${TEST_DIR}/base.yml" "${TEST_DIR}/ov.yml" "${TEST_DIR}/out.yml"
    assert_success
    run grep -F -x -e 'x: {{A}}_{{A}}' -e 'y: {{A}}-{{B}}' -e 'z: {{A}}_suffix' -e 'w: {{A}}{{B}}' "${TEST_DIR}/out.yml"
    assert_success
    assert_equal "${#lines[@]}" 4
}

@test "base file without placeholders merges unchanged" {
    PATH="${FAKE_BIN}:${PATH}"
    passthrough_yq
    printf 'k: v\n' > "${TEST_DIR}/ov.yml"
    run merge_docker_compose_services "${TEST_DIR}/base.yml" "${TEST_DIR}/ov.yml" "${TEST_DIR}/out.yml"
    assert_success
    run cat "${TEST_DIR}/out.yml"
    assert_output "$(cat "${TEST_DIR}/base.yml" "${TEST_DIR}/ov.yml")"
}

@test "literal sentinel text in an input falls back to the non-yq merge" {
    PATH="${FAKE_BIN}:${PATH}"
    printf '#!/bin/bash\necho yq-was-called >&2\nexit 1\n' > "${FAKE_BIN}/yq"
    printf 'services:\n  db:\n    image: tarnishedph-NAME-hptarnished\nvolumes:\n  v: {}\n' > "${TEST_DIR}/ov.yml"
    run merge_docker_compose_services "${TEST_DIR}/base.yml" "${TEST_DIR}/ov.yml" "${TEST_DIR}/out.yml"
    assert_success
    assert_output --partial "without yq"
    refute_output --partial "yq-was-called"
    run grep -F 'image: tarnishedph-NAME-hptarnished' "${TEST_DIR}/out.yml"
    assert_success
    run grep -c '{{NAME}}' "${TEST_DIR}/out.yml"
    assert_output "0"
}

@test "failures in any pipeline stage return 1 under set -euo pipefail and leave no temp files" {
    local stage
    for stage in sed1 sed2 yq sed3; do
        rm -f "${TEST_DIR}"/out.yml*
        run bash -c '
            set -euo pipefail
            source "$1/scripts/lib/common.sh"
            stage="$4"
            mkdir -p "$3/fb"
            printf "#!/bin/bash\ncat \"\${@:3}\"\n" > "$3/fb/yq"
            [[ "$stage" == yq ]] && printf "#!/bin/bash\nexit 1\n" > "$3/fb/yq"
            # sed shim: fail the Nth sed call (1=base, 2=overlay, 3=restore)
            n=0
            sed() {
                n=$((n + 1))
                case "$stage:$n" in sed1:1|sed2:2|sed3:3) return 1 ;; esac
                command sed "$@"
            }
            PATH="$3/fb:$PATH"
            printf "a: {{X}}\n" > "$3/ov.yml"
            set +e
            merge_docker_compose_services "$3/base.yml" "$3/ov.yml" "$3/out.yml" > /dev/null 2>&1
            echo "rc=$?"
        ' _ "$SCRIPT_DIR" x "$TEST_DIR" "$stage"
        assert_output "rc=1"
        run bash -c "ls '${TEST_DIR}' | grep -c '^out.yml\.'"
        assert_output "0"
    done
}

@test "real yq v4: core base + postgresql overlay merges and renders to valid compose" {
    command -v yq &> /dev/null || skip "yq not on PATH"
    yq --version | grep -q 'mikefarah' || skip "not mikefarah yq"
    run merge_docker_compose_services "${SCRIPT_DIR}/templates/core/docker-compose.yml" \
        "${SCRIPT_DIR}/templates/services/postgresql/docker-compose.postgresql.yml" "${TEST_DIR}/out.yml"
    assert_success
    run grep -c '{{PROJECT_NAME}}-db:' "${TEST_DIR}/out.yml"
    assert_output "1"
    run grep -c '^  {{PROJECT_NAME}}:' "${TEST_DIR}/out.yml"
    assert_output "1"
    sed 's/{{PROJECT_NAME}}/demo/g' "${TEST_DIR}/out.yml" > "${TEST_DIR}/rendered.yml"
    run yq eval '.services | keys | .[]' "${TEST_DIR}/rendered.yml"
    assert_success
    assert_output --partial "demo-db"
    assert_line "demo"
    local overlay_vol
    overlay_vol=$(yq eval '.volumes | keys | .[0]' "${SCRIPT_DIR}/templates/services/postgresql/docker-compose.postgresql.yml" | sed 's/{{PROJECT_NAME}}/demo/g')
    run yq eval '.volumes | keys | .[]' "${TEST_DIR}/rendered.yml"
    assert_output --partial "$overlay_vol"
}
