/**
 * GraphQL query to get organization project information
 */
export declare const GET_ORGANIZATION_PROJECT = "\n  query GetOrganizationProject($owner: String!, $number: Int!) {\n    organization(login: $owner) {\n      projectV2(number: $number) {\n        id\n        title\n        fields(first: 50) {\n          nodes {\n            ... on ProjectV2Field {\n              __typename\n              id\n              name\n              dataType\n            }\n            ... on ProjectV2SingleSelectField {\n              __typename\n              id\n              name\n              dataType\n              options {\n                id\n                name\n              }\n            }\n            ... on ProjectV2IterationField {\n              __typename\n              id\n              name\n              dataType\n              configuration {\n                iterations {\n                  id\n                  title\n                }\n              }\n            }\n          }\n        }\n      }\n    }\n  }\n";
/**
 * GraphQL query to get user (repository) project information
 */
export declare const GET_USER_PROJECT = "\n  query GetUserProject($owner: String!, $number: Int!) {\n    user(login: $owner) {\n      projectV2(number: $number) {\n        id\n        title\n        fields(first: 50) {\n          nodes {\n            ... on ProjectV2Field {\n              __typename\n              id\n              name\n              dataType\n            }\n            ... on ProjectV2SingleSelectField {\n              __typename\n              id\n              name\n              dataType\n              options {\n                id\n                name\n              }\n            }\n            ... on ProjectV2IterationField {\n              __typename\n              id\n              name\n              dataType\n              configuration {\n                iterations {\n                  id\n                  title\n                }\n              }\n            }\n          }\n        }\n      }\n    }\n  }\n";
/**
 * GraphQL query to get project items for idempotency check
 */
export declare const GET_PROJECT_ITEMS = "\n  query GetProjectItems($projectId: ID!, $cursor: String) {\n    node(id: $projectId) {\n      ... on ProjectV2 {\n        items(first: 100, after: $cursor) {\n          nodes {\n            id\n            content {\n              ... on Issue {\n                id\n              }\n              ... on PullRequest {\n                id\n              }\n            }\n          }\n          pageInfo {\n            hasNextPage\n            endCursor\n          }\n        }\n      }\n    }\n  }\n";
/**
 * GraphQL query to get issue by number
 */
export declare const GET_ISSUE_BY_NUMBER = "\n  query GetIssueByNumber($owner: String!, $repo: String!, $number: Int!) {\n    repository(owner: $owner, name: $repo) {\n      issue(number: $number) {\n        id\n        number\n        title\n        state\n      }\n    }\n  }\n";
//# sourceMappingURL=queries.d.ts.map