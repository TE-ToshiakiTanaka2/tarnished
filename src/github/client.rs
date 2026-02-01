//! GitHub API client implementation.
//!
//! Provides both REST API and GraphQL API functionality for GitHub operations.

use reqwest::header::{HeaderMap, HeaderValue, ACCEPT, AUTHORIZATION, USER_AGENT};
use serde_json::json;

use super::types::{
    AddProjectItemData, CreateIssueRequest, CreateIssueResponse, GraphQLResponse, ProjectField,
    ProjectQueryData, ProjectV2, UpdateProjectItemFieldData,
};
use crate::project_config::ProjectConfig;

/// GitHub API client
#[allow(dead_code)]
pub struct GitHubClient {
    /// HTTP client
    client: reqwest::Client,
    /// GitHub token for authentication
    token: String,
    /// Base URL for REST API
    rest_base_url: String,
    /// Base URL for GraphQL API
    graphql_url: String,
}

/// Error types for GitHub client operations
#[derive(Debug, thiserror::Error)]
#[allow(dead_code)]
pub enum GitHubClientError {
    /// HTTP request failed
    #[error("HTTP request failed: {0}")]
    RequestError(#[from] reqwest::Error),

    /// GraphQL error returned from API
    #[error("GraphQL error: {0}")]
    GraphQLError(String),

    /// Project not found
    #[error("Project not found: {owner}/projects/{number}")]
    ProjectNotFound { owner: String, number: u32 },

    /// Field not found in project
    #[error("Field '{field}' not found in project")]
    FieldNotFound { field: String },

    /// Option not found for field
    #[error("Option '{option}' not found for field '{field}'")]
    OptionNotFound { field: String, option: String },

    /// Failed to add item to project
    #[error("Failed to add item to project")]
    AddItemFailed,

    /// Failed to update field
    #[error("Failed to update field '{field}'")]
    UpdateFieldFailed { field: String },
}

impl GitHubClient {
    /// Create a new GitHub client.
    ///
    /// # Arguments
    ///
    /// * `token` - GitHub personal access token with appropriate scopes
    pub fn new(token: String) -> Result<Self, GitHubClientError> {
        let mut headers = HeaderMap::new();
        headers.insert(
            AUTHORIZATION,
            HeaderValue::from_str(&format!("Bearer {token}")).unwrap(),
        );
        headers.insert(
            ACCEPT,
            HeaderValue::from_static("application/vnd.github+json"),
        );
        headers.insert(USER_AGENT, HeaderValue::from_static("erd-cli"));
        headers.insert(
            "X-GitHub-Api-Version",
            HeaderValue::from_static("2022-11-28"),
        );

        let client = reqwest::Client::builder()
            .default_headers(headers)
            .build()?;

        Ok(Self {
            client,
            token,
            rest_base_url: "https://api.github.com".to_string(),
            graphql_url: "https://api.github.com/graphql".to_string(),
        })
    }

    /// Create an issue via REST API.
    pub async fn create_issue(
        &self,
        owner: &str,
        repo: &str,
        request: &CreateIssueRequest,
    ) -> Result<CreateIssueResponse, GitHubClientError> {
        let url = format!("{}/repos/{owner}/{repo}/issues", self.rest_base_url);

        let response = self.client.post(&url).json(request).send().await?;

        let issue: CreateIssueResponse = response.error_for_status()?.json().await?;

        Ok(issue)
    }

    /// Get project information including fields.
    pub async fn get_project(
        &self,
        owner: &str,
        number: u32,
    ) -> Result<ProjectV2, GitHubClientError> {
        // Try user project first, then organization
        let query = r"
            query($owner: String!, $number: Int!) {
                user(login: $owner) {
                    projectV2(number: $number) {
                        id
                        title
                        fields(first: 50) {
                            nodes {
                                ... on ProjectV2SingleSelectField {
                                    __typename
                                    id
                                    name
                                    options {
                                        id
                                        name
                                    }
                                }
                                ... on ProjectV2IterationField {
                                    __typename
                                    id
                                    name
                                }
                            }
                        }
                    }
                }
            }
        ";

        let variables = json!({
            "owner": owner,
            "number": number
        });

        let response: GraphQLResponse<ProjectQueryData> =
            self.graphql_query(query, variables).await?;

        if let Some(errors) = response.errors {
            if !errors.is_empty() {
                // If user query fails, try organization
                return self.get_org_project(owner, number).await;
            }
        }

        if let Some(data) = response.data {
            if let Some(user_data) = data.user {
                if let Some(project) = user_data.project_v2 {
                    return Ok(project);
                }
            }
        }

        // Try organization if user didn't have the project
        self.get_org_project(owner, number).await
    }

