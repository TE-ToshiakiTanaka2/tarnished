#!/bin/bash
# =============================================================================
# Template Plugin: latex
# This file is meant to be sourced by setup.sh, not executed directly.
# =============================================================================
# This plugin provides a LaTeX development environment for academic papers:
# - TeX Live (full) via apt-get install
# - latexmk build driver with per-project .latexmkrc
# - Japanese LaTeX support (platex, LuaLaTeX, upbibtex, upmendex)
# - LaTeX Workshop VS Code extension with SyncTeX
# - Claude Code hooks for latexindent auto-formatting
# - GitHub Actions workflow for PDF builds with directory-based auto-detection
# - Sample paper templates (English/Japanese ICSE format)
#
# =============================================================================

# Get the directory where this plugin is located
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# =============================================================================
# Required Functions
# =============================================================================

# Return plugin identifier
plugin_name() {
    echo "latex"
}

# Return plugin description
plugin_description() {
    echo "LaTeX development environment for academic papers"
}

# =============================================================================
# Hook Functions
# =============================================================================

# Copy GitHub Actions workflow and helper scripts
plugin_copy() {
    local target_dir="$1"

    print_info "Copying LaTeX build workflow..."

    # Create .github directories
    mkdir -p "${target_dir}/.github/workflows"
    mkdir -p "${target_dir}/.github/scripts"

    # Copy workflow file
    local workflow="${PLUGIN_DIR}/.github/workflows/build-pdf.yml"
    if [[ -f "$workflow" ]]; then
        local target_file="${target_dir}/.github/workflows/build-pdf.yml"

        if [[ -f "$target_file" ]]; then
            echo -n "  build-pdf.yml already exists. Overwrite? (y/n) [n]: "
            if check_tty_available; then
                read -r overwrite < /dev/tty
            else
                overwrite="n"
            fi
            if [[ "$overwrite" != "y" ]]; then
                print_info "Skipping build-pdf.yml"
            else
                cp "$workflow" "$target_file"
                print_success "Created build-pdf.yml"
            fi
        else
            cp "$workflow" "$target_file"
            print_success "Created build-pdf.yml"
        fi
    fi

    # Copy detect_changes.sh script
    local detect_script="${PLUGIN_DIR}/.github/scripts/detect_changes.sh"
    if [[ -f "$detect_script" ]]; then
        local target_script="${target_dir}/.github/scripts/detect_changes.sh"

        if [[ -f "$target_script" ]]; then
            echo -n "  detect_changes.sh already exists. Overwrite? (y/n) [n]: "
            if check_tty_available; then
                read -r overwrite < /dev/tty
            else
                overwrite="n"
            fi
            if [[ "$overwrite" != "y" ]]; then
                print_info "Skipping detect_changes.sh"
            else
                cp "$detect_script" "$target_script"
                chmod +x "$target_script"
                print_success "Created detect_changes.sh"
            fi
        else
            cp "$detect_script" "$target_script"
            chmod +x "$target_script"
            print_success "Created detect_changes.sh"
        fi
    fi
}

# Append TeX Live packages and ENV variables to Dockerfile.dev
plugin_dockerfile() {
    local target_dir="$1"
    local dockerfile="${target_dir}/docker/Dockerfile.dev"

    if [[ ! -f "$dockerfile" ]]; then
        print_warning "Dockerfile.dev not found, skipping LaTeX Dockerfile configuration"
        return
    fi

    print_info "Adding TeX Live packages to Dockerfile..."

    local temp_file="${dockerfile}.tmp"

    # Insert TeX Live installation and ENV block before SHELL line
    awk '
    /^SHELL / && !inserted {
        print ""
        print "# TeX Live environment"
        print "RUN apt-get update && apt-get install -y --no-install-recommends \\"
        print "    texlive-full \\"
        print "    && rm -rf /var/lib/apt/lists/*"
        print ""
        print "# LaTeX environment configuration"
        print "ENV TEXINPUTS='"'"'.//;'"'"'"
        print "ENV BIBINPUTS='"'"'.//;'"'"'"
        print ""
        inserted=1
    }
    { print }
    ' "$dockerfile" > "$temp_file"

    mv "$temp_file" "$dockerfile"
    print_success "TeX Live packages and environment variables added to Dockerfile"
}

