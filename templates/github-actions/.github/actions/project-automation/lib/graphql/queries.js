/**
 * GraphQL query to get organization project information
 */
export const GET_ORGANIZATION_PROJECT = `
  query GetOrganizationProject($owner: String!, $number: Int!) {
    organization(login: $owner) {
      projectV2(number: $number) {
        id
        title
        fields(first: 50) {
          nodes {
            ... on ProjectV2Field {
              __typename
              id
              name
              dataType
            }
            ... on ProjectV2SingleSelectField {
              __typename
              id
              name
              dataType
              options {
                id
                name
              }
            }
            ... on ProjectV2IterationField {
              __typename
              id
              name
              dataType
              configuration {
                iterations {
                  id
                  title
                }
              }
            }
          }
        }
      }
    }
  }
`;
/**
 * GraphQL query to get user (repository) project information
 */
export const GET_USER_PROJECT = `
  query GetUserProject($owner: String!, $number: Int!) {
    user(login: $owner) {
      projectV2(number: $number) {
        id
        title
        fields(first: 50) {
          nodes {
            ... on ProjectV2Field {
              __typename
              id
              name
              dataType
            }
            ... on ProjectV2SingleSelectField {
              __typename
              id
              name
              dataType
              options {
                id
                name
              }
            }
            ... on ProjectV2IterationField {
              __typename
              id
              name
              dataType
              configuration {
                iterations {
                  id
                  title
                }
              }
            }
          }
        }
      }
    }
  }
`;
/**
 * GraphQL query to get project items for idempotency check
 */
export const GET_PROJECT_ITEMS = `
  query GetProjectItems($projectId: ID!, $cursor: String) {
    node(id: $projectId) {
      ... on ProjectV2 {
        items(first: 100, after: $cursor) {
          nodes {
            id
            content {
              ... on Issue {
                id
              }
              ... on PullRequest {
                id
              }
            }
          }
          pageInfo {
            hasNextPage
            endCursor
          }
        }
      }
    }
  }
`;
//# sourceMappingURL=queries.js.map