#!/bin/bash
# =============================================================================
# mise Runtime Setup Script
# =============================================================================
# Runs `mise install` in the project root so a mise.toml edited after the image
# was built converges without a rebuild. It is sourced by post.sh and must stay
# the first install block: a Node version change removes npm global CLIs, which
# the following setup_claude / setup_codex blocks then reinstall.
# =============================================================================

setup_mise() {
    echo "Setting up mise runtimes..."

    if ! command -v mise &> /dev/null; then
        echo "  [WARN] mise not found. Skipping runtime installation."
        echo "  Rebuild the container from the current docker/Dockerfile.dev (see docs/maintenance.md)."
        return 0
    fi

    local project_root
    project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

    if [[ ! -f "${project_root}/mise.toml" ]] \
        && [[ ! -f "${project_root}/.mise.toml" ]] \
        && [[ ! -f "${project_root}/.tool-versions" ]]; then
        echo "  - No mise.toml found in ${project_root}, skipping"
        return 0
    fi

    if (cd "$project_root" && mise install); then
        echo "  - mise runtimes are up to date"
    else
        echo "  [WARN] mise install failed (network error or invalid mise.toml)"
        echo "  You can retry manually: cd ${project_root} && mise install"
    fi
    return 0
}
