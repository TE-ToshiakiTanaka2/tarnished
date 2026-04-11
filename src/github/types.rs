//! Type definitions for GitHub API responses.

use serde::{Deserialize, Serialize};

/// Response from creating an issue via REST API
#[derive(Debug, Deserialize)]
pub struct CreateIssueResponse {
    /// Issue ID (`node_id` for GraphQL)
    pub node_id: String,
    /// Issue number
    pub number: u64,
    /// Issue URL
    pub html_url: String,
}

/// Label on a GitHub issue
#[derive(Debug, Deserialize)]
pub struct IssueLabel {
    /// Label name
    pub name: String,
}

/// Response from getting an issue via REST API
#[derive(Debug, Deserialize)]
#[allow(dead_code)]
pub struct GetIssueResponse {
    /// Issue ID (`node_id` for GraphQL)
    pub node_id: String,
    /// Issue number
    pub number: u64,
    /// Issue title
    pub title: String,
    /// Issue body
    pub body: Option<String>,
    /// Issue URL
    pub html_url: String,
    /// Issue labels
    #[serde(default)]
    pub labels: Vec<IssueLabel>,
}

/// Response from GraphQL query to get project info
#[derive(Debug, Deserialize)]
pub struct GraphQLResponse<T> {
    /// Response data
    pub data: Option<T>,
    /// Errors if any
    pub errors: Option<Vec<GraphQLError>>,
}

/// GraphQL error
#[derive(Debug, Deserialize)]
pub struct GraphQLError {
    /// Error message
    pub message: String,
}

/// Project query response data
#[derive(Debug, Deserialize)]
pub struct ProjectQueryData {
    /// User data (when querying user projects)
    pub user: Option<UserProjectData>,
    /// Organization data (when querying org projects)
    pub organization: Option<OrgProjectData>,
}

/// User project data
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UserProjectData {
    /// Project V2
    pub project_v2: Option<ProjectV2>,
}

/// Organization project data
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct OrgProjectData {
    /// Project V2
    pub project_v2: Option<ProjectV2>,
}

/// GitHub Project V2
#[derive(Debug, Deserialize)]
pub struct ProjectV2 {
    /// Project node ID
    pub id: String,
    /// Project title
    pub title: String,
    /// Project fields
    pub fields: Option<ProjectFieldConnection>,
}

/// Project field connection
#[derive(Debug, Deserialize)]
pub struct ProjectFieldConnection {
    /// Field nodes
    pub nodes: Vec<ProjectField>,
}

/// Project field (can be single select, iteration, date, etc.)
#[derive(Debug, Deserialize)]
#[serde(tag = "__typename")]
pub enum ProjectField {
    /// Single select field (Status, Size, Priority, etc.)
    #[serde(rename = "ProjectV2SingleSelectField")]
    SingleSelect(SingleSelectField),
    /// Iteration field
    #[serde(rename = "ProjectV2IterationField")]
    Iteration(IterationField),
    /// Standard field (includes Date fields)
    #[serde(rename = "ProjectV2Field")]
    Field(StandardField),
    /// Other field types we don't need to handle specially
    #[serde(other)]
    Other,
}

/// Standard project field (used for Date, Number, Text, etc.)
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
#[allow(dead_code)]
pub struct StandardField {
    /// Field node ID
    pub id: String,
    /// Field name
    pub name: String,
    /// Data type (DATE, NUMBER, TEXT, etc.)
    pub data_type: Option<String>,
}

/// Single select field definition
#[derive(Debug, Deserialize)]
pub struct SingleSelectField {
    /// Field node ID
    pub id: String,
    /// Field name
    pub name: String,
    /// Available options
    pub options: Vec<SingleSelectOption>,
}

/// Single select option
#[derive(Debug, Deserialize)]
pub struct SingleSelectOption {
    /// Option ID
    pub id: String,
    /// Option name
    pub name: String,
}

/// Iteration field definition with configuration
#[derive(Debug, Deserialize)]
#[allow(dead_code)]
pub struct IterationField {
    /// Field node ID
    pub id: String,
    /// Field name
    pub name: String,
    /// Iteration configuration (includes available iterations)
    pub configuration: Option<IterationConfiguration>,
}

/// Iteration field configuration
#[derive(Debug, Clone, Deserialize)]
pub struct IterationConfiguration {
    /// List of available iterations
    pub iterations: Vec<Iteration>,
}

