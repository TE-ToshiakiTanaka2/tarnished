//! Branch name pattern matching for version bump determination.

use glob::Pattern;

#[cfg(test)]
use crate::tag_config::BumpPattern;
use crate::tag_config::{BumpType, TagRules};

/// Matches branch names against configured patterns to determine bump type.
pub struct BranchMatcher {
    patterns: Vec<(Pattern, BumpType)>,
    default_bump: BumpType,
}

impl BranchMatcher {
    /// Create a new `BranchMatcher` from tag rules configuration.
    pub fn new(rules: &TagRules) -> anyhow::Result<Self> {
        let mut patterns = Vec::new();

        for bp in &rules.patterns {
            let pattern = Pattern::new(&bp.pattern)
                .map_err(|e| anyhow::anyhow!("Invalid glob pattern '{}': {}", bp.pattern, e))?;
            patterns.push((pattern, bp.bump));
        }

        Ok(Self {
            patterns,
            default_bump: rules.default.bump,
        })
    }

    /// Create a `BranchMatcher` from a list of patterns.
    #[cfg(test)]
    pub fn from_patterns(patterns: &[BumpPattern], default_bump: BumpType) -> anyhow::Result<Self> {
        let compiled: Result<Vec<_>, _> = patterns
            .iter()
            .map(|bp| {
                Pattern::new(&bp.pattern)
                    .map(|p| (p, bp.bump))
                    .map_err(|e| anyhow::anyhow!("Invalid glob pattern '{}': {}", bp.pattern, e))
            })
            .collect();

        Ok(Self {
            patterns: compiled?,
            default_bump,
        })
    }

    /// Match a branch name and return the appropriate bump type.
    ///
    /// Returns the bump type of the first matching pattern, or the default if none match.
    pub fn match_branch(&self, branch: &str) -> BumpType {
        for (pattern, bump_type) in &self.patterns {
            if pattern.matches(branch) {
                return *bump_type;
            }
        }
        self.default_bump
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn create_test_patterns() -> Vec<BumpPattern> {
        vec![
            BumpPattern {
                pattern: "feat/*".to_string(),
                bump: BumpType::Minor,
            },
            BumpPattern {
                pattern: "fix/*".to_string(),
                bump: BumpType::Patch,
            },
            BumpPattern {
                pattern: "breaking/*".to_string(),
                bump: BumpType::Major,
            },
            BumpPattern {
                pattern: "release/*".to_string(),
                bump: BumpType::Release,
            },
        ]
    }

    #[test]
    fn test_match_feat_branch() {
        let matcher = BranchMatcher::from_patterns(&create_test_patterns(), BumpType::Rc).unwrap();
        assert_eq!(matcher.match_branch("feat/new-feature"), BumpType::Minor);
        assert_eq!(matcher.match_branch("feat/add-button"), BumpType::Minor);
    }

    #[test]
    fn test_match_fix_branch() {
        let matcher = BranchMatcher::from_patterns(&create_test_patterns(), BumpType::Rc).unwrap();
        assert_eq!(matcher.match_branch("fix/bug-123"), BumpType::Patch);
    }

    #[test]
    fn test_match_breaking_branch() {
        let matcher = BranchMatcher::from_patterns(&create_test_patterns(), BumpType::Rc).unwrap();
        assert_eq!(matcher.match_branch("breaking/api-change"), BumpType::Major);
    }

    #[test]
    fn test_match_release_branch() {
        let matcher = BranchMatcher::from_patterns(&create_test_patterns(), BumpType::Rc).unwrap();
        assert_eq!(matcher.match_branch("release/v1.0.0"), BumpType::Release);
    }

    #[test]
    fn test_default_bump_on_no_match() {
        let matcher = BranchMatcher::from_patterns(&create_test_patterns(), BumpType::Rc).unwrap();
        assert_eq!(matcher.match_branch("random/branch"), BumpType::Rc);
        assert_eq!(matcher.match_branch("chore/cleanup"), BumpType::Rc);
        assert_eq!(matcher.match_branch("main"), BumpType::Rc);
    }

    #[test]
    fn test_first_match_wins() {
        let patterns = vec![
            BumpPattern {
                pattern: "feat/*".to_string(),
                bump: BumpType::Minor,
            },
            BumpPattern {
                pattern: "feat/special*".to_string(),
                bump: BumpType::Major,
            },
        ];
        let matcher = BranchMatcher::from_patterns(&patterns, BumpType::Rc).unwrap();
        // First pattern matches, so Minor is returned
        assert_eq!(matcher.match_branch("feat/special-case"), BumpType::Minor);
    }

    #[test]
    fn test_deep_path_matching() {
        let patterns = vec![BumpPattern {
            pattern: "feat/**".to_string(),
            bump: BumpType::Minor,
        }];
        let matcher = BranchMatcher::from_patterns(&patterns, BumpType::Rc).unwrap();
        assert_eq!(
            matcher.match_branch("feat/deep/nested/path"),
            BumpType::Minor
        );
    }

    #[test]
    fn test_exact_match() {
        let patterns = vec![BumpPattern {
            pattern: "main".to_string(),
            bump: BumpType::Release,
        }];
        let matcher = BranchMatcher::from_patterns(&patterns, BumpType::Rc).unwrap();
        assert_eq!(matcher.match_branch("main"), BumpType::Release);
        assert_eq!(matcher.match_branch("main-backup"), BumpType::Rc);
    }

    #[test]
    fn test_empty_patterns() {
        let matcher = BranchMatcher::from_patterns(&[], BumpType::Patch).unwrap();
        assert_eq!(matcher.match_branch("any-branch"), BumpType::Patch);
    }

    #[test]
    fn test_from_tag_rules() {
        use crate::tag_config::{DefaultBump, TagRules};

        let rules = TagRules {
            patterns: vec![BumpPattern {
                pattern: "feat/*".to_string(),
                bump: BumpType::Minor,
            }],
            default: DefaultBump {
                bump: BumpType::Patch,
            },
        };

        let matcher = BranchMatcher::new(&rules).unwrap();
        assert_eq!(matcher.match_branch("feat/x"), BumpType::Minor);
        assert_eq!(matcher.match_branch("other"), BumpType::Patch);
    }
}
