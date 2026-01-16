/**
 * Configuration file schema for project-automation
 */
export interface ProjectConfig {
    project: {
        /** Project type: 'organization' or 'repository' */
        type: 'organization' | 'repository';
        /** Owner name (organization or user) */
        owner: string;
        /** Project number */
        number: number;
    };
    /** Default field values to set */
    defaults?: Record<string, string | number>;
}
/**
 * Project information from GraphQL API
 */
export interface ProjectInfo {
    id: string;
    title: string;
    fields: FieldInfo[];
}
/**
 * Field information from GraphQL API
 */
export interface FieldInfo {
    id: string;
    name: string;
    dataType: FieldDataType;
    options?: FieldOption[];
    iterations?: IterationInfo[];
}
export type FieldDataType = 'TEXT' | 'NUMBER' | 'DATE' | 'SINGLE_SELECT' | 'ITERATION' | 'LABELS' | 'LINKED_PULL_REQUESTS' | 'TRACKS' | 'TRACKED_BY' | 'REVIEWERS' | 'REPOSITORY' | 'MILESTONE' | 'ASSIGNEES';
export interface FieldOption {
    id: string;
    name: string;
}
export interface IterationInfo {
    id: string;
    title: string;
}
/**
 * Project item information
 */
export interface ProjectItem {
    id: string;
    contentId?: string;
}
/**
 * GraphQL response types
 */
export interface GetProjectResponse {
    organization?: {
        projectV2: ProjectV2Node | null;
    };
    user?: {
        projectV2: ProjectV2Node | null;
    };
}
export interface ProjectV2Node {
    id: string;
    title: string;
    fields: {
        nodes: Array<ProjectV2FieldNode>;
    };
}
export interface ProjectV2FieldNode {
    __typename?: string;
    id: string;
    name: string;
    dataType?: FieldDataType;
    options?: FieldOption[];
    configuration?: {
        iterations: IterationInfo[];
    };
}
export interface GetProjectItemsResponse {
    node: {
        items: {
            nodes: Array<{
                id: string;
                content: {
                    id: string;
                } | null;
            }>;
            pageInfo: {
                hasNextPage: boolean;
                endCursor: string | null;
            };
        };
    } | null;
}
export interface AddProjectItemResponse {
    addProjectV2ItemById: {
        item: {
            id: string;
        };
    };
}
export interface UpdateFieldValueResponse {
    updateProjectV2ItemFieldValue: {
        projectV2Item: {
            id: string;
        };
    };
}
/**
 * Field value input for mutations
 */
export type FieldValueInput = {
    text: string;
} | {
    number: number;
} | {
    date: string;
} | {
    singleSelectOptionId: string;
} | {
    iterationId: string;
};
