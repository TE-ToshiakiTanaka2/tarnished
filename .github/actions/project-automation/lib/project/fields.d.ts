import type { GraphQLClient } from "../graphql/client.js";
import type { FieldInfo } from "../types.js";
export interface SetFieldValueParams {
    client: GraphQLClient;
    projectId: string;
    itemId: string;
    fields: FieldInfo[];
    fieldName: string;
    value: string | number;
}
/**
 * Set a field value for a project item
 */
export declare function setFieldValue(params: SetFieldValueParams): Promise<boolean>;
/**
 * Set multiple field values
 */
export declare function setFieldValues(client: GraphQLClient, projectId: string, itemId: string, fields: FieldInfo[], defaults: Record<string, string | number>): Promise<{
    success: number;
    failed: number;
}>;
//# sourceMappingURL=fields.d.ts.map