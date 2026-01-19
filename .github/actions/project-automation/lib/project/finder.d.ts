import type { GraphQLClient } from "../graphql/client.js";
import type { FieldInfo, ProjectConfig, ProjectInfo } from "../types.js";
/**
 * Find a project and retrieve its information including fields
 */
export declare function findProject(client: GraphQLClient, config: ProjectConfig): Promise<ProjectInfo>;
/**
 * Find a field by name (case-insensitive)
 */
export declare function findFieldByName(fields: FieldInfo[], name: string): FieldInfo | undefined;
//# sourceMappingURL=finder.d.ts.map