    /// Get organization project.
    async fn get_org_project(
        &self,
        owner: &str,
        number: u32,
    ) -> Result<ProjectV2, GitHubClientError> {
        let query = r"
            query($owner: String!, $number: Int!) {
                organization(login: $owner) {
                    projectV2(number: $number) {
                        id
                        title
                        fields(first: 50) {
                            nodes {
                                ... on ProjectV2SingleSelectField {
                                    __typename
                                    id
                                    name
                                    options {
                                        id
                                        name
                                    }
                                }
                                ... on ProjectV2IterationField {
                                    __typename
                                    id
                                    name
                                }
                            }
                        }
                    }
                }
            }
        ";

        let variables = json!({
            "owner": owner,
            "number": number
        });

        let response: GraphQLResponse<ProjectQueryData> =
            self.graphql_query(query, variables).await?;

        if let Some(errors) = response.errors {
            if !errors.is_empty() {
                return Err(GitHubClientError::GraphQLError(
                    errors
                        .into_iter()
                        .map(|e| e.message)
                        .collect::<Vec<_>>()
                        .join(", "),
                ));
            }
        }

        if let Some(data) = response.data {
            if let Some(org_data) = data.organization {
                if let Some(project) = org_data.project_v2 {
                    return Ok(project);
                }
            }
        }

        Err(GitHubClientError::ProjectNotFound {
            owner: owner.to_string(),
            number,
        })
    }

    /// Add an issue to a project.
    pub async fn add_issue_to_project(
        &self,
        project_id: &str,
        issue_node_id: &str,
    ) -> Result<String, GitHubClientError> {
        let mutation = r"
            mutation($projectId: ID!, $contentId: ID!) {
                addProjectV2ItemByContentId(input: {projectId: $projectId, contentId: $contentId}) {
                    item {
                        id
                    }
                }
            }
        ";

        let variables = json!({
            "projectId": project_id,
            "contentId": issue_node_id
        });

        let response: GraphQLResponse<AddProjectItemData> =
            self.graphql_query(mutation, variables).await?;

        if let Some(errors) = response.errors {
            if !errors.is_empty() {
                return Err(GitHubClientError::GraphQLError(
                    errors
                        .into_iter()
                        .map(|e| e.message)
                        .collect::<Vec<_>>()
                        .join(", "),
                ));
            }
        }

        if let Some(data) = response.data {
            if let Some(payload) = data.add_project_v2_item_by_content_id {
                if let Some(item) = payload.item {
                    return Ok(item.id);
                }
            }
        }

        Err(GitHubClientError::AddItemFailed)
    }

    /// Update a single select field on a project item.
    pub async fn update_project_item_field(
        &self,
        project_id: &str,
        item_id: &str,
        field_id: &str,
        option_id: &str,
    ) -> Result<(), GitHubClientError> {
        let mutation = r"
            mutation($projectId: ID!, $itemId: ID!, $fieldId: ID!, $optionId: String!) {
                updateProjectV2ItemFieldValue(input: {
                    projectId: $projectId,
                    itemId: $itemId,
                    fieldId: $fieldId,
                    value: { singleSelectOptionId: $optionId }
                }) {
                    projectV2Item {
                        id
                    }
                }
            }
        ";

        let variables = json!({
            "projectId": project_id,
            "itemId": item_id,
            "fieldId": field_id,
            "optionId": option_id
        });

        let response: GraphQLResponse<UpdateProjectItemFieldData> =
            self.graphql_query(mutation, variables).await?;

        if let Some(errors) = response.errors {
            if !errors.is_empty() {
                return Err(GitHubClientError::GraphQLError(
                    errors
                        .into_iter()
                        .map(|e| e.message)
                        .collect::<Vec<_>>()
                        .join(", "),
                ));
            }
        }

        Ok(())
    }

    /// Execute a GraphQL query.
    async fn graphql_query<T: serde::de::DeserializeOwned>(
        &self,
        query: &str,
        variables: serde_json::Value,
    ) -> Result<GraphQLResponse<T>, GitHubClientError> {
        let body = json!({
            "query": query,
            "variables": variables
        });

        let response = self
            .client
            .post(&self.graphql_url)
            .json(&body)
            .send()
            .await?;

        let result: GraphQLResponse<T> = response.error_for_status()?.json().await?;

        Ok(result)
    }

    /// Add an issue to a project and set field defaults from config.
    pub async fn add_issue_to_project_with_defaults(
        &self,
        project: &ProjectV2,
        issue_node_id: &str,
        config: &ProjectConfig,
    ) -> Result<String, GitHubClientError> {
        // Add issue to project
        let item_id = self
            .add_issue_to_project(&project.id, issue_node_id)
            .await?;

        // Set field defaults
        if let Some(fields) = &project.fields {
            for (field_name, default_value) in &config.field_defaults {
                // Find the field
                let field = fields.nodes.iter().find(|f| match f {
                    ProjectField::SingleSelect(sf) => sf.name == *field_name,
                    _ => false,
                });

                if let Some(ProjectField::SingleSelect(single_select)) = field {
                    // Find the option
                    let option = single_select
                        .options
                        .iter()
                        .find(|o| o.name == *default_value);

                    if let Some(opt) = option {
                        self.update_project_item_field(
                            &project.id,
                            &item_id,
                            &single_select.id,
                            &opt.id,
                        )
                        .await?;
                    }
                }
            }
        }

        Ok(item_id)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_create_issue_request_serialization() {
        let request = CreateIssueRequest {
            title: "Test issue".to_string(),
            body: Some("Test body".to_string()),
            labels: Some(vec!["bug".to_string()]),
            milestone: None,
            assignees: None,
        };

        let json = serde_json::to_string(&request).unwrap();
        assert!(json.contains("\"title\":\"Test issue\""));
        assert!(json.contains("\"body\":\"Test body\""));
        assert!(json.contains("\"labels\":[\"bug\"]"));
        // milestone and assignees should not be present
        assert!(!json.contains("milestone"));
        assert!(!json.contains("assignees"));
    }
}
