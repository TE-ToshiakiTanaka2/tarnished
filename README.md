# Tarnished

Tarnished sets up and maintains a DevContainer development environment with shared Claude Code and Codex workflows. Choose language and service plugins for your project, then receive updates to the distributed AI skills, workflows and settings. The repository also includes [erd, a GitHub issue and tag CLI](docs/erd.md).

## First-time setup

Requires Bash 4.4+, Git, jq, and `sha256sum` or `shasum`. On macOS, install a modern Bash; the system Bash 3.2 is unsupported.

```bash
mkdir my-project && cd my-project
curl -fsSL https://raw.githubusercontent.com/TE-ToshiakiTanaka2/tarnished/develop/setup.sh | bash
```

Follow the prompts, then open the folder in VS Code and choose **Reopen in Container**. See the [setup reference](docs/setup.md) for AI profiles, Codex workflow invocation and monorepos.

## Update an existing project

Run these commands from your project directory. Preview an AI update, then apply it:

```bash
curl -fsSL https://raw.githubusercontent.com/TE-ToshiakiTanaka2/tarnished/develop/setup.sh | bash -s -- --refresh --dry-run
curl -fsSL https://raw.githubusercontent.com/TE-ToshiakiTanaka2/tarnished/develop/setup.sh | bash -s -- --refresh -y
```

To update both distributed AI assets and eligible runtime helpers, including pruning unchanged obsolete helpers:

```bash
curl -fsSL https://raw.githubusercontent.com/TE-ToshiakiTanaka2/tarnished/develop/setup.sh | bash -s -- --upgrade -y --prune
```

A bare setup rerun also refreshes AI assets. Container starts use the installed refresher. For older installations, run the current setup command above first and follow any [updater migration guidance](docs/maintenance.md#existing-installations).

Updates replace distributed files even if you edited or deleted them. **Every differing existing file is backed up and verified before replacement**, including the complete `.claude/settings.json` and, where Codex is applicable, `.codex/config.toml`. Custom keys inside those settings files are backed up and replaced too. Matching files need no backup. Application files, project-only siblings, profile selection and configured `.local` sidecars are preserved.

If helper upgrades are blocked by a missing manifest or dirty working tree, the AI update can still run; the combined command reports the helper problem and returns a nonzero status. See [maintenance](docs/maintenance.md) for helper adoption, version selection and module scope.

## Backups and recovery

The update reports each backup path beneath `.tarnished/backups/`. Each run uses a unique private directory and keeps original relative paths. Backups are never automatically deleted; retain or remove them yourself when appropriate. They can contain sensitive settings and should stay out of version control.

To restore a file, copy the **exact backup path reported by your update** back to its original location. For example, if the report names `.tarnished/backups/refresh.A1b2C3/.codex/config.toml`:

```bash
cp .tarnished/backups/refresh.A1b2C3/.codex/config.toml .codex/config.toml
```

The next refresh may replace that restored live file again. For lasting changes, use [configured sidecars or the CLI's native local settings](docs/maintenance.md#customization). Native local settings are preserved and are not treated as whole-file replacement sidecars.

## More documentation

- [Maintenance, ownership, customization and migration](docs/maintenance.md)
- [AI profiles and monorepo setup](docs/setup.md)
- [erd installation, usage and development](docs/erd.md)

## License

MIT
