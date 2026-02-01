#!/bin/sh
# setup-project.sh - Interactive setup for GitHub Project integration
# POSIX sh compatible

set -e

# Color definitions (with fallback for non-TTY)
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    CYAN=''
    BOLD=''
    NC=''
fi

# Logging functions
info() {
    printf "${BLUE}[INFO]${NC} %s\n" "$1"
}

success() {
    printf "${GREEN}[SUCCESS]${NC} %s\n" "$1"
}

warn() {
    printf "${YELLOW}[WARN]${NC} %s\n" "$1"
}

error() {
    printf "${RED}[ERROR]${NC} %s\n" "$1" >&2
}

header() {
    printf "\n${BOLD}${CYAN}=== %s ===${NC}\n\n" "$1"
}

# Check prerequisites
check_prerequisites() {
    header "Checking Prerequisites"

    # Check gh CLI
    if ! command -v gh >/dev/null 2>&1; then
        error "gh CLI is not installed."
        echo "Please install it from: https://cli.github.com/"
        exit 1
    fi
    success "gh CLI is installed"

    # Check gh auth
    if ! gh auth status >/dev/null 2>&1; then
        error "gh CLI is not authenticated."
        echo "Please run: gh auth login"
        exit 1
    fi
    success "gh CLI is authenticated"

    # Check jq
    if ! command -v jq >/dev/null 2>&1; then
        error "jq is not installed."
        echo "Please install jq for JSON processing."
        exit 1
    fi
    success "jq is installed"

    # Check if in git repository
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        error "Not in a git repository."
        exit 1
    fi
    success "In a git repository"
}

