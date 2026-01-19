import * as core from "@actions/core";
import type { GraphQLClient } from "../graphql/client.js";
import { GET_ORGANIZATION_PROJECT, GET_USER_PROJECT } from "../graphql/queries.js";
import type {
  FieldInfo,
  GetProjectResponse,
  ProjectConfig,
  ProjectInfo,
  ProjectV2FieldNode,
} from "../types.js";

/**
 * Find a project and retrieve its information including fields
 */
export async function findProject(
  client: GraphQLClient,
  config: ProjectConfig,
): Promise<ProjectInfo> {
  const { type, owner, number } = config.project;

  core.info(`Finding ${type} project: ${owner}/#${number}`);

  const query = type === "organization" ? GET_ORGANIZATION_PROJECT : GET_USER_PROJECT;
  const response = await client.query<GetProjectResponse>(query, { owner, number });

  const projectNode =
    type === "organization" ? response.organization?.projectV2 : response.user?.projectV2;

  if (!projectNode) {
    throw new Error(
      `Project not found: ${owner}/#${number}. Make sure the project exists and the token has access to it.`,
    );
  }

  const fields = parseFields(projectNode.fields.nodes);

  core.info(`Found project: "${projectNode.title}" (${projectNode.id})`);
  core.info(`Found ${fields.length} fields`);

  return {
    id: projectNode.id,
    title: projectNode.title,
    fields,
  };
}

/**
 * Parse field nodes from GraphQL response
 */
function parseFields(nodes: ProjectV2FieldNode[]): FieldInfo[] {
  return nodes
    .filter((node): node is ProjectV2FieldNode => node.id != null)
    .map((node) => {
      const field: FieldInfo = {
        id: node.id,
        name: node.name,
        dataType: node.dataType ?? "TEXT",
      };

      // Add options for single select fields
      if (node.options) {
        field.options = node.options;
      }

      // Add iterations for iteration fields
      if (node.configuration?.iterations) {
        field.iterations = node.configuration.iterations;
      }

      return field;
    });
}

/**
 * Find a field by name (case-insensitive)
 */
export function findFieldByName(fields: FieldInfo[], name: string): FieldInfo | undefined {
  const lowerName = name.toLowerCase();
  return fields.find((f) => f.name.toLowerCase() === lowerName);
}
