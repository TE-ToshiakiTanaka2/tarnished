import * as core from "@actions/core";
import { ADD_PROJECT_ITEM } from "../graphql/mutations.js";
import { GET_PROJECT_ITEMS } from "../graphql/queries.js";
/**
 * Check if an issue/PR is already in the project
 * Returns the item ID if found, null otherwise
 */
export async function findItemInProject(client, projectId, contentId) {
    core.info("Checking if item already exists in project...");
    let cursor = null;
    let shouldContinue = true;
    while (shouldContinue) {
        const queryResponse = await client.query(GET_PROJECT_ITEMS, { projectId, cursor });
        const nodeData = queryResponse.node;
        if (!nodeData || !nodeData.items) {
            core.warning("Could not retrieve project items");
            return null;
        }
        const { nodes, pageInfo } = nodeData.items;
        // Check if the content ID matches any item
        for (const item of nodes) {
            if (item.content?.id === contentId) {
                core.info(`Item already exists in project: ${item.id}`);
                return item.id;
            }
        }
        shouldContinue = pageInfo.hasNextPage;
        cursor = pageInfo.endCursor;
    }
    core.info("Item not found in project");
    return null;
}
/**
 * Add an issue/PR to the project
 */
export async function addItemToProject(client, projectId, contentId) {
    core.info("Adding item to project...");
    const response = await client.mutate(ADD_PROJECT_ITEM, {
        projectId,
        contentId,
    });
    const itemId = response.addProjectV2ItemById.item.id;
    core.info(`Item added to project: ${itemId}`);
    return itemId;
}
//# sourceMappingURL=item.js.map