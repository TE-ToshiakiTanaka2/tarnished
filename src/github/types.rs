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

/// Project field (can be single select, iteration, etc.)
#[derive(Debug, Deserialize)]
#[serde(tag = "__typename")]
#[allow(dead_code)]
pub enum ProjectField {
    /// Single select field (Status, Size, Priority, etc.)
    #[serde(rename = "ProjectV2SingleSelectField")]
    SingleSelect(SingleSelectField),
    /// Iteration field
    #[serde(rename = "ProjectV2IterationField")]
    Iteration(IterationField),
    /// Other field types we don't need to handle specially
    #[serde(other)]
    Other,
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

/// Iteration field definition
#[derive(Debug, Deserialize)]
#[allow(dead_code)]
pub struct IterationField {
    /// Field node ID
    pub id: String,
    /// Field name
    pub name: String,
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
