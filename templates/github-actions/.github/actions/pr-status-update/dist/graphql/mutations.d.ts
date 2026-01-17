/**
 * GraphQL mutation to add an item to a project
 */
export declare const ADD_PROJECT_ITEM = "\n  mutation AddProjectItem($projectId: ID!, $contentId: ID!) {\n    addProjectV2ItemById(input: {\n      projectId: $projectId\n      contentId: $contentId\n    }) {\n      item {\n        id\n      }\n    }\n  }\n";
/**
 * GraphQL mutation to update a single select field value
 */
export declare const UPDATE_SINGLE_SELECT_FIELD = "\n  mutation UpdateSingleSelectField($projectId: ID!, $itemId: ID!, $fieldId: ID!, $optionId: String!) {\n    updateProjectV2ItemFieldValue(input: {\n      projectId: $projectId\n      itemId: $itemId\n      fieldId: $fieldId\n      value: {\n        singleSelectOptionId: $optionId\n      }\n    }) {\n      projectV2Item {\n        id\n      }\n    }\n  }\n";
/**
 * GraphQL mutation to update a text field value
 */
export declare const UPDATE_TEXT_FIELD = "\n  mutation UpdateTextField($projectId: ID!, $itemId: ID!, $fieldId: ID!, $text: String!) {\n    updateProjectV2ItemFieldValue(input: {\n      projectId: $projectId\n      itemId: $itemId\n      fieldId: $fieldId\n      value: {\n        text: $text\n      }\n    }) {\n      projectV2Item {\n        id\n      }\n    }\n  }\n";
/**
 * GraphQL mutation to update a number field value
 */
export declare const UPDATE_NUMBER_FIELD = "\n  mutation UpdateNumberField($projectId: ID!, $itemId: ID!, $fieldId: ID!, $number: Float!) {\n    updateProjectV2ItemFieldValue(input: {\n      projectId: $projectId\n      itemId: $itemId\n      fieldId: $fieldId\n      value: {\n        number: $number\n      }\n    }) {\n      projectV2Item {\n        id\n      }\n    }\n  }\n";
/**
 * GraphQL mutation to update an iteration field value
 */
export declare const UPDATE_ITERATION_FIELD = "\n  mutation UpdateIterationField($projectId: ID!, $itemId: ID!, $fieldId: ID!, $iterationId: String!) {\n    updateProjectV2ItemFieldValue(input: {\n      projectId: $projectId\n      itemId: $itemId\n      fieldId: $fieldId\n      value: {\n        iterationId: $iterationId\n      }\n    }) {\n      projectV2Item {\n        id\n      }\n    }\n  }\n";
/**
 * GraphQL mutation to update a date field value
 */
export declare const UPDATE_DATE_FIELD = "\n  mutation UpdateDateField($projectId: ID!, $itemId: ID!, $fieldId: ID!, $date: Date!) {\n    updateProjectV2ItemFieldValue(input: {\n      projectId: $projectId\n      itemId: $itemId\n      fieldId: $fieldId\n      value: {\n        date: $date\n      }\n    }) {\n      projectV2Item {\n        id\n      }\n    }\n  }\n";
//# sourceMappingURL=mutations.d.ts.map