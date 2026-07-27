#!/bin/bash
# =============================================================================
# verify-mirrors.sh — enforce byte-identity of mirrored AI workflow assets
# =============================================================================
# The workspace trees dogfood the templates that setup.sh ships to downstream
# projects. The pairs below MUST stay byte-identical (AGENTS.md section 6);
# historically this was verified by hand with `diff -r`, and three of the five
# 2026-07 audit PRs were manual parity repairs. This script encodes the
# invariants so CI (asset-parity.yml) and reviewers can check them in one call.
#
# Usage:
#   scripts/verify-mirrors.sh          # verify all pairs, exit 1 on any drift
#
# Exit codes: 0 = all mirrors identical, 1 = drift detected (details on stdout)
# =============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILURES=0

# check_pair <label> <path_a> <path_b>
# Both paths are repo-relative. Directories are compared recursively.
check_pair() {
    local label="$1"
    local a="${REPO_ROOT}/$2"
    local b="${REPO_ROOT}/$3"

    if [[ ! -e "$a" ]] || [[ ! -e "$b" ]]; then
        echo "FAIL ${label}: missing path ($2 or $3)"
        FAILURES=$((FAILURES + 1))
        return 0
    fi

    if diff -r "$a" "$b" > /tmp/mirror-diff.$$ 2>&1; then
        echo "OK   ${label}"
    else
        echo "FAIL ${label}: $2 and $3 differ:"
        sed 's/^/     /' /tmp/mirror-diff.$$
        FAILURES=$((FAILURES + 1))
    fi
    rm -f /tmp/mirror-diff.$$
    return 0
}

# --- erd command docs: three-way mirror -------------------------------------
check_pair "erd: live commands == tarnished projection" \
    ".claude/commands/erd" ".tarnished/workflows/erd"
check_pair "erd: live commands == claude template" \
    ".claude/commands/erd" "templates/claude/.claude/commands/erd"

# --- Claude skills / commands / agents / scripts vs claude template ---------
check_pair "claude: skills tree" \
    ".claude/skills" "templates/claude/.claude/skills"
check_pair "claude: commands tree" \
    ".claude/commands" "templates/claude/.claude/commands"
check_pair "claude: agents tree" \
    ".claude/agents" "templates/claude/.claude/agents"
check_pair "claude: scripts tree" \
    ".claude/scripts" "templates/claude/.claude/scripts"
check_pair "claude: shell rules" \
    ".claude/rules/shell.md" "templates/claude/.claude/rules/shell.md"

# --- Codex projections vs codex template -------------------------------------
check_pair "codex: .agents skills" \
    ".agents" "templates/codex/.agents"
check_pair "codex: config.toml" \
    ".codex/config.toml" "templates/codex/.codex/config.toml"

# --- Shared workflow source vs agent-workflows template ---------------------
# The template ships without erd/ (generated at scaffold time from the claude
# template) so the erd subtree is excluded from this pair.
check_pair "tarnished: workflow summaries" \
    ".tarnished/workflows/README.md" \
    "templates/agent-workflows/.tarnished/workflows/README.md"
for f in issue design implement review pr flow; do
    check_pair "tarnished: workflows/${f}.md" \
        ".tarnished/workflows/${f}.md" \
        "templates/agent-workflows/.tarnished/workflows/${f}.md"
done
check_pair "tarnished: refresh.json" \
    ".tarnished/refresh.json" \
    "templates/agent-workflows/.tarnished/refresh.json"
check_pair "tarnished: agent-profile.json" \
    ".tarnished/agent-profile.json" \
    "templates/agent-workflows/.tarnished/agent-profile.json"

# --- devcontainer refresh script ---------------------------------------------
check_pair "devcontainer: refresh-assets.sh" \
    ".devcontainer/scripts/refresh-assets.sh" \
    "templates/core/.devcontainer/scripts/refresh-assets.sh"
check_pair "devcontainer: setup_plugins.sh" \
    ".devcontainer/scripts/setup_plugins.sh" \
    "templates/claude/.devcontainer/scripts/setup_plugins.sh"

# --- Rust rules vs rust language template ------------------------------------
check_pair "rules: rust.md" \
    ".claude/rules/rust.md" "templates/languages/rust/.claude/rules/rust.md"

echo
if [[ "$FAILURES" -gt 0 ]]; then
    echo "verify-mirrors: ${FAILURES} mirror pair(s) diverged."
    echo "Fix by copying the edited tree over its mirror(s) — see AGENTS.md section 6."
    exit 1
fi
echo "verify-mirrors: all mirror pairs are byte-identical."