/// A single iteration in a project
#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Iteration {
    /// Iteration ID (used for mutations)
    pub id: String,
    /// Iteration title (e.g., "Sprint 5")
    pub title: String,
    /// Start date in ISO 8601 format (YYYY-MM-DD)
    pub start_date: String,
    /// Duration in days
    pub duration: u32,
}

#[allow(dead_code)]
impl Iteration {
    /// Calculate the end date of this iteration.
    ///
    /// Returns the end date in ISO 8601 format (YYYY-MM-DD).
    pub fn end_date(&self) -> Option<String> {
        use chrono::{Days, NaiveDate};
        let start = NaiveDate::parse_from_str(&self.start_date, "%Y-%m-%d").ok()?;
        let end = start.checked_add_days(Days::new(u64::from(self.duration) - 1))?;
        Some(end.format("%Y-%m-%d").to_string())
    }

    /// Check if this iteration contains the given date.
    pub fn contains_date(&self, date: &str) -> bool {
        use chrono::NaiveDate;
        let Some(start) = NaiveDate::parse_from_str(&self.start_date, "%Y-%m-%d").ok() else {
            return false;
        };
        let Some(check_date) = NaiveDate::parse_from_str(date, "%Y-%m-%d").ok() else {
            return false;
        };
        let Some(end_str) = self.end_date() else {
            return false;
        };
        let Some(end) = NaiveDate::parse_from_str(&end_str, "%Y-%m-%d").ok() else {
            return false;
        };
        check_date >= start && check_date <= end
    }
}

/// Date field definition (standard field with DATE dataType)
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
#[allow(dead_code)]
pub struct DateField {
    /// Field node ID
    pub id: String,
    /// Field name
    pub name: String,
    /// Data type (should be "DATE")
    pub data_type: String,
}

/// Response from adding an item to a project
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AddProjectItemData {
    /// Add item mutation response
    pub add_project_v2_item_by_id: Option<AddProjectItemPayload>,
}

/// Add project item payload
#[derive(Debug, Deserialize)]
pub struct AddProjectItemPayload {
    /// The created project item
    pub item: Option<ProjectItem>,
}

/// Project item
#[derive(Debug, Deserialize)]
pub struct ProjectItem {
    /// Item node ID
    pub id: String,
}

/// Response from updating a project item field
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
#[allow(dead_code)]
pub struct UpdateProjectItemFieldData {
    /// Update field mutation response
    pub update_project_v2_item_field_value: Option<UpdateProjectItemFieldPayload>,
}

/// Update project item field payload
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
#[allow(dead_code)]
pub struct UpdateProjectItemFieldPayload {
    /// The updated project item
    pub project_v2_item: Option<ProjectItem>,
}

/// Request body for creating an issue
#[derive(Debug, Serialize)]
pub struct CreateIssueRequest {
    /// Issue title
    pub title: String,
    /// Issue body
    #[serde(skip_serializing_if = "Option::is_none")]
    pub body: Option<String>,
    /// Labels to add
    #[serde(skip_serializing_if = "Option::is_none")]
    pub labels: Option<Vec<String>>,
    /// Milestone number
    #[serde(skip_serializing_if = "Option::is_none")]
    pub milestone: Option<u64>,
    /// Assignees
    #[serde(skip_serializing_if = "Option::is_none")]
    pub assignees: Option<Vec<String>>,
}

// =============================================================================
// PR Linked Issues Types
// =============================================================================

/// Response data for PR linked issues query
#[derive(Debug, Deserialize)]
pub struct PrLinkedIssuesData {
    /// Repository data
    pub repository: Option<RepositoryPrData>,
}

/// Repository data containing pull request
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RepositoryPrData {
    /// Pull request data
    pub pull_request: Option<PullRequestData>,
}

/// Pull request data with closing issues references
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
#[allow(dead_code)]
pub struct PullRequestData {
    /// PR node ID
    pub id: String,
    /// PR number
    pub number: u64,
    /// PR title
    pub title: String,
    /// Issues that will be closed when this PR is merged
    pub closing_issues_references: Option<ClosingIssuesConnection>,
}

/// Connection for closing issues
#[derive(Debug, Deserialize)]
#[allow(dead_code)]
pub struct ClosingIssuesConnection {
    /// Total count of linked issues
    #[serde(rename = "totalCount")]
    pub total_count: u32,
    /// Linked issue nodes
    pub nodes: Vec<LinkedIssue>,
}

/// A linked issue from a PR
#[derive(Debug, Deserialize)]
pub struct LinkedIssue {
    /// Issue node ID
    pub id: String,
    /// Issue number
    pub number: u64,
    /// Issue title
    pub title: String,
}

// =============================================================================
// Project Item Query Types
// =============================================================================