# Fetch user's projects
fetch_projects() {
    header "Fetching GitHub Projects"

    GITHUB_USER=$(gh api user --jq '.login')
    info "Logged in as: $GITHUB_USER"

    # Fetch user projects
    PROJECTS_JSON=$(gh api graphql -f query='
        query($login: String!) {
            user(login: $login) {
                projectsV2(first: 20) {
                    nodes {
                        id
                        number
                        title
                    }
                }
            }
        }
    ' -f login="$GITHUB_USER" --jq '.data.user.projectsV2.nodes')

    PROJECT_COUNT=$(echo "$PROJECTS_JSON" | jq 'length')

    if [ "$PROJECT_COUNT" -eq 0 ]; then
        error "No GitHub Projects found for user: $GITHUB_USER"
        echo "Please create a project at: https://github.com/users/$GITHUB_USER/projects"
        exit 1
    fi

    echo ""
    echo "Available Projects:"
    echo ""

    i=1
    while [ "$i" -le "$PROJECT_COUNT" ]; do
        idx=$((i - 1))
        num=$(echo "$PROJECTS_JSON" | jq -r ".[$idx].number")
        title=$(echo "$PROJECTS_JSON" | jq -r ".[$idx].title")
        printf "  ${CYAN}%d)${NC} #%s - %s\n" "$i" "$num" "$title"
        i=$((i + 1))
    done

    echo ""
    printf "Select a project (1-%d): " "$PROJECT_COUNT"
    read -r selection

    if ! echo "$selection" | grep -q '^[0-9]\+$' || [ "$selection" -lt 1 ] || [ "$selection" -gt "$PROJECT_COUNT" ]; then
        error "Invalid selection"
        exit 1
    fi

    # Get selected project (0-indexed for jq)
    idx=$((selection - 1))
    SELECTED_PROJECT=$(echo "$PROJECTS_JSON" | jq ".[$idx]")
    PROJECT_NUMBER=$(echo "$SELECTED_PROJECT" | jq -r '.number')
    PROJECT_TITLE=$(echo "$SELECTED_PROJECT" | jq -r '.title')
    PROJECT_OWNER="$GITHUB_USER"

    success "Selected: #$PROJECT_NUMBER - $PROJECT_TITLE"
}

# Fetch project fields
fetch_project_fields() {
    header "Fetching Project Fields"

    FIELDS_JSON=$(gh api graphql -f query='
        query($owner: String!, $number: Int!) {
            user(login: $owner) {
                projectV2(number: $number) {
                    fields(first: 50) {
                        nodes {
                            __typename
                            ... on ProjectV2SingleSelectField {
                                id
                                name
                                options {
                                    id
                                    name
                                }
                            }
                        }
                    }
                }
            }
        }
    ' -f owner="$PROJECT_OWNER" -F number="$PROJECT_NUMBER" --jq '.data.user.projectV2.fields.nodes')

    # Extract single select fields as JSON arrays
    STATUS_FIELD=$(echo "$FIELDS_JSON" | jq '[.[] | select(.name == "Status")] | .[0]')
    SIZE_FIELD=$(echo "$FIELDS_JSON" | jq '[.[] | select(.name == "Size")] | .[0]')
    PRIORITY_FIELD=$(echo "$FIELDS_JSON" | jq '[.[] | select(.name == "Priority")] | .[0]')

    # Store options as JSON arrays for easier handling
    if [ "$STATUS_FIELD" = "null" ]; then
        warn "Status field not found in project"
        STATUS_OPTIONS_JSON="[]"
    else
        STATUS_OPTIONS_JSON=$(echo "$STATUS_FIELD" | jq '[.options[].name]')
        success "Found Status field with $(echo "$STATUS_OPTIONS_JSON" | jq 'length') options"
    fi

    if [ "$SIZE_FIELD" = "null" ]; then
        warn "Size field not found in project"
        SIZE_OPTIONS_JSON="[]"
    else
        SIZE_OPTIONS_JSON=$(echo "$SIZE_FIELD" | jq '[.options[].name]')
        success "Found Size field with $(echo "$SIZE_OPTIONS_JSON" | jq 'length') options"
    fi

    if [ "$PRIORITY_FIELD" = "null" ]; then
        warn "Priority field not found in project"
        PRIORITY_OPTIONS_JSON="[]"
    else
        PRIORITY_OPTIONS_JSON=$(echo "$PRIORITY_FIELD" | jq '[.options[].name]')
        success "Found Priority field with $(echo "$PRIORITY_OPTIONS_JSON" | jq 'length') options"
    fi
}

# Display options and read selection
# Sets SELECTED_VALUE variable
select_from_options() {
    field_name="$1"
    options_json="$2"
    fallback="$3"

    option_count=$(echo "$options_json" | jq 'length')

    if [ "$option_count" -eq 0 ]; then
        SELECTED_VALUE="$fallback"
        warn "Using fallback $field_name default: $SELECTED_VALUE"
        return
    fi

    echo ""
    printf "${BOLD}Select default value for %s:${NC}\n" "$field_name"
    echo ""

    i=1
    while [ "$i" -le "$option_count" ]; do
        idx=$((i - 1))
        opt=$(echo "$options_json" | jq -r ".[$idx]")
        printf "  ${CYAN}%d)${NC} %s\n" "$i" "$opt"
        i=$((i + 1))
    done

    echo ""
    printf "Select (1-%d): " "$option_count"
    read -r selection

    if ! echo "$selection" | grep -q '^[0-9]\+$' || [ "$selection" -lt 1 ] || [ "$selection" -gt "$option_count" ]; then
        error "Invalid selection"
        exit 1
    fi

    idx=$((selection - 1))
    SELECTED_VALUE=$(echo "$options_json" | jq -r ".[$idx]")
    success "$field_name default: $SELECTED_VALUE"
}

# Configure field defaults
configure_field_defaults() {
    header "Configuring Field Defaults"

    # Status default
    select_from_options "Status" "$STATUS_OPTIONS_JSON" "Backlog"
    DEFAULT_STATUS="$SELECTED_VALUE"

    # Size default
    select_from_options "Size" "$SIZE_OPTIONS_JSON" "M"
    DEFAULT_SIZE="$SELECTED_VALUE"

    # Priority default
    select_from_options "Priority" "$PRIORITY_OPTIONS_JSON" "P1"
    DEFAULT_PRIORITY="$SELECTED_VALUE"
}

# Configure PR status
configure_pr_status() {
    header "Configuring PR Status"

    echo "When a PR is opened/reopened, linked issues will have their Status updated."

    select_from_options "pr_status.on_open" "$STATUS_OPTIONS_JSON" "In review"
    PR_ON_OPEN="$SELECTED_VALUE"
}

# Check if file exists and prompt for overwrite
# Returns 0 if should write, 1 if should skip
check_file_exists() {
    filepath="$1"

    if [ -f "$filepath" ]; then
        printf "${YELLOW}File already exists: %s${NC}\n" "$filepath"
        printf "Overwrite? [y/N]: "
        read -r response
        case "$response" in
            [yY]|[yY][eE][sS])
                return 0
                ;;
            *)
                return 1
                ;;
        esac
    fi
    return 0
}

