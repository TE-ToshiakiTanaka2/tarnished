# Research: mise (runtime manager)

Cross-cutting research introduced by #325 and extended by #331. mise replaces
devcontainer `features` as the source of every language runtime in generated
projects, so every language plugin and the core Dockerfile depend on the facts
below.

Findings 1–9 were read on 2026-11-01. Findings 10–12 were read, and verified
by installing with mise 2026.10.25 in an isolated `MISE_DATA_DIR`, on
2026-11-03 (#331). Sources are the mise documentation
(`https://github.com/jdx/mise/tree/main/docs`, rendered at
`https://mise.jdx.dev`). Version numbers quoted here are observations at those
dates, not pins; the pins live in `templates/core/docker/Dockerfile.dev` and the
generated `mise.toml`.

## Executive Summary

mise reads a project-root `mise.toml` (and, natively, asdf's `.tool-versions`),
installs each declared tool into a per-user data directory, and exposes it
either through PATH activation (interactive shells) or through shims
(non-interactive processes). It installs Node.js from official binaries with
checksum + OpenPGP verification, Python from precompiled
python-build-standalone builds with artifact attestation, Rust through rustup,
and Go/Deno/uv/pnpm as standalone binaries. mise itself ships as a single static
binary per platform, with a minisign-signed `SHASUMS256.txt` per release.
Tools without a suitable registry entry can be declared through the `github`
and `pypi` backends. A `[tool_alias]` entry gives such a tool a bare name, and
backend options (asset selection, executable renaming, a private Python) ride
on the ordinary `[tools]` entry.

## Findings

### 1. Installing mise in a Dockerfile

- **Details**: Release assets are raw executables named
  `mise-v<version>-<platform>` with platforms `linux-x64`, `linux-arm64`
  (glibc 2.18+) and `-musl` static variants. Each release ships
  `SHASUMS256.txt`, signed with minisign (`SHASUMS256.txt.minisig`) and GPG
  (`SHASUMS256.asc`). The documented verification is
  `minisign -Vm SHASUMS256.txt -P RWTC3g8W3z4RZK3V3qv7fa1QY4JEWyBtqIHW+85QlJpZc5yG+uNYNBSZ`
  followed by `sha256sum -c` on the matching line. The `mise.run` install
  script accepts `MISE_VERSION=v<ver>` and verifies against `SHASUMS256.txt`,
  but only checksums (no signature check for non-embedded versions) and it is a
  `curl | sh`. Debian 11+ can use `extrepo enable mise` (signed apt repo), but
  that repository tracks the newest release, so it cannot honour an
  `ARG MISE_VERSION` pin. Official container images exist
  (`ghcr.io/jdx/mise`, amd64 + arm64) for `COPY --from`, pinned by tag/digest.
  Latest release observed: `v2026.10.25` (2026-10-31).
- **Source**: `docs/installing-mise.md` (sections "mise.run", "apt",
  "Containers", "Manual download"); `docs/mise-cookbook/docker.md`.
- **Relevance**: FR-2 / NFR-1 require `ARG MISE_VERSION`; NFR-4 requires a
  signed repo or a checksum-verified download; NFR-5 requires amd64 + arm64.
  The direct-download + minisign route is the only one meeting all three
  without a second pin (digest) to keep in sync. `minisign` is packaged in
  Debian trixie (`minisign 0.12-1`).

### 2. Data directory, shims and activation

- **Details**: Default data dir is `~/.local/share/mise`; shims live in
  `~/.local/share/mise/shims`. A shim "reads the config for the current
  directory, picks the version, sets that project's `[env]` variables, and runs
  the real executable." `mise activate bash` (in `~/.bashrc`) prepends each
  selected tool's `bin` directory and exports `[env]` at each prompt; it also
  keeps the shim directory on PATH. Shims are the documented mechanism "for
  programs that do not start from" an interactive shell. Reading an `[env]`
  variable *in the shell itself* requires activation; running a tool through a
  shim applies `[env]` to that tool.
- **Caveat**: with `not_found_auto_install` on (default), a shim whose tool
  version is missing installs it; with `not_found_system_fallback` it may run
  an unrelated system binary of the same name. A shim for a command that no
  longer exists in the *selected* version (e.g. an npm global after a Node
  bump) fails at run time even though `command -v` still finds the shim.
- **Source**: `docs/dev-tools/shims.md` ("Shims vs PATH activation",
  "Environment variables", "Add shims to PATH").
- **Relevance**: FR-2 acceptance (`bash -c 'node --version'`) and FR-4
  (`claude` / `codex` from non-login `post.sh`) are both met by putting the
  shim directory on `ENV PATH`; interactive shells additionally get
  `mise activate bash`. Install probes must execute the command
  (`<cmd> --version`) rather than rely on `command -v`.

### 3. System installs vs per-user installs in dev containers

- **Details**: The cookbook notes that dev containers which mount the whole
  home directory hide build-time installs in `~/.local/share/mise`, and
  recommends `mise install --system` (`/usr/local/share/mise/installs`) for that
  case.
- **Source**: `docs/mise-cookbook/docker.md` ("Dev containers").
- **Relevance**: Tarnished's `docker-compose.yml` mounts only individual files
  under `/home/vscode` (`.bash_history`, `.gitconfig.local`, `.config/gh`),
  so per-user installs are not hidden. Per-user installs are required anyway:
  `npm install -g` writes into the active Node's install directory, and only a
  user-owned install lets it run without sudo (NFR-4, FR-4).

### 4. Trust

- **Details**: Config files that use templates, `[env]` directives beyond
  plain values, or non-string tool options need trust. `mise install`,
  `mise exec`, `mise run` "trust their active config automatically" (outside
  paranoid mode). `trusted_config_paths` (env `MISE_TRUSTED_CONFIG_PATHS`)
  trusts every config under the listed paths. Trust in a main checkout extends
  to its git worktrees.
- **Source**: `docs/cli/trust.md`, `docs/configuration.md`.
- **Relevance**: the python plugin writes
  `UV_PYTHON = { value = "{{ tools.python.path }}", tools = true }`, which
  needs trust before shims apply it. Setting
  `ENV MISE_TRUSTED_CONFIG_PATHS=/workspace` in the image trusts the
  bind-mounted project for every process; `mise install` in the build and in
  `post.sh` would also self-trust.

### 5. Node.js

- **Details**: Downloads official nodejs.org archives, checks
  `SHASUMS256.txt` and its OpenPGP signature (`node.gpg_verify`), then runs
  `node -v` / `npm -v`. `npm install -g` installs into the active Node version
  (unless `.npmrc` sets `prefix`), so global commands disappear after a version
  switch. On Linux mise replaces each version's `bin/npm` with a wrapper that
  runs `mise reshim` after global installs (`node.npm_shim`, default on).
  pnpm can be a standalone mise tool; Corepack is not needed
  (`node.corepack` default false). `node.default_packages_file` is deprecated.
- **Source**: `docs/lang/node.md` ("Global npm packages", "How mise installs
  Node.js", "Corepack").
- **Relevance**: FR-4 (npm prefix decision), FR-3 ordering (Node bump must
  re-run CLI installs), FR-5 (pnpm as a tool).

### 6. Python and uv

- **Details**: Precompiled CPython from python-build-standalone by default
  (GitHub artifact attestation verified; no compiler needed); `python.compile`
  forces source builds. uv is a registry tool (`mise use uv`). To make
  `uv sync` / `uv run` use mise's interpreter:
  `[env] UV_PYTHON = { value = "{{ tools.python.path }}", tools = true }`.
  `python.uv_venv_auto = "source" | "create|source"` activates a uv project's
  `.venv` when a `uv.lock` exists; the boolean form is deprecated (removed in
  2027.7.0).
- **Source**: `docs/lang/python.md` ("uv projects", "How mise installs
  Python").
- **Relevance**: decides #325 Open Question (a); see design.md.

### 7. Rust

- **Details**: Installed through rustup (mise installs rustup when needed).
  `rust = { version = "stable", components = [...], profile = "..." }` is
  supported; `stable` tracks rustup's channel. mise sets `RUSTUP_TOOLCHAIN`,
  which outranks `rust-toolchain.toml` unless
  `idiomatic_version_file_enable_tools` includes `rust`. `cargo install`
  binaries land in `$CARGO_HOME/bin` (default `~/.cargo/bin`).
- **Source**: `docs/lang/rust.md`.
- **Relevance**: FR-5 default `rust stable`; the old feature's `default`
  profile shipped rustfmt and clippy, so the entry lists both components. The
  workspace keeps `rust-toolchain.toml`; its `mise.toml` must agree with it.

### 8. Go and Deno

- **Details**: Go archives come from `go.download_mirror` with checksum
  verification; mise sets `GOROOT` and `GOBIN` (the selected version's `bin`),
  so `go install` binaries belong to one Go version. Deno: mise sets
  `DENO_INSTALL_ROOT` per version; checksums are verified. Current releases
  observed: Go `1.27.3`, Deno `2.9.8`, uv `0.13.6`, pnpm `12.16.1`.
- **Source**: `docs/lang/go.md`, `docs/lang/deno.md`; release listings
  (`go.dev/dl/?mode=json`, GitHub releases API).
- **Relevance**: FR-5 pins; `post.sh` language blocks that run
  `go install` / `cargo install` should `mise reshim` so the new commands are
  reachable from non-interactive shells.

### 9. GitHub API rate limits during `mise install`

- **Details**: Several backends resolve versions and download assets through
  the GitHub API, whose anonymous rate limit returns `403 Forbidden` once
  exhausted. mise reads `MISE_GITHUB_TOKEN`, and an existing `GITHUB_TOKEN`
  "also works unless a higher-priority source is set". mise does not read
  `GH_TOKEN` itself.
- **Source**: `docs/dev-tools/github-tokens.md`.
- **Relevance**: CI builds (FR-12) pass the workflow token as a BuildKit secret
  so `mise install` is not throttled; local builds work without it.
  `jdx/mise-action` passes `github.token` to mise by default (#331 CI).

### 10. `github` backend: asset selection and executable naming (#331)

- **Details**: `github:<owner>/<repo>` installs a release asset.
  - **Asset selection**: `asset_pattern` (a glob over the whole name, and a
    Tera template with `{{ version }}`, `{{ os() }}` and
    `{{ arch(x64=…, arm64=…) }}`) replaces autodetection. When it matches
    several assets the shortest name wins, so a too-broad pattern can select
    the wrong architecture.
  - **Extraction**: an archive with a single top-level directory is stripped
    one level automatically. The install directory goes on `PATH` when it
    directly holds an executable.
  - **Renaming**: `rename_exe = { "<glob>" = "<name>" }` renames an
    executable after extraction and restores the executable bit that zip
    files drop. The string form picks "the first executable" when no name
    matches the repo, which is unsafe when the archive carries executable
    data files.
  - **Versions and verification**: the version is the tag minus a leading
    `v`. Downloads are checked against the digest GitHub reports, or a
    checksum file in the release.
  - **Trust**: non-string options need a trusted config.
  - **ubi**: the `ubi:` backend is deprecated (warning since 2026.4.0,
    removal in 2027.1.0) in favour of `github`.

  Verified: the Godot .NET editor
  (`Godot_v4.7.2-stable_mono_linux_x86_64.zip`) installed with
  `asset_pattern` + table-form `rename_exe` as `godot` beside its
  `GodotSharp/` directory, and ran through the shim.
- **Source**: `docs/dev-tools/backends/github.md`, `docs/dev-tools/backends/ubi.md`.
- **Relevance**: The way to install a runtime that the registry shorthand
  cannot express, without moving the pin into `Dockerfile.dev`.

### 11. `pypi` (alias `pipx`) backend and private Python (#331)

- **Details**: `pypi:<pkg>` installs a PyPI application into its own venv
  with `uv tool install`, or with pipx when uv is absent. It needs `uv` (or
  `pipx`) in the config, and mise installs those first.
  - **Interpreter**: without a mise-managed Python, uv downloads its own
    newest CPython (observed: 3.15.2 into `~/.local/share/uv/python`, with
    an sdist build for a dependency that had no wheel yet).
  - **Per-tool `python` option**: `python = "3.12"` makes mise install that
    CPython "as a private dependency of the tool", without adding `python`
    to the active tools. A `python` shim is still created, and it errors as
    "not active" in a project without a `python` tool.
  - **Executables**: the package's console scripts become shims.
- **Source**: `docs/dev-tools/backends/pypi.md` (Requirements, Choosing Python).
- **Relevance**: PyPI-distributed CLIs (gdtoolkit) can be installed without
  the python flavor and with a pinned interpreter.

### 12. `[tool_alias]` (#331)

- **Details**: `[tool_alias] <name> = "<backend>:<id>"` points a tool name at
  a backend. The `[tools] <name>` entry then carries the version and backend
  options, and two aliases may target the same repository with different
  asset filters. `[alias]` is the deprecated old spelling. An alias also
  overrides a registry shorthand of the same name.
- **Source**: `docs/dev-tools/aliases.md`.
- **Relevance**: It keeps `mise.toml` keys bare, which is what
  `mise_toml_ensure` accepts. It also means an alias changes the meaning of
  an existing `[tools]` entry, so a plugin must add an alias only together
  with the tool entry it introduces (`mise_toml_has_key`).

## Comparison: how to install mise in the image

| Option | Pin via `ARG MISE_VERSION` | Integrity | arm64 | Verdict |
| --- | --- | --- | --- | --- |
| GitHub release binary + minisign-verified `SHASUMS256.txt` | Yes | Signature + checksum | Yes (`linux-arm64`) | **Chosen** |
| `mise.run` script with `MISE_VERSION` | Yes | Checksum only for non-embedded versions; `curl \| sh` | Yes | Rejected: weaker, less auditable |
| Debian `extrepo` apt repo | No (tracks newest) | Signed repo | Yes | Rejected: breaks NFR-1 pin |
| `COPY --from=ghcr.io/jdx/mise:<tag>` | Tag only unless digest is also pinned | Content-addressed only with digest | Yes | Rejected: needs a second pin to be verifiable |

## Recommendations

1. Install mise to `/usr/local/bin/mise` as root from the release binary,
   verifying `SHASUMS256.txt.minisig` with the published public key and the
   binary's sha256. Map `dpkg --print-architecture` `amd64`→`linux-x64`,
   `arm64`→`linux-arm64`; fail the build on any other architecture.
2. Install runtimes as the `vscode` user into the default per-user data
   directory, put `~/.local/share/mise/shims` on `ENV PATH`, append
   `eval "$(mise activate bash)"` to `~/.bashrc`, and set
   `MISE_TRUSTED_CONFIG_PATHS=/workspace`.
3. Keep `npm install -g` on mise's per-version prefix and re-run the CLI
   installers after `mise install` in `post.sh`.
4. Probe installed commands by running them, not with `command -v`.
5. For a tool the registry shorthand cannot express, use
   `[tool_alias] <name> = "github:…"` or `"pypi:…"` and put the backend
   options on `[tools] <name>`. Write the alias only when the tool entry is
   new. Give `pypi` tools an explicit `python = "<minor>"`.

## Sources

- https://mise.jdx.dev/installing-mise.html
- https://mise.jdx.dev/dev-tools/shims.html
- https://mise.jdx.dev/cli/trust.html
- https://mise.jdx.dev/configuration.html
- https://mise.jdx.dev/mise-cookbook/docker.html
- https://mise.jdx.dev/lang/node.html
- https://mise.jdx.dev/lang/python.html
- https://mise.jdx.dev/lang/rust.html
- https://mise.jdx.dev/lang/go.html
- https://mise.jdx.dev/lang/deno.html
- https://mise.jdx.dev/dev-tools/github-tokens.html
- https://mise.jdx.dev/dev-tools/backends/github.html
- https://mise.jdx.dev/dev-tools/backends/pypi.html
- https://mise.jdx.dev/dev-tools/backends/ubi.html
- https://mise.jdx.dev/dev-tools/aliases.html
- https://mise.jdx.dev/lang/dotnet.html
- https://packages.debian.org/trixie/minisign
