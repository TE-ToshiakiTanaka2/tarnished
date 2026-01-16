import * as core from '@actions/core';
import { GraphQLClient } from '../graphql/client.js';
import { GET_PROJECT_ITEMS } from '../graphql/queries.js';
import { ADD_PROJECT_ITEM } from '../graphql/mutations.js';
import type { GetProjectItemsResponse, AddProjectItemResponse } from '../types.js';

/**
 * Check if an issue/PR is already in the project
 * Returns the item ID if found, null otherwise
 */
export async function findItemInProject(
  client: GraphQLClient,
  projectId: string,
  contentId: string
): Promise<string | null> {
  core.info('Checking if item already exists in project...');

  let cursor: string | null = null;
  let shouldContinue: boolean = true;

  while (shouldContinue) {
    const queryResponse: GetProjectItemsResponse = await client.query<GetProjectItemsResponse>(
      GET_PROJECT_ITEMS,
      { projectId, cursor }
    );

    const nodeData = queryResponse.node;
    if (!nodeData || !nodeData.items) {
      core.warning('Could not retrieve project items');
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

  core.info('Item not found in project');
  return null;
}

/**
 * Add an issue/PR to the project
 */
export async function addItemToProject(
  client: GraphQLClient,
  projectId: string,
  contentId: string
): Promise<string> {
  core.info('Adding item to project...');

  const response = await client.mutate<AddProjectItemResponse>(
    ADD_PROJECT_ITEM,
    { projectId, contentId }
  );

  const itemId = response.addProjectV2ItemById.item.id;
  core.info(`Item added to project: ${itemId}`);

  return itemId;
}
