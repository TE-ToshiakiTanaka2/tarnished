# Research: #325 Claude Code install, declarative plugins, and OS packages

Issue-specific research. The cross-cutting mise findings live in
[`../shared/research/mise.md`](../shared/research/mise.md). Sources were read on
2026-11-01.

## Executive Summary

Claude Code supports `npm install -g @anthropic-ai/claude-code` (Node 22+,
never under sudo). Project settings can declare a marketplace
(`extraKnownMarketplaces`) and enable plugins (`enabledPlugins`), but an
external plugin is **not** downloaded onto a collaborator's machine by that
declaration: each machine still runs `claude plugin install <id> --scope project`
once. The `claude plugin` CLI has script-friendly behaviour (`list --json`,
idempotent `install` with exit 0 when already installed, refusal without a TTY
when a marketplace-declared command needs confirmation). The GitHub CLI's
official apt repository is signed and documents its key fingerprints. Debian
trixie packages `postgresql-client` (17) and `default-mysql-client` (MariaDB
client).

## Findings

### 1. Installing Claude Code with npm

- **Details**: `npm install -g @anthropic-ai/claude-code` is a supported
  install method alongside the native installer. It requires Node.js 22 or
  newer, must not be run with `sudo`, and accepts `@X.Y.Z` to pin a version.
  `DISABLE_AUTOUPDATER=1` turns off background updates. The devcontainer
  feature `ghcr.io/anthropics/devcontainer-features/claude-code:1.0` installs
  its own Node when none is present; `:1.0` pins the feature script, not
  Claude Code itself.
- **Source**: https://code.claude.com/docs/en/setup.md,
  https://code.claude.com/docs/en/troubleshoot-install.md,
  https://code.claude.com/docs/en/devcontainer.md
- **Relevance**: FR-3 / FR-4. Core's `node = "22"` satisfies the minimum. A
  user-writable npm prefix (mise's per-version Node install) keeps both the
  install and Claude's own updater sudo-free. Projects scaffolded before #325
  already have `claude` from the feature, so the new helper must detect and
  skip (NFR-2).

### 2. Declarative plugin settings

- **Details**: `.claude/settings.json` accepts
  `extraKnownMarketplaces: { "<name>": { "source": { "source": "github", "repo": "owner/repo" } } }`
  (also `git` with `url`, plus `ref` / `path`) and
  `enabledPlugins: { "<plugin>@<marketplace>": true }`. Project scope means
  "the entry goes in `.claude/settings.json`, which you commit. Committing that
  entry turns the plugin on for your collaborators but doesn't download it to
  their machines, so each collaborator also runs
  `claude plugin install <name>@<marketplace> --scope project` once." The
  marketplace declaration applies after the folder-trust dialog is accepted.
  `claude-plugins-official` is a reserved marketplace name that is accepted
  only from a `github`/`git` source under `github.com/anthropics/`, which the
  shipped entry satisfies.
- **Source**: https://code.claude.com/docs/en/settings-reference.md,
  https://code.claude.com/docs/en/plugins/install.md,
  https://code.claude.com/docs/en/plugins/marketplace-reference.md
  ("Reserved names"), https://code.claude.com/docs/en/plugins/loading.md
- **Relevance**: FR-7 (keys) and FR-8 (why the fallback script remains).

### 3. `claude plugin` CLI behaviour relevant to scripts

- **Details**:
  - `claude plugin list --json` prints an array of installations whose `id` is
    `name@marketplace` (plus `scope`, `enabled`, `projectEnabled`, …).
  - `claude plugin install <id> --scope project` exits `0` and prints
    `Plugin "<id>" is already installed (scope: project)` when nothing new is
    installed, so install is itself idempotent.
  - If stdin/stdout is not a TTY and a marketplace entry declares an install
    command, the install is refused (exit 1) unless `-y` or
    `--accept-command <sha256>` is passed.
  - On a machine where no interactive session has run, the official
    marketplace is not yet registered, so scripts run
    `claude plugin marketplace add anthropics/claude-plugins-official` first.
  - Exit codes: `0` success, `1` failure for every subcommand.
- **Source**: https://code.claude.com/docs/en/plugins/cli-reference.md,
  https://code.claude.com/docs/en/plugins/install.md ("Install from your shell")
- **Relevance**: FR-8 design. The fallback registers only marketplaces that an
  enabled plugin references (sourced from `extraKnownMarketplaces`), installs
  only ids missing from `list --json`, and never passes `-y` (a
  marketplace-declared command needs a human decision).

### 4. GitHub CLI apt repository

- **Details**: Official instructions download
  `https://cli.github.com/packages/githubcli-archive-keyring.gpg` into
  `/etc/apt/keyrings/` and add
  `deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main`.
  Packages and repository metadata are signed with the key fingerprints
  `2C6106201985B60E6C7AC87323F3D4EA75716059` and
  `7F38BBB59D064DBCB3D84D725612B36462313325`; the docs recommend checking them
  with `gpg --show-keys`. Debian trixie's own `gh` is `2.46.0`.
- **Source**: https://github.com/cli/cli/blob/trunk/docs/install_linux.md,
  https://packages.debian.org/trixie/gh
- **Relevance**: FR-6 / NFR-4 ("third-party apt repos use `signed-by`
  keyrings"). The distribution package is too old to track GitHub API changes,
  so the official repo is used and its keyring fingerprints are checked at
  build time.

### 5. Debian trixie client packages

- **Details**: `postgresql-client` (`17+278`, depends on
  `postgresql-client-17`); `default-mysql-client` (`1.1.1`, a metapackage that
  resolves to the MariaDB client).
- **Source**: https://packages.debian.org/trixie/postgresql-client,
  https://packages.debian.org/trixie/default-mysql-client
- **Relevance**: FR-6 service blocks. The MariaDB client speaks the MySQL
  protocol; the generated `mysql:8.0` service defaults to
  `caching_sha2_password`, so the implementation verifies a login from the
  container once (recorded as a risk in design.md). CI only smoke-checks
  `mysql --version`.

## Recommendations

1. Install Claude Code and Codex CLI with one shared npm helper that never
   uses sudo, probes by running `<cmd> --version`, and warns with a recovery
   command on failure.
2. Ship `extraKnownMarketplaces` + `enabledPlugins` in
   `templates/claude/.claude/settings.json`; keep `setup_plugins.sh` as a
   settings-driven fallback that installs only missing ids.
3. Install `gh` from the official apt repository with a fingerprint-checked
   `signed-by` keyring.

## Sources

- https://code.claude.com/docs/en/setup.md
- https://code.claude.com/docs/en/troubleshoot-install.md
- https://code.claude.com/docs/en/devcontainer.md
- https://code.claude.com/docs/en/settings-reference.md
- https://code.claude.com/docs/en/plugins/install.md
- https://code.claude.com/docs/en/plugins/loading.md
- https://code.claude.com/docs/en/plugins/cli-reference.md
- https://code.claude.com/docs/en/plugins/marketplace-reference.md
- https://github.com/cli/cli/blob/trunk/docs/install_linux.md
- https://packages.debian.org/trixie/gh
- https://packages.debian.org/trixie/postgresql-client
- https://packages.debian.org/trixie/default-mysql-client