# Generate files
generate_files() {
    header "Generating Configuration Files"

    # Ensure directories exist
    mkdir -p .github/workflows

    # Generate project.yml
    PROJECT_YML=".github/project.yml"
    if check_file_exists "$PROJECT_YML"; then
        cat > "$PROJECT_YML" << EOF
default_project:
  owner: "$PROJECT_OWNER"
  number: $PROJECT_NUMBER  # $PROJECT_TITLE

field_defaults:
  Status: "$DEFAULT_STATUS"
  Size: "$DEFAULT_SIZE"
  Priority: "$DEFAULT_PRIORITY"

# PR event status configuration
pr_status:
  on_open: "$PR_ON_OPEN"  # Status when PR is opened/reopened
EOF
        success "Created: $PROJECT_YML"
    else
        warn "Skipped: $PROJECT_YML"
    fi

    # Generate project-integration.yml
    INTEGRATION_YML=".github/workflows/project-integration.yml"
    if check_file_exists "$INTEGRATION_YML"; then
        cat > "$INTEGRATION_YML" << 'EOF'
name: Project Integration

on:
  issues:
    types: [opened, reopened]

permissions:
  contents: read
  issues: write

env:
  CARGO_TERM_COLOR: always

jobs:
  add-to-project:
    name: Add Issue to Project
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Setup Rust
        uses: dtolnay/rust-toolchain@stable

      - name: Cache cargo registry
        uses: actions/cache@v4
        with:
          path: |
            ~/.cargo/registry
            ~/.cargo/git
            target
          key: ${{ runner.os }}-cargo-release-${{ hashFiles('**/Cargo.lock') }}
          restore-keys: |
            ${{ runner.os }}-cargo-release-
            ${{ runner.os }}-cargo-

      - name: Build erd
        run: cargo build --release

      - name: Link issue to project
        id: link
        run: |
          ./target/release/erd issue link ${{ github.event.issue.number }} --verbose
        env:
          PROJECT_TOKEN: ${{ secrets.PROJECT_TOKEN }}
          ERD_REPO: ${{ github.repository }}
        continue-on-error: true

      - name: Comment on failure
        if: steps.link.outcome == 'failure'
        uses: actions/github-script@v7
        with:
          script: |
            await github.rest.issues.createComment({
              owner: context.repo.owner,
              repo: context.repo.repo,
              issue_number: context.issue.number,
              body: `⚠️ **Project Integration Failed**\n\nFailed to automatically link this issue to the project. This may be due to:\n- Missing \`PROJECT_TOKEN\` secret\n- Invalid project configuration in \`.github/project.yml\`\n- GitHub API errors\n\nPlease link the issue to the project manually or check the [workflow run](${context.serverUrl}/${context.repo.owner}/${context.repo.repo}/actions/runs/${context.runId}) for details.`
            });

      - name: Fail job if link failed
        if: steps.link.outcome == 'failure'
        run: exit 1
EOF
        success "Created: $INTEGRATION_YML"
    else
        warn "Skipped: $INTEGRATION_YML"
    fi

    # Generate pr-project-status.yml
    PR_STATUS_YML=".github/workflows/pr-project-status.yml"
    if check_file_exists "$PR_STATUS_YML"; then
        cat > "$PR_STATUS_YML" << 'EOF'
name: PR Project Status

on:
  pull_request:
    types: [opened, reopened]

permissions:
  contents: read
  pull-requests: read

env:
  CARGO_TERM_COLOR: always

jobs:
  update-status:
    name: Update Project Status
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Setup Rust
        uses: dtolnay/rust-toolchain@stable

      - name: Cache cargo registry
        uses: actions/cache@v4
        with:
          path: |
            ~/.cargo/registry
            ~/.cargo/git
            target
          key: ${{ runner.os }}-cargo-release-${{ hashFiles('**/Cargo.lock') }}
          restore-keys: |
            ${{ runner.os }}-cargo-release-
            ${{ runner.os }}-cargo-

      - name: Build erd
        run: cargo build --release

      - name: Update linked issues status
        id: update-status
        run: |
          ./target/release/erd pr status ${{ github.event.pull_request.number }} --verbose
        env:
          PROJECT_TOKEN: ${{ secrets.PROJECT_TOKEN }}
          ERD_REPO: ${{ github.repository }}
        continue-on-error: true

      - name: Log result
        if: steps.update-status.outcome == 'failure'
        run: |
          echo "::warning::Failed to update project status for linked issues. This may be due to missing PROJECT_TOKEN secret or no linked issues."
EOF
        success "Created: $PR_STATUS_YML"
    else
        warn "Skipped: $PR_STATUS_YML"
    fi
}

