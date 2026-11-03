#!/usr/bin/env bats

# Unit tests for the #325 install-contract helpers in scripts/lib/common.sh:
# mise_toml_ensure and dockerfile_add_os_packages.

load 'libs/bats-support/load'
load 'libs/bats-assert/load'

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

setup() {
    # shellcheck disable=SC1091
    source "${SCRIPT_DIR}/scripts/lib/common.sh"
    SCRATCH="$(mktemp -d)"
    export SCRATCH
    TOML="$SCRATCH/mise.toml"
}

teardown() {
    chmod -R u+w "$SCRATCH" 2>/dev/null || true
    case "${SCRATCH:-}" in
        /tmp/*) rm -rf "$SCRATCH" ;;
    esac
}

# --- mise_toml_ensure --------------------------------------------------------

@test "mise_toml_ensure creates a missing file with the header" {
    run mise_toml_ensure "$TOML" tools node '"22"'
    assert_success
    run head -n 1 "$TOML"
    assert_output --partial "Runtime versions"
    run grep -c '^\[tools\]$' "$TOML"
    assert_output "1"
    run grep -x 'node = "22"' "$TOML"
    assert_success
}

@test "mise_toml_ensure adds a key to an existing section after its last entry" {
    printf '[tools]\nnode = "22"\n\n[env]\nFOO = "1"\n' > "$TOML"
    run mise_toml_ensure "$TOML" tools uv '"0.13.6"'
    assert_success
    run cat "$TOML"
    assert_output $'[tools]\nnode = "22"\nuv = "0.13.6"\n\n[env]\nFOO = "1"'
}

@test "mise_toml_ensure appends a missing section" {
    printf '[tools]\nnode = "22"\n' > "$TOML"
    run mise_toml_ensure "$TOML" env PYTHONUNBUFFERED '"1"'
    assert_success
    run cat "$TOML"
    assert_output $'[tools]\nnode = "22"\n\n[env]\nPYTHONUNBUFFERED = "1"'
}

@test "mise_toml_ensure inserts a dotted key beside top-level dotted siblings" {
    printf 'tools.node = "24"\n\n[env]\nFOO = "1"\n' > "$TOML"
    run mise_toml_ensure "$TOML" tools pnpm '"10"'
    assert_success
    run cat "$TOML"
    assert_output $'tools.node = "24"\ntools.pnpm = "10"\n\n[env]\nFOO = "1"'
    run grep -c '^\[tools\]' "$TOML"
    assert_output "0"
    run python3 -I -c 'import tomllib,sys; d=tomllib.loads(open(sys.argv[1]).read()); assert d["tools"]=={"node":"24","pnpm":"10"}' "$TOML"
    assert_success
}

@test "mise_toml_ensure treats a literal-quoted key as present" {
    printf "[tools]\n'node' = \"24\"\n" > "$TOML"
    cp "$TOML" "$SCRATCH/before"
    run mise_toml_ensure "$TOML" tools node '"22"'
    assert_success
    assert_output --partial "Kept existing"
    run cmp "$TOML" "$SCRATCH/before"
    assert_success
}

@test "mise_toml_ensure treats a literal-quoted dotted key as present" {
    printf "tools.'node' = \"24\"\n" > "$TOML"
    cp "$TOML" "$SCRATCH/before"
    run mise_toml_ensure "$TOML" tools node '"22"'
    assert_success
    run cmp "$TOML" "$SCRATCH/before"
    assert_success
}

@test "mise_toml_ensure keeps a user-changed value byte-identical" {
    printf '[tools]\nnode = "24"\n' > "$TOML"
    cp "$TOML" "$SCRATCH/before"
    run mise_toml_ensure "$TOML" tools node '"22"'
    assert_success
    assert_output --partial "Kept existing"
    run cmp "$TOML" "$SCRATCH/before"
    assert_success
}

@test "mise_toml_ensure detects a quoted key" {
    printf '[tools]\n"node" = "24"\n' > "$TOML"
    cp "$TOML" "$SCRATCH/before"
    run mise_toml_ensure "$TOML" tools node '"22"'
    assert_success
    run cmp "$TOML" "$SCRATCH/before"
    assert_success
}

@test "mise_toml_ensure detects the [tools.node] table form" {
    printf '[tools.node]\nversion = "24"\n' > "$TOML"
    cp "$TOML" "$SCRATCH/before"
    run mise_toml_ensure "$TOML" tools node '"22"'
    assert_success
    run cmp "$TOML" "$SCRATCH/before"
    assert_success
}

@test "mise_toml_ensure detects a top-level dotted key" {
    printf 'tools.node = "24"\n' > "$TOML"
    cp "$TOML" "$SCRATCH/before"
    run mise_toml_ensure "$TOML" tools node '"22"'
    assert_success
    run cmp "$TOML" "$SCRATCH/before"
    assert_success
}

@test "mise_toml_ensure does not count a commented-out entry as present" {
    printf '[tools]\n# node = "20"\n' > "$TOML"
    run mise_toml_ensure "$TOML" tools node '"22"'
    assert_success
    run grep -x 'node = "22"' "$TOML"
    assert_success
    run grep -x '# node = "20"' "$TOML"
    assert_success
}

@test "mise_toml_ensure does not mistake the same key in another section" {
    printf '[env]\nnode = "x"\n' > "$TOML"
    run mise_toml_ensure "$TOML" tools node '"22"'
    assert_success
    run cat "$TOML"
    assert_output $'[env]\nnode = "x"\n\n[tools]\nnode = "22"'
}

@test "mise_toml_ensure writes inline-table values verbatim" {
    local v='{ version = "stable", components = ["rustfmt", "clippy"] }'
    run mise_toml_ensure "$TOML" tools rust "$v"
    assert_success
    run grep -xF "rust = ${v}" "$TOML"
    assert_success
}

@test "mise_toml_ensure is byte-identical on a second call" {
    mise_toml_ensure "$TOML" tools node '"22"'
    mise_toml_ensure "$TOML" env UV_LINK_MODE '"copy"'
    cp "$TOML" "$SCRATCH/before"
    run mise_toml_ensure "$TOML" tools node '"22"'
    assert_success
    run mise_toml_ensure "$TOML" env UV_LINK_MODE '"copy"'
    assert_success
    run cmp "$TOML" "$SCRATCH/before"
    assert_success
}

@test "mise_toml_ensure handles a file without a trailing newline" {
    printf '[tools]\nnode = "22"' > "$TOML"
    run mise_toml_ensure "$TOML" tools uv '"1"'
    assert_success
    run cat "$TOML"
    assert_output $'[tools]\nnode = "22"\nuv = "1"'
}

@test "mise_toml_ensure preserves comments and CRLF endings" {
    printf '# top\r\n[tools]\r\nnode = "22"\r\n' > "$TOML"
    run mise_toml_ensure "$TOML" tools uv '"1"'
    assert_success
    run grep -c $'\r$' "$TOML"
    assert_output "4"
    run grep -c '^# top' "$TOML"
    assert_output "1"
}

@test "mise_toml_ensure rejects bad input and leaves the file unchanged" {
    printf '[tools]\nnode = "22"\n' > "$TOML"
    cp "$TOML" "$SCRATCH/before"
    run mise_toml_ensure "$TOML" bogus node '"22"'
    assert_failure
    run mise_toml_ensure "$TOML" tools 'bad key' '"22"'
    assert_failure
    run mise_toml_ensure "$TOML" tools go ''
    assert_failure
    run mise_toml_ensure "$TOML" tools go $'"a"\n"b"'
    assert_failure
    run cmp "$TOML" "$SCRATCH/before"
    assert_success
}

@test "mise_toml_ensure fails without touching the original when the directory is read-only" {
    [[ "$(id -u)" != "0" ]] || skip "root ignores directory permissions"
    printf '[tools]\nnode = "22"\n' > "$TOML"
    mkdir "$SCRATCH/ro"
    cp "$TOML" "$SCRATCH/ro/mise.toml"
    cp "$TOML" "$SCRATCH/before"
    chmod 555 "$SCRATCH/ro"
    run mise_toml_ensure "$SCRATCH/ro/mise.toml" tools uv '"1"'
    assert_failure
    run cmp "$SCRATCH/ro/mise.toml" "$SCRATCH/before"
    assert_success
}

@test "mise_toml_ensure accepts the tool_alias section and appends to it" {
    printf '[tools]\nnode = "22"\n' > "$TOML"
    run mise_toml_ensure "$TOML" tool_alias godot '"github:godotengine/godot"'
    assert_success
    run mise_toml_ensure "$TOML" tool_alias gdtoolkit '"pypi:gdtoolkit"'
    assert_success
    run cat "$TOML"
    assert_output $'[tools]\nnode = "22"\n\n[tool_alias]\ngodot = "github:godotengine/godot"\ngdtoolkit = "pypi:gdtoolkit"'
}

@test "mise_toml_ensure keeps an existing tool_alias key" {
    printf '[tool_alias]\ngodot = "aqua:godotengine/godot"\n' > "$TOML"
    cp "$TOML" "$SCRATCH/before"
    run mise_toml_ensure "$TOML" tool_alias godot '"github:godotengine/godot"'
    assert_success
    run cmp "$TOML" "$SCRATCH/before"
    assert_success
}

# --- mise_toml_has_key -------------------------------------------------------

@test "mise_toml_has_key finds bare, quoted, table and dotted-key forms" {
    printf '[tools]\ngodot = "4"\n"dotnet" = "10"\n'"'uv'"' = "1"\n\n[tools.gdtoolkit]\nversion = "4"\n' > "$TOML"
    run mise_toml_has_key "$TOML" tools godot
    assert_success
    run mise_toml_has_key "$TOML" tools dotnet
    assert_success
    run mise_toml_has_key "$TOML" tools uv
    assert_success
    run mise_toml_has_key "$TOML" tools gdtoolkit
    assert_success
    printf 'tools.godot = "4"\n' > "$TOML"
    run mise_toml_has_key "$TOML" tools godot
    assert_success
    assert_output ""
}

@test "mise_toml_has_key returns 1 for absent, other-section, commented and missing" {
    printf '[tools]\nnode = "22"\n# godot = "4"\n\n[env]\ngodot = "x"\n' > "$TOML"
    run mise_toml_has_key "$TOML" tools godot
    assert_failure 1
    assert_output ""
    run mise_toml_has_key "$SCRATCH/nope.toml" tools godot
    assert_failure 1
    [[ ! -e "$SCRATCH/nope.toml" ]]
}

@test "mise_toml_has_key returns 2 for a bad section or key" {
    printf '[tools]\n' > "$TOML"
    run mise_toml_has_key "$TOML" bogus godot
    assert_failure 2
    run mise_toml_has_key "$TOML" tools 'bad key'
    assert_failure 2
}

# --- dockerfile_add_os_packages ---------------------------------------------

_fixture_dockerfile() {
    cat > "$SCRATCH/Dockerfile" <<'EOF'
FROM debian:trixie-slim
RUN echo base

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
# >>> mise runtimes >>>
RUN echo mise
# <<< mise runtimes <<<
EOF
}

@test "dockerfile_add_os_packages inserts a marker block above SHELL" {
    _fixture_dockerfile
    run dockerfile_add_os_packages "$SCRATCH/Dockerfile" postgresql postgresql-client
    assert_success
    local open shell
    open="$(grep -n '^# >>> postgresql os-packages >>>$' "$SCRATCH/Dockerfile" | cut -d: -f1)"
    shell="$(grep -n '^SHELL ' "$SCRATCH/Dockerfile" | cut -d: -f1)"
    [[ -n "$open" ]]
    [[ "$open" -lt "$shell" ]]
    run grep -c '^    postgresql-client \\$' "$SCRATCH/Dockerfile"
    assert_output "1"
    run grep -c '^# <<< postgresql os-packages <<<$' "$SCRATCH/Dockerfile"
    assert_output "1"
}

@test "dockerfile_add_os_packages is idempotent" {
    _fixture_dockerfile
    dockerfile_add_os_packages "$SCRATCH/Dockerfile" mysql default-mysql-client
    cp "$SCRATCH/Dockerfile" "$SCRATCH/before"
    run dockerfile_add_os_packages "$SCRATCH/Dockerfile" mysql default-mysql-client
    assert_success
    run cmp "$SCRATCH/Dockerfile" "$SCRATCH/before"
    assert_success
}

@test "dockerfile_add_os_packages supports several packages and coexists with other blocks" {
    _fixture_dockerfile
    dockerfile_add_os_packages "$SCRATCH/Dockerfile" a pkg-one pkg-two
    dockerfile_add_os_packages "$SCRATCH/Dockerfile" b pkg-three
    run grep -c 'os-packages >>>$' "$SCRATCH/Dockerfile"
    assert_output "2"
    run grep -c '^SHELL ' "$SCRATCH/Dockerfile"
    assert_output "1"
    run grep -c '^    pkg-two \\$' "$SCRATCH/Dockerfile"
    assert_output "1"
}

@test "dockerfile_add_os_packages warns and leaves the file when there is no SHELL line" {
    printf 'FROM debian\nRUN echo hi\n' > "$SCRATCH/Dockerfile"
    cp "$SCRATCH/Dockerfile" "$SCRATCH/before"
    run dockerfile_add_os_packages "$SCRATCH/Dockerfile" mysql default-mysql-client
    assert_success
    assert_output --partial "default-mysql-client"
    run cmp "$SCRATCH/Dockerfile" "$SCRATCH/before"
    assert_success
}

@test "dockerfile_add_os_packages rejects an invalid block id or no packages" {
    _fixture_dockerfile
    run dockerfile_add_os_packages "$SCRATCH/Dockerfile" 'Bad Id' pkg
    assert_failure
    run dockerfile_add_os_packages "$SCRATCH/Dockerfile" ok
    assert_failure
}

@test "dockerfile_add_os_packages warns and succeeds when the Dockerfile is missing" {
    run dockerfile_add_os_packages "$SCRATCH/nope" mysql default-mysql-client
    assert_success
}
