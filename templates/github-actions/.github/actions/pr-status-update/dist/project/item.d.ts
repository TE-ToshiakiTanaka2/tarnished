import { GraphQLClient } from '../graphql/client.js';
/**
 * Check if an issue/PR is already in the project
 * Returns the item ID if found, null otherwise
 */
export declare function findItemInProject(client: GraphQLClient, projectId: string, contentId: string): Promise<string | null>;
/**
 * Add an issue/PR to the project
 */
export declare function addItemToProject(client: GraphQLClient, projectId: string, contentId: string): Promise<string>;
/**
 * Get issue node ID by issue number
 */
export declare function getIssueNodeId(client: GraphQLClient, owner: string, repo: string, issueNumber: number): Promise<string | null>;
//# sourceMappingURL=item.d.ts.map