/// Response data for finding an issue's project items
#[derive(Debug, Deserialize)]
pub struct IssueProjectItemsData {
    /// Node (issue) data
    pub node: Option<IssueWithProjectItems>,
}

/// Issue with its project items
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct IssueWithProjectItems {
    /// Project items connection
    pub project_items: Option<ProjectItemsConnection>,
}

/// Connection for project items
#[derive(Debug, Deserialize)]
pub struct ProjectItemsConnection {
    /// Project item nodes
    pub nodes: Vec<ProjectItemWithProject>,
}

/// Project item with its project info
#[derive(Debug, Deserialize)]
pub struct ProjectItemWithProject {
    /// Project item ID
    pub id: String,
    /// The project this item belongs to
    pub project: ProjectItemProject,
}

/// Project info from a project item
#[derive(Debug, Deserialize)]
#[allow(dead_code)]
pub struct ProjectItemProject {
    /// Project ID
    pub id: String,
    /// Project number
    pub number: u32,
}

// =============================================================================
// Repository Projects Types
// =============================================================================

/// Response data for repository linked projects query
#[derive(Debug, Deserialize)]
pub struct RepositoryProjectsData {
    /// Repository data
    pub repository: Option<RepositoryWithProjects>,
}

/// Repository with linked projects
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RepositoryWithProjects {
    /// Projects V2 connection
    pub projects_v2: Option<ProjectsV2Connection>,
}

/// Projects V2 connection
#[derive(Debug, Deserialize)]
pub struct ProjectsV2Connection {
    /// Project nodes
    pub nodes: Vec<ProjectV2Summary>,
}

/// Project V2 summary (for listing)
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct ProjectV2Summary {
    /// Project node ID
    pub id: String,
    /// Project number
    pub number: u32,
    /// Project title
    pub title: String,
    /// Project URL
    pub url: String,
    /// Whether the project is closed
    pub closed: bool,
    /// Project owner
    pub owner: ProjectOwner,
}

/// Project owner (can be User or Organization)
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct ProjectOwner {
    /// Owner login name
    pub login: String,
}

// =============================================================================
// Project Details Types (for JSON output)
// =============================================================================

/// Project details for JSON output
#[derive(Debug, Clone, Serialize)]
pub struct ProjectDetails {
    /// Project node ID
    pub id: String,
    /// Project number
    pub number: u32,
    /// Project title
    pub title: String,
    /// Project owner
    pub owner: String,
    /// Project fields
    pub fields: Vec<FieldDetails>,
}

/// Field details for JSON output
#[derive(Debug, Clone, Serialize)]
pub struct FieldDetails {
    /// Field name
    pub name: String,
    /// Field type
    #[serde(rename = "type")]
    pub field_type: String,
    /// Options (for `SingleSelect` fields)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub options: Option<Vec<String>>,
    /// Iterations (for `Iteration` fields)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub iterations: Option<Vec<String>>,
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_iteration(id: &str, title: &str, start: &str, duration: u32) -> Iteration {
        Iteration {
            id: id.to_string(),
            title: title.to_string(),
            start_date: start.to_string(),
            duration,
        }
    }

    #[test]
    fn test_iteration_end_date() {
        let iteration = make_iteration("1", "Sprint 1", "2024-01-01", 14);
        assert_eq!(iteration.end_date(), Some("2024-01-14".to_string()));
    }

    #[test]
    fn test_iteration_end_date_single_day() {
        let iteration = make_iteration("1", "Sprint 1", "2024-01-01", 1);
        assert_eq!(iteration.end_date(), Some("2024-01-01".to_string()));
    }

    #[test]
    fn test_iteration_contains_date() {
        let iteration = make_iteration("1", "Sprint 1", "2024-01-01", 14);

        // Start date
        assert!(iteration.contains_date("2024-01-01"));
        // Middle date
        assert!(iteration.contains_date("2024-01-07"));
        // End date
        assert!(iteration.contains_date("2024-01-14"));
        // Before start
        assert!(!iteration.contains_date("2023-12-31"));
        // After end
        assert!(!iteration.contains_date("2024-01-15"));
    }

    #[test]
    fn test_iteration_contains_date_invalid() {
        let iteration = make_iteration("1", "Sprint 1", "2024-01-01", 14);
        assert!(!iteration.contains_date("invalid"));
    }

    #[test]
    fn test_iteration_end_date_invalid_start() {
        let iteration = make_iteration("1", "Sprint 1", "invalid", 14);
        assert_eq!(iteration.end_date(), None);
    }
}
