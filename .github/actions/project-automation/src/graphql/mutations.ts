/**
 * GraphQL mutation to add an item to a project
 */
export const ADD_PROJECT_ITEM = `
  mutation AddProjectItem($projectId: ID!, $contentId: ID!) {
    addProjectV2ItemById(input: {
      projectId: $projectId
      contentId: $contentId
    }) {
      item {
        id
      }
    }
  }
`;

/**
 * GraphQL mutation to update a single select field value
 */
export const UPDATE_SINGLE_SELECT_FIELD = `
  mutation UpdateSingleSelectField($projectId: ID!, $itemId: ID!, $fieldId: ID!, $optionId: String!) {
    updateProjectV2ItemFieldValue(input: {
      projectId: $projectId
      itemId: $itemId
      fieldId: $fieldId
      value: {
        singleSelectOptionId: $optionId
      }
    }) {
      projectV2Item {
        id
      }
    }
  }
`;

/**
 * GraphQL mutation to update a text field value
 */
export const UPDATE_TEXT_FIELD = `
  mutation UpdateTextField($projectId: ID!, $itemId: ID!, $fieldId: ID!, $text: String!) {
    updateProjectV2ItemFieldValue(input: {
      projectId: $projectId
      itemId: $itemId
      fieldId: $fieldId
      value: {
        text: $text
      }
    }) {
      projectV2Item {
        id
      }
    }
  }
`;

/**
 * GraphQL mutation to update a number field value
 */
export const UPDATE_NUMBER_FIELD = `
  mutation UpdateNumberField($projectId: ID!, $itemId: ID!, $fieldId: ID!, $number: Float!) {
    updateProjectV2ItemFieldValue(input: {
      projectId: $projectId
      itemId: $itemId
      fieldId: $fieldId
      value: {
        number: $number
      }
    }) {
      projectV2Item {
        id
      }
    }
  }
`;

/**
 * GraphQL mutation to update an iteration field value
 */
export const UPDATE_ITERATION_FIELD = `
  mutation UpdateIterationField($projectId: ID!, $itemId: ID!, $fieldId: ID!, $iterationId: String!) {
    updateProjectV2ItemFieldValue(input: {
      projectId: $projectId
      itemId: $itemId
      fieldId: $fieldId
      value: {
        iterationId: $iterationId
      }
    }) {
      projectV2Item {
        id
      }
    }
  }
`;

/**
 * GraphQL mutation to update a date field value
 */
export const UPDATE_DATE_FIELD = `
  mutation UpdateDateField($projectId: ID!, $itemId: ID!, $fieldId: ID!, $date: Date!) {
    updateProjectV2ItemFieldValue(input: {
      projectId: $projectId
      itemId: $itemId
      fieldId: $fieldId
      value: {
        date: $date
      }
    }) {
      projectV2Item {
        id
      }
    }
  }
`;
