//! GitHub API client implementation.
//!
//! Provides both REST API and GraphQL API functionality for GitHub operations.

use reqwest::header::{HeaderMap, HeaderValue, ACCEPT, AUTHORIZATION, USER_AGENT};
use serde_json::json;

use super::types::{
    AddProjectItemData, CreateIssueRequest, CreateIssueResponse, GetIssueResponse, GraphQLResponse,
    IssueProjectItemsData, Iteration, LinkedIssue, PrLinkedIssuesData, ProjectField,
    ProjectQueryData, ProjectV2, StandardField, UpdateProjectItemFieldData,
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

    /// Iteration not found
    #[error("Iteration '{iteration}' not found in field '{field}'")]
    IterationNotFound { field: String, iteration: String },

    /// Failed to add item to project
    #[error("Failed to add item to project")]
    AddItemFailed,

    /// Failed to update field
    #[error("Failed to update field '{field}'")]
    UpdateFieldFailed { field: String },

    /// Date parse error
    #[error("Failed to parse date: {0}")]
    DateParseError(String),
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

    /// Get an issue via REST API.
    pub async fn get_issue(
        &self,
        owner: &str,
        repo: &str,
        issue_number: u64,
    ) -> Result<GetIssueResponse, GitHubClientError> {
        let url = format!(
            "{}/repos/{owner}/{repo}/issues/{issue_number}",
            self.rest_base_url
        );

        let response = self.client.get(&url).send().await?;

        let issue: GetIssueResponse = response.error_for_status()?.json().await?;

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
                                __typename
                                ... on ProjectV2SingleSelectField {
                                    id
                                    name
                                    options {
                                        id
                                        name
                                    }
                                }
                                ... on ProjectV2IterationField {
                                    id
                                    name
                                    configuration {
                                        iterations {
                                            id
                                            title
                                            startDate
                                            duration
                                        }
                                    }
                                }
                                ... on ProjectV2Field {
                                    id
                                    name
                                    dataType
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
                                __typename
                                ... on ProjectV2SingleSelectField {
                                    id
                                    name
                                    options {
                                        id
                                        name
                                    }
                                }
                                ... on ProjectV2IterationField {
                                    id
                                    name
                                    configuration {
                                        iterations {
                                            id
                                            title
                                            startDate
                                            duration
                                        }
                                    }
                                }
                                ... on ProjectV2Field {
                                    id
                                    name
                                    dataType
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
                addProjectV2ItemById(input: {projectId: $projectId, contentId: $contentId}) {
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
            if let Some(payload) = data.add_project_v2_item_by_id {
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

    /// Update an iteration field on a project item.
    pub async fn update_project_item_iteration(
        &self,
        project_id: &str,
        item_id: &str,
        field_id: &str,
        iteration_id: &str,
    ) -> Result<(), GitHubClientError> {
        let mutation = r"
            mutation($projectId: ID!, $itemId: ID!, $fieldId: ID!, $iterationId: String!) {
                updateProjectV2ItemFieldValue(input: {
                    projectId: $projectId,
                    itemId: $itemId,
                    fieldId: $fieldId,
                    value: { iterationId: $iterationId }
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
            "iterationId": iteration_id
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

    /// Update a date field on a project item.
    pub async fn update_project_item_date(
        &self,
        project_id: &str,
        item_id: &str,
        field_id: &str,
        date: &str,
    ) -> Result<(), GitHubClientError> {
        let mutation = r"
            mutation($projectId: ID!, $itemId: ID!, $fieldId: ID!, $date: Date!) {
                updateProjectV2ItemFieldValue(input: {
                    projectId: $projectId,
                    itemId: $itemId,
                    fieldId: $fieldId,
                    value: { date: $date }
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
            "date": date
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

    /// Find an iteration by name or resolve "current"/"next".
    ///
    /// Returns the iteration if found, None otherwise.
    pub fn resolve_iteration(iterations: &[Iteration], value: &str) -> Option<Iteration> {
        let value_lower = value.to_lowercase();
        let today = chrono::Local::now().format("%Y-%m-%d").to_string();

        match value_lower.as_str() {
            "current" => {
                // Find iteration containing today's date
                iterations.iter().find(|i| i.contains_date(&today)).cloned()
            }
            "next" => {
                // Find first iteration after current
                let current_idx = iterations.iter().position(|i| i.contains_date(&today));

                match current_idx {
                    Some(idx) if idx + 1 < iterations.len() => Some(iterations[idx + 1].clone()),
                    None => {
                        // No current iteration, find first future iteration
                        iterations.iter().find(|i| i.start_date > today).cloned()
                    }
                    _ => None,
                }
            }
            _ => {
                // Find by exact name match (case-insensitive)
                iterations
                    .iter()
                    .find(|i| i.title.to_lowercase() == value_lower)
                    .cloned()
            }
        }
    }

    /// Find a date field by name in the project fields.
    pub fn find_date_field<'a>(
        fields: &'a [ProjectField],
        name: &str,
    ) -> Option<&'a StandardField> {
        let name_lower = name.to_lowercase();
        fields.iter().find_map(|f| match f {
            ProjectField::Field(sf)
                if sf.name.to_lowercase() == name_lower
                    && sf.data_type.as_deref() == Some("DATE") =>
            {
                Some(sf)
            }
            _ => None,
        })
    }

    /// Find an iteration field by name in the project fields.
    #[allow(dead_code)]
    pub fn find_iteration_field<'a>(
        fields: &'a [ProjectField],
        name: &str,
    ) -> Option<&'a super::types::IterationField> {
        let name_lower = name.to_lowercase();
        fields.iter().find_map(|f| match f {
            ProjectField::Iteration(it) if it.name.to_lowercase() == name_lower => Some(it),
            _ => None,
        })
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

    /// Get linked issues for a pull request.
    ///
    /// Uses the `closingIssuesReferences` field to find issues that will be
    /// closed when the PR is merged.
    pub async fn get_pr_linked_issues(
        &self,
        owner: &str,
        repo: &str,
        pr_number: u64,
    ) -> Result<Vec<LinkedIssue>, GitHubClientError> {
        let query = r"
            query($owner: String!, $repo: String!, $prNumber: Int!) {
                repository(owner: $owner, name: $repo) {
                    pullRequest(number: $prNumber) {
                        id
                        number
                        title
                        closingIssuesReferences(first: 50) {
                            totalCount
                            nodes {
                                id
                                number
                                title
                            }
                        }
                    }
                }
            }
        ";

        let variables = json!({
            "owner": owner,
            "repo": repo,
            "prNumber": pr_number
        });

        let response: GraphQLResponse<PrLinkedIssuesData> =
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
            if let Some(repo_data) = data.repository {
                if let Some(pr) = repo_data.pull_request {
                    if let Some(closing_refs) = pr.closing_issues_references {
                        return Ok(closing_refs.nodes);
                    }
                }
            }
        }

        Ok(vec![])
    }

    /// Get the project item ID for an issue in a specific project.
    ///
    /// Returns the item ID if the issue is in the project, None otherwise.
    pub async fn get_issue_project_item_id(
        &self,
        issue_node_id: &str,
        project_number: u32,
    ) -> Result<Option<String>, GitHubClientError> {
        let query = r"
            query($nodeId: ID!) {
                node(id: $nodeId) {
                    ... on Issue {
                        projectItems(first: 20) {
                            nodes {
                                id
                                project {
                                    id
                                    number
                                }
                            }
                        }
                    }
                }
            }
        ";

        let variables = json!({
            "nodeId": issue_node_id
        });

        let response: GraphQLResponse<IssueProjectItemsData> =
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
            if let Some(node) = data.node {
                if let Some(project_items) = node.project_items {
                    for item in project_items.nodes {
                        if item.project.number == project_number {
                            return Ok(Some(item.id));
                        }
                    }
                }
            }
        }

        Ok(None)
    }

    /// Add an issue to a project and set field defaults from config.
    ///
    /// This method:
    /// 1. Adds the issue to the project
    /// 2. Sets single-select field defaults (Status, Size, Priority, etc.)
    /// 3. Sets schedule defaults (Iteration, Start, End) if configured
    #[allow(clippy::too_many_lines)]
    pub async fn add_issue_to_project_with_defaults(
        &self,
        project: &ProjectV2,
        issue_node_id: &str,
        config: &ProjectConfig,
        verbose: bool,
    ) -> Result<String, GitHubClientError> {
        // Add issue to project
        let item_id = self
            .add_issue_to_project(&project.id, issue_node_id)
            .await?;

        let Some(fields) = &project.fields else {
            return Ok(item_id);
        };

        // Set single-select field defaults
        for (field_name, default_value) in &config.field_defaults {
            let field = fields.nodes.iter().find(|f| match f {
                ProjectField::SingleSelect(sf) => sf.name == *field_name,
                _ => false,
            });

            if let Some(ProjectField::SingleSelect(single_select)) = field {
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

        // Set schedule defaults if configured
        if let Some(schedule) = &config.schedule_defaults {
            // Track resolved iteration for date derivation
            let mut resolved_iteration: Option<Iteration> = None;

            // Handle Iteration field
            if let Some(iteration_value) = &schedule.iteration {
                // Find the first Iteration field in the project
                let iteration_field = fields.nodes.iter().find_map(|f| match f {
                    ProjectField::Iteration(it) => Some(it),
                    _ => None,
                });

                if let Some(it_field) = iteration_field {
                    if let Some(config) = &it_field.configuration {
                        if let Some(iteration) =
                            Self::resolve_iteration(&config.iterations, iteration_value)
                        {
                            if verbose {
                                eprintln!(
                                    "  Setting Iteration to '{}' ({})",
                                    iteration.title, iteration.id
                                );
                            }
                            self.update_project_item_iteration(
                                &project.id,
                                &item_id,
                                &it_field.id,
                                &iteration.id,
                            )
                            .await?;
                            resolved_iteration = Some(iteration);
                        } else if verbose {
                            eprintln!(
                                "  Warning: Iteration '{}' not found in field '{}'",
                                iteration_value, it_field.name
                            );
                        }
                    }
                }
            }

            // Handle Start date field
            if let Some(start_value) = &schedule.start {
                self.set_date_field(
                    &project.id,
                    &item_id,
                    &fields.nodes,
                    "Start",
                    start_value,
                    resolved_iteration.as_ref().map(|i| i.start_date.as_str()),
                    verbose,
                )
                .await?;
            } else if let Some(ref iteration) = resolved_iteration {
                // Derive from iteration if no explicit start
                self.set_date_field(
                    &project.id,
                    &item_id,
                    &fields.nodes,
                    "Start",
                    &iteration.start_date,
                    None,
                    verbose,
                )
                .await?;
            }

            // Handle End date field
            if let Some(end_value) = &schedule.end {
                self.set_date_field(
                    &project.id,
                    &item_id,
                    &fields.nodes,
                    "End",
                    end_value,
                    resolved_iteration
                        .as_ref()
                        .and_then(Iteration::end_date)
                        .as_deref(),
                    verbose,
                )
                .await?;
            } else if let Some(ref iteration) = resolved_iteration {
                // Derive from iteration if no explicit end
                if let Some(end_date) = iteration.end_date() {
                    self.set_date_field(
                        &project.id,
                        &item_id,
                        &fields.nodes,
                        "End",
                        &end_date,
                        None,
                        verbose,
                    )
                    .await?;
                }
            }
        }

        Ok(item_id)
    }

    /// Helper to set a date field with flexible field name matching.
    ///
    /// Tries to find a DATE field with the given name (case-insensitive).
    /// If not found, tries common alternatives (e.g., "Start" -> "Start date").
    #[allow(clippy::too_many_arguments)]
    async fn set_date_field(
        &self,
        project_id: &str,
        item_id: &str,
        fields: &[ProjectField],
        field_name: &str,
        value: &str,
        _fallback: Option<&str>,
        verbose: bool,
    ) -> Result<(), GitHubClientError> {
        use crate::date_parser::parse_date_expression;

        // Try to find the field with exact name or common alternatives
        let field_names = [
            field_name.to_string(),
            format!("{field_name} date"),
            format!("{field_name}_date"),
        ];

        let date_field = field_names
            .iter()
            .find_map(|name| Self::find_date_field(fields, name));

        let Some(date_field) = date_field else {
            if verbose {
                eprintln!("  Note: No DATE field matching '{field_name}' found");
            }
            return Ok(());
        };

        // Parse the date expression
        let date = parse_date_expression(value)
            .map_err(|e| GitHubClientError::DateParseError(e.to_string()))?;

        if verbose {
            eprintln!("  Setting {} to '{}'", date_field.name, date);
        }

        self.update_project_item_date(project_id, item_id, &date_field.id, &date)
            .await
    }

    /// Get projects linked to a repository.
    pub async fn get_repository_projects(
        &self,
        owner: &str,
        repo: &str,
    ) -> Result<Vec<super::types::ProjectV2Summary>, GitHubClientError> {
        let query = r"
            query($owner: String!, $repo: String!) {
                repository(owner: $owner, name: $repo) {
                    projectsV2(first: 20) {
                        nodes {
                            id
                            number
                            title
                            url
                            closed
                            owner {
                                ... on User { login }
                                ... on Organization { login }
                            }
                        }
                    }
                }
            }
        ";

        let variables = json!({
            "owner": owner,
            "repo": repo
        });

        let response: GraphQLResponse<super::types::RepositoryProjectsData> =
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
            if let Some(repo_data) = data.repository {
                if let Some(projects) = repo_data.projects_v2 {
                    return Ok(projects.nodes);
                }
            }
        }

        Ok(vec![])
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

    fn make_iteration(id: &str, title: &str, start: &str, duration: u32) -> Iteration {
        Iteration {
            id: id.to_string(),
            title: title.to_string(),
            start_date: start.to_string(),
            duration,
        }
    }

    #[test]
    fn test_resolve_iteration_by_name() {
        let iterations = vec![
            make_iteration("1", "Sprint 1", "2024-01-01", 14),
            make_iteration("2", "Sprint 2", "2024-01-15", 14),
            make_iteration("3", "Sprint 3", "2024-01-29", 14),
        ];

        let result = GitHubClient::resolve_iteration(&iterations, "Sprint 2");
        assert!(result.is_some());
        assert_eq!(result.unwrap().id, "2");
    }

    #[test]
    fn test_resolve_iteration_by_name_case_insensitive() {
        let iterations = vec![make_iteration("1", "Sprint 1", "2024-01-01", 14)];

        let result = GitHubClient::resolve_iteration(&iterations, "sprint 1");
        assert!(result.is_some());
        assert_eq!(result.unwrap().id, "1");
    }

    #[test]
    fn test_resolve_iteration_not_found() {
        let iterations = vec![make_iteration("1", "Sprint 1", "2024-01-01", 14)];

        let result = GitHubClient::resolve_iteration(&iterations, "Sprint 99");
        assert!(result.is_none());
    }

    #[test]
    fn test_find_date_field() {
        let fields = vec![
            ProjectField::Field(StandardField {
                id: "f1".to_string(),
                name: "Start".to_string(),
                data_type: Some("DATE".to_string()),
            }),
            ProjectField::Field(StandardField {
                id: "f2".to_string(),
                name: "End".to_string(),
                data_type: Some("DATE".to_string()),
            }),
            ProjectField::Field(StandardField {
                id: "f3".to_string(),
                name: "Title".to_string(),
                data_type: Some("TITLE".to_string()),
            }),
        ];

        let result = GitHubClient::find_date_field(&fields, "Start");
        assert!(result.is_some());
        assert_eq!(result.unwrap().id, "f1");

        let result = GitHubClient::find_date_field(&fields, "end");
        assert!(result.is_some());
        assert_eq!(result.unwrap().id, "f2");

        let result = GitHubClient::find_date_field(&fields, "Title");
        assert!(result.is_none()); // Not a DATE field
    }

    #[test]
    fn test_find_date_field_not_found() {
        let fields = vec![ProjectField::Field(StandardField {
            id: "f1".to_string(),
            name: "Start".to_string(),
            data_type: Some("DATE".to_string()),
        })];

        let result = GitHubClient::find_date_field(&fields, "Due Date");
        assert!(result.is_none());
    }
}