# Display PROJECT_TOKEN setup guide
show_token_guide() {
    header "PROJECT_TOKEN Setup Guide"

    cat << EOF
To enable GitHub Actions workflows, you need to create a Personal Access Token
and add it as a repository secret.

${BOLD}Step 1: Create a Personal Access Token (Classic)${NC}

  1. Go to: https://github.com/settings/tokens
  2. Click "Generate new token" -> "Generate new token (classic)"
  3. Set a descriptive name (e.g., "ErdTree Project Integration")
  4. Select scopes:
     - ${GREEN}repo${NC} (Full control of private repositories)
     - ${GREEN}project${NC} (Full control of projects)
  5. Click "Generate token"
  6. ${YELLOW}Copy the token immediately${NC} (you won't see it again!)

${BOLD}Step 2: Add as Repository Secret${NC}

  1. Go to your repository settings
  2. Navigate to: Settings -> Secrets and variables -> Actions
  3. Click "New repository secret"
  4. Name: ${CYAN}PROJECT_TOKEN${NC}
  5. Value: Paste your token
  6. Click "Add secret"

${BOLD}Alternative: Use gh CLI${NC}

  gh secret set PROJECT_TOKEN

Then paste your token when prompted.

EOF
}

# Main function
main() {
    echo ""
    printf "${BOLD}${CYAN}"
    cat << 'EOF'
    ____            _           __     _____      __
   / __ \_______  (_)__  _____/ /_   / ___/___  / /___  ______
  / /_/ / ___/ / / / _ \/ ___/ __/   \__ \/ _ \/ __/ / / / __ \
 / ____/ /  / /_/ /  __/ /__/ /_    ___/ /  __/ /_/ /_/ / /_/ /
/_/   /_/   \____/\___/\___/\__/   /____/\___/\__/\__,_/ .___/
                                                      /_/
EOF
    printf "${NC}"
    echo ""
    echo "Interactive setup for GitHub Project integration with erd"
    echo ""

    check_prerequisites
    fetch_projects
    fetch_project_fields
    configure_field_defaults
    configure_pr_status
    generate_files
    show_token_guide

    header "Setup Complete!"

    echo "Generated files:"
    echo "  - .github/project.yml"
    echo "  - .github/workflows/project-integration.yml"
    echo "  - .github/workflows/pr-project-status.yml"
    echo ""
    echo "Next steps:"
    echo "  1. Set up PROJECT_TOKEN as described above"
    echo "  2. Commit the generated files"
    echo "  3. Create an issue to test the integration"
    echo ""
}

main "$@"
