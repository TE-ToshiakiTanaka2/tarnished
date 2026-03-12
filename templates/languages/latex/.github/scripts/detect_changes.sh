#!/bin/bash
# =============================================================================
# Detect Changed LaTeX Projects
# =============================================================================
#
# Scans known base directories for LaTeX projects (identified by index.tex)
# and detects which have changed files using git diff.
#
# Usage:
#   ./detect_changes.sh                    # Auto-detect changes (HEAD~1)
#   ./detect_changes.sh --all              # Build all projects
#   ./detect_changes.sh --project <path>   # Build specific project
#   ./detect_changes.sh --base <ref>       # Compare against specific ref
#
# Output (GitHub Actions):
#   Sets 'matrix' and 'has_projects' as GITHUB_OUTPUT
#
# =============================================================================

set -euo pipefail

# Base directories to scan for LaTeX projects
BASE_DIRS=("arxiv" "conference" "journal" "workshop")

# Default entry file
ENTRY_FILE="index.tex"

# Parse arguments
MODE="auto"
BASE_REF="HEAD~1"
SPECIFIC_PROJECT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --all)
            MODE="all"
            shift
            ;;
        --project)
            MODE="specific"
            SPECIFIC_PROJECT="$2"
            shift 2
            ;;
        --base)
            BASE_REF="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# Find all LaTeX projects (directories containing index.tex)
find_all_projects() {
    local projects=()
    for dir in "${BASE_DIRS[@]}"; do
        if [[ -d "$dir" ]]; then
            while IFS= read -r entry_file; do
                local project_path
                project_path=$(dirname "$entry_file")
                projects+=("$project_path")
            done < <(find "$dir" -name "$ENTRY_FILE" -type f 2>/dev/null)
        fi
    done
    printf '%s\n' "${projects[@]}"
}

# Check if a project has changed files
has_changes() {
    local project_path="$1"
    # Check for changes in the project directory
    if git diff --name-only "$BASE_REF" HEAD -- "$project_path" 2>/dev/null | grep -q .; then
        return 0
    fi
    # Also check for changes in root .latexmkrc (shared config)
    if git diff --name-only "$BASE_REF" HEAD -- ".latexmkrc" 2>/dev/null | grep -q .; then
        return 0
    fi
    return 1
}

# Generate project name from path (e.g., "arxiv/sample-en" -> "arxiv-sample-en")
project_name_from_path() {
    echo "$1" | tr '/' '-'
}

# Build the matrix JSON
build_matrix() {
    local projects=()

    case "$MODE" in
        all)
            echo "Mode: Build all projects" >&2
            while IFS= read -r project; do
                [[ -n "$project" ]] && projects+=("$project")
            done < <(find_all_projects)
            ;;
        specific)
            echo "Mode: Build specific project: $SPECIFIC_PROJECT" >&2
            if [[ -f "${SPECIFIC_PROJECT}/${ENTRY_FILE}" ]]; then
                projects+=("$SPECIFIC_PROJECT")
            else
                echo "Error: No ${ENTRY_FILE} found in ${SPECIFIC_PROJECT}" >&2
                exit 1
            fi
            ;;
        auto)
            echo "Mode: Auto-detect changes (base: $BASE_REF)" >&2
            while IFS= read -r project; do
                if [[ -n "$project" ]] && has_changes "$project"; then
                    projects+=("$project")
                    echo "  Changed: $project" >&2
                fi
            done < <(find_all_projects)
            ;;
    esac

    # Build JSON matrix
    local json="["
    local first=true
    for project in "${projects[@]}"; do
        local name
        name=$(project_name_from_path "$project")
        if [[ "$first" == "true" ]]; then
            first=false
        else
            json+=","
        fi
        json+="{\"name\":\"${name}\",\"path\":\"${project}\",\"entry_file\":\"${ENTRY_FILE}\"}"
    done
    json+="]"

    echo "$json"
}

# Main
matrix=$(build_matrix)
has_projects="false"
if [[ "$matrix" != "[]" ]]; then
    has_projects="true"
fi

echo "Matrix: $matrix" >&2
echo "Has projects: $has_projects" >&2

# Set GitHub Actions outputs
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "matrix=${matrix}" >> "$GITHUB_OUTPUT"
    echo "has_projects=${has_projects}" >> "$GITHUB_OUTPUT"
else
    # For local testing
    echo "matrix=${matrix}"
    echo "has_projects=${has_projects}"
fi
