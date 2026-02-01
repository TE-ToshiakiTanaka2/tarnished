//! Tag-related CLI commands.

use std::path::PathBuf;

use clap::Subcommand;

use crate::git_ops;
use crate::tag_config::Config;
use crate::version::SemVer;

/// Tag-related subcommands
#[derive(Debug, Subcommand)]
pub enum TagCommands {
    /// List tags (placeholder)
    List,
    /// Create a new tag (placeholder)
    Create {
        /// Tag name (e.g., v1.0.0)
        #[arg(value_name = "NAME")]
        name: String,
    },
    /// Delete a tag (placeholder)
    Delete {
        /// Tag name
        #[arg(value_name = "NAME")]
        name: String,
    },
    /// Bump version and create tag (placeholder)
    Bump {
        /// Version bump type
        #[arg(value_enum, default_value = "patch")]
        level: BumpLevel,
    },
    /// Automatically determine version bump from branch name and create tag
    Auto {
        /// Branch name to determine version bump type
        #[arg(short, long)]
        branch: String,

        /// Perform a dry run without creating the tag
        #[arg(short, long, default_value = "false")]
        dry_run: bool,

        /// Path to configuration file (defaults to .github/versioning.yml)
        #[arg(short, long)]
        config: Option<PathBuf>,

        /// Push tag to remote after creation
        #[arg(short, long, default_value = "true")]
        push: bool,

        /// Remote name to push to
        #[arg(long, default_value = "origin")]
        remote: String,
    },
}

/// Version bump level
#[derive(Debug, Clone, Copy, clap::ValueEnum)]
pub enum BumpLevel {
    /// Major version bump (x.0.0)
    Major,
    /// Minor version bump (0.x.0)
    Minor,
    /// Patch version bump (0.0.x)
    Patch,
}

impl TagCommands {
    /// Execute the tag subcommand
    pub fn execute(&self) -> anyhow::Result<()> {
        match self {
            Self::List => {
                println!("Tag list command (not implemented)");
            }
            Self::Create { name } => {
                println!("Tag create '{name}' command (not implemented)");
            }
            Self::Delete { name } => {
                println!("Tag delete '{name}' command (not implemented)");
            }
            Self::Bump { level } => {
                println!("Tag bump {level:?} command (not implemented)");
            }
            Self::Auto {
                branch,
                dry_run,
                config,
                push,
                remote,
            } => {
                execute_auto(branch, *dry_run, config.as_deref(), *push, remote)?;
            }
        }
        Ok(())
    }
}

/// Default tag prefix
const TAG_PREFIX: &str = "v";

/// Default initial version
const INITIAL_VERSION: &str = "0.1.0";

/// Execute the auto-tagging command.
fn execute_auto(
    branch: &str,
    dry_run: bool,
    config_path: Option<&std::path::Path>,
    push: bool,
    remote: &str,
) -> anyhow::Result<()> {
    // Check if we're in a git repository
    if !git_ops::is_git_repository() {
        anyhow::bail!("Not a git repository. Please run this command from a git repository.");
    }

    // Load configuration
    let config = Config::load(config_path)?;

    // Determine bump type from branch name
    let bump_type = config.versioning.branch_prefixes.match_branch(branch);

    // Get current version (latest tag or initial)
    let current_version = git_ops::get_latest_version(TAG_PREFIX)?;

    // Display branch and bump type information
    println!("Branch: {branch}");
    println!("Bump type: {bump_type:?}");

    let (new_version, new_tag) = if let Some(current_version) = current_version {
        // Calculate new version from existing
        let new_version = current_version.bump(bump_type);
        let new_tag = new_version.to_tag(TAG_PREFIX);
        println!("Current version: {current_version}");
        println!("New version: {new_version}");
        println!("New tag: {new_tag}");
        (new_version, new_tag)
    } else {
        // No existing tags, use initial version
        let initial = SemVer::parse(INITIAL_VERSION)?;
        eprintln!("No existing tags found. Starting from initial version: {initial}");
        let new_tag = initial.to_tag(TAG_PREFIX);
        println!("New tag: {new_tag}");
        (initial, new_tag)
    };

    // Suppress unused variable warning (new_version used for display)
    let _ = new_version;

    create_and_push_tag(&new_tag, dry_run, push, remote)
}

fn create_and_push_tag(tag: &str, dry_run: bool, push: bool, remote: &str) -> anyhow::Result<()> {
    if dry_run {
        println!("\n[Dry run] Would create tag: {tag}");
        if push {
            println!("[Dry run] Would push tag to remote: {remote}");
        }
        return Ok(());
    }

    // Create tag
    println!("\nCreating tag: {tag}");
    git_ops::create_tag(tag, Some(&format!("Release {tag}")))?;
    println!("Tag created successfully.");

    // Push tag
    if push {
        println!("Pushing tag to remote '{remote}'...");
        git_ops::push_tag(tag, remote)?;
        println!("Tag pushed successfully.");
    }

    Ok(())
}
