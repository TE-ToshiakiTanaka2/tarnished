#!/bin/bash
# =============================================================================
# Template Plugin: agent-workflows
# This file is meant to be sourced by setup.sh, not executed directly.
# =============================================================================
# This plugin provides the agent-neutral workflow source used by Claude Code
# and Codex projections.
# =============================================================================

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

plugin_name() {
    echo "agent-workflows"
}

plugin_description() {
    echo "Shared Claude/Codex workflow source"
}

plugin_copy() {
    local target_dir="$1"

    print_info "Copying shared agent workflow files..."

    if [[ -d "${PLUGIN_DIR}/.tarnished" ]]; then
        copy_dir_with_confirm "${PLUGIN_DIR}/.tarnished" "${target_dir}/.tarnished"
    fi

    local erd_source="${PLUGIN_DIR}/../claude/.claude/commands/erd"
    if [[ -d "$erd_source" ]]; then
        copy_dir_with_confirm "$erd_source" "${target_dir}/.tarnished/workflows/erd"
    fi

    print_success "Shared agent workflow files copied"
}
