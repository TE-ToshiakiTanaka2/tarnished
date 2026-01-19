import type { GraphQLClient } from "../graphql/client.js";
/**
 * Check if an issue/PR is already in the project
 * Returns the item ID if found, null otherwise
 */
export declare function findItemInProject(client: GraphQLClient, projectId: string, contentId: string): Promise<string | null>;
/**
 * Add an issue/PR to the project
 */
export declare function addItemToProject(client: GraphQLClient, projectId: string, contentId: string): Promise<string>;
//# sourceMappingURL=item.d.ts.map