# Post-copy processing - merge configs, create project structure, copy templates
plugin_post_copy() {
    local target_dir="$1"

    # Merge devcontainer.json features and extensions
    local target_devcontainer="${target_dir}/.devcontainer/devcontainer.json"
    local plugin_devcontainer="${PLUGIN_DIR}/.devcontainer/devcontainer.json"

    if [[ -f "$plugin_devcontainer" ]] && [[ -f "$target_devcontainer" ]]; then
        print_info "Merging LaTeX devcontainer features..."
        local temp_file="${target_dir}/.devcontainer/devcontainer.json.tmp"

        merge_devcontainer_json "$target_devcontainer" "$plugin_devcontainer" "$temp_file"
        mv "$temp_file" "$target_devcontainer"

        print_success "LaTeX devcontainer features merged"
    fi

    # Merge Claude settings hooks
    local target_settings="${target_dir}/.claude/settings.json"
    local plugin_settings="${PLUGIN_DIR}/.claude/settings.json"

    if [[ -f "$plugin_settings" ]] && [[ -f "$target_settings" ]]; then
        print_info "Merging LaTeX Claude settings..."
        local temp_file="${target_dir}/.claude/settings.json.tmp"

        merge_claude_settings_hooks "$target_settings" "$plugin_settings" "$temp_file"
        mv "$temp_file" "$target_settings"

        print_success "LaTeX Claude settings merged"
    fi

    # Copy .latexmkrc (root config for Japanese platex)
    local source_latexmkrc="${PLUGIN_DIR}/.latexmkrc"
    local target_latexmkrc="${target_dir}/.latexmkrc"

    if [[ -f "$source_latexmkrc" ]]; then
        print_info "Copying .latexmkrc..."
        copy_with_confirm "$source_latexmkrc" "$target_latexmkrc"
    fi

    # Copy sample paper templates
    print_info "Copying sample paper templates..."

    # Copy arxiv/sample-en
    local source_sample_en="${PLUGIN_DIR}/arxiv/sample-en"
    local target_sample_en="${target_dir}/arxiv/sample-en"

    if [[ -d "$source_sample_en" ]]; then
        mkdir -p "${target_dir}/arxiv"
        copy_dir_with_confirm "$source_sample_en" "$target_sample_en"
        print_success "Created arxiv/sample-en template"
    fi

    # Copy arxiv/sample-ja
    local source_sample_ja="${PLUGIN_DIR}/arxiv/sample-ja"
    local target_sample_ja="${target_dir}/arxiv/sample-ja"

    if [[ -d "$source_sample_ja" ]]; then
        mkdir -p "${target_dir}/arxiv"
        copy_dir_with_confirm "$source_sample_ja" "$target_sample_ja"
        print_success "Created arxiv/sample-ja template"
    fi

    # Create standard directories for paper categories
    print_info "Creating paper category directories..."
    mkdir -p "${target_dir}/conference"
    mkdir -p "${target_dir}/journal"
    mkdir -p "${target_dir}/workshop"

    touch "${target_dir}/conference/.gitkeep"
    touch "${target_dir}/journal/.gitkeep"
    touch "${target_dir}/workshop/.gitkeep"

    print_success "Paper category directories created"

    # Add .latexmkrc volume mount to docker-compose.yml
    local target_compose="${target_dir}/docker-compose.yml"

    if [[ -f "$target_compose" ]]; then
        print_info "Adding .latexmkrc volume mount to docker-compose.yml..."

        # Add .latexmkrc mount after the workspace volume mount
        if ! grep -q '\.latexmkrc' "$target_compose"; then
            local temp_file="${target_compose}.tmp"
            awk '
            /- \.\/workspace:cached/ || /- \.:\/workspace:cached/ {
                print
                print "      # Mount .latexmkrc to user home for latexmk"
                print "      - .latexmkrc:/home/vscode/.latexmkrc:cached"
                next
            }
            { print }
            ' "$target_compose" > "$temp_file"
            mv "$temp_file" "$target_compose"
            print_success ".latexmkrc volume mount added"
        else
            print_info ".latexmkrc volume mount already exists, skipping"
        fi
    fi

    # Append LaTeX-specific entries to .gitignore
    local target_gitignore="${target_dir}/.gitignore"
    local source_gitignore="${PLUGIN_DIR}/.gitignore.template"

    if [[ -f "$source_gitignore" ]]; then
        print_info "Adding LaTeX entries to .gitignore..."

        if [[ -f "$target_gitignore" ]]; then
            # Append if not already present
            if ! grep -q '# LaTeX intermediate files' "$target_gitignore"; then
                echo "" >> "$target_gitignore"
                cat "$source_gitignore" >> "$target_gitignore"
                print_success "LaTeX entries added to .gitignore"
            else
                print_info "LaTeX entries already in .gitignore, skipping"
            fi
        else
            cp "$source_gitignore" "$target_gitignore"
            print_success "Created .gitignore with LaTeX entries"
        fi
    fi

    # Append LaTeX setup to post.sh
    local target_post_sh="${target_dir}/.devcontainer/scripts/post.sh"

    if [[ -f "$target_post_sh" ]]; then
        print_info "Adding LaTeX setup to post.sh..."

        cat >> "$target_post_sh" << 'EOF'

# -----------------------------------------------------------------------------
# LaTeX Development Environment Setup
# -----------------------------------------------------------------------------
if command -v latexmk &> /dev/null; then
    echo "LaTeX development environment detected."
    echo "  - TeX distribution: $(latex --version | head -1)"
    echo "  - latexmk: $(latexmk --version | head -1)"
    echo "  - Build: latexmk index.tex (in paper directory)"
    echo "  - Or use Ctrl+Alt+B in VS Code with LaTeX Workshop"
else
    echo "Warning: latexmk not found. TeX Live may not be installed correctly."
fi
EOF

        print_success "LaTeX setup added to post.sh"
    fi
}
