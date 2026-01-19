import * as core from "@actions/core";
import type { GraphQLClient } from "../graphql/client.js";
import {
  UPDATE_DATE_FIELD,
  UPDATE_ITERATION_FIELD,
  UPDATE_NUMBER_FIELD,
  UPDATE_SINGLE_SELECT_FIELD,
  UPDATE_TEXT_FIELD,
} from "../graphql/mutations.js";
import type { FieldInfo, IterationInfo, UpdateFieldValueResponse } from "../types.js";
import { findFieldByName } from "./finder.js";

// Dynamic value constants
const DYNAMIC_TODAY = "@today";
const DYNAMIC_CURRENT_ITERATION = "@current_iteration";
const DYNAMIC_ITERATION_END = "@iteration_end";

// Cache for current iteration (to avoid recalculating)
let cachedCurrentIteration: IterationInfo | null = null;

/**
 * Get today's date in YYYY-MM-DD format
 */
function getToday(): string {
  const now = new Date();
  const isoString = now.toISOString();
  return isoString.substring(0, 10); // YYYY-MM-DD
}

/**
 * Find the current iteration based on today's date
 */
function findCurrentIteration(iterations: IterationInfo[]): IterationInfo | null {
  if (cachedCurrentIteration) {
    return cachedCurrentIteration;
  }

  const today = new Date(getToday());

  for (const iteration of iterations) {
    const startDate = new Date(iteration.startDate);
    const endDate = new Date(startDate);
    endDate.setDate(endDate.getDate() + iteration.duration - 1);

    if (today >= startDate && today <= endDate) {
      cachedCurrentIteration = iteration;
      return iteration;
    }
  }

  // If no current iteration found, return the next upcoming iteration
  const futureIterations = iterations
    .filter((i) => new Date(i.startDate) > today)
    .sort((a, b) => new Date(a.startDate).getTime() - new Date(b.startDate).getTime());

  const nextIteration = futureIterations[0];
  if (nextIteration) {
    core.info(`No current iteration found, using next upcoming: ${nextIteration.title}`);
    cachedCurrentIteration = nextIteration;
    return nextIteration;
  }

  return null;
}

/**
 * Calculate the end date of an iteration
 */
function getIterationEndDate(iteration: IterationInfo): string {
  const startDate = new Date(iteration.startDate);
  const endDate = new Date(startDate);
  endDate.setDate(endDate.getDate() + iteration.duration - 1);
  const isoString = endDate.toISOString();
  return isoString.substring(0, 10); // YYYY-MM-DD
}

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
export async function setFieldValue(params: SetFieldValueParams): Promise<boolean> {
  const { client, projectId, itemId, fields, fieldName, value } = params;

  core.info(`Setting field "${fieldName}" to "${value}"...`);

  // Find the field
  const field = findFieldByName(fields, fieldName);
  if (!field) {
    core.warning(`Field "${fieldName}" not found in project, skipping`);
    return false;
  }

  try {
    switch (field.dataType) {
      case "SINGLE_SELECT":
        return await setSingleSelectField(client, projectId, itemId, field, String(value));

      case "TEXT":
        return await setTextField(client, projectId, itemId, field, String(value));

      case "NUMBER":
        return await setNumberField(client, projectId, itemId, field, Number(value));

      case "ITERATION":
        return await setIterationField(client, projectId, itemId, field, String(value));

      case "DATE":
        return await setDateField(client, projectId, itemId, field, String(value), fields);

      default:
        core.warning(
          `Field type "${field.dataType}" is not supported for field "${fieldName}", skipping`,
        );
        return false;
    }
  } catch (error) {
    if (error instanceof Error) {
      core.warning(`Failed to set field "${fieldName}": ${error.message}`);
    }
    return false;
  }
}

/**
 * Set a single select field value
 */
async function setSingleSelectField(
  client: GraphQLClient,
  projectId: string,
  itemId: string,
  field: FieldInfo,
  value: string,
): Promise<boolean> {
  if (!field.options || field.options.length === 0) {
    core.warning(`Field "${field.name}" has no options defined`);
    return false;
  }

  // Find the option by name (case-insensitive)
  const lowerValue = value.toLowerCase();
  const option = field.options.find((o) => o.name.toLowerCase() === lowerValue);

  if (!option) {
    const availableOptions = field.options.map((o) => o.name).join(", ");
    core.warning(
      `Option "${value}" not found for field "${field.name}". ` +
        `Available options: ${availableOptions}`,
    );
    return false;
  }

  await client.mutate<UpdateFieldValueResponse>(UPDATE_SINGLE_SELECT_FIELD, {
    projectId,
    itemId,
    fieldId: field.id,
    optionId: option.id,
  });

  core.info(`Set "${field.name}" to "${option.name}"`);
  return true;
}

/**
 * Set a text field value
 */
async function setTextField(
  client: GraphQLClient,
  projectId: string,
  itemId: string,
  field: FieldInfo,
  value: string,
): Promise<boolean> {
  await client.mutate<UpdateFieldValueResponse>(UPDATE_TEXT_FIELD, {
    projectId,
    itemId,
    fieldId: field.id,
    text: value,
  });

  core.info(`Set "${field.name}" to "${value}"`);
  return true;
}

/**
 * Set a number field value
 */
async function setNumberField(
  client: GraphQLClient,
  projectId: string,
  itemId: string,
  field: FieldInfo,
  value: number,
): Promise<boolean> {
  if (Number.isNaN(value)) {
    core.warning(`Invalid number value for field "${field.name}"`);
    return false;
  }

  await client.mutate<UpdateFieldValueResponse>(UPDATE_NUMBER_FIELD, {
    projectId,
    itemId,
    fieldId: field.id,
    number: value,
  });

  core.info(`Set "${field.name}" to ${value}`);
  return true;
}

/**
 * Set an iteration field value
 * Supports dynamic value: @current_iteration
 */
async function setIterationField(
  client: GraphQLClient,
  projectId: string,
  itemId: string,
  field: FieldInfo,
  value: string,
): Promise<boolean> {
  if (!field.iterations || field.iterations.length === 0) {
    core.warning(`Field "${field.name}" has no iterations defined`);
    return false;
  }

  let iteration: IterationInfo | null | undefined;

  // Handle dynamic value: @current_iteration
  if (value === DYNAMIC_CURRENT_ITERATION) {
    iteration = findCurrentIteration(field.iterations);
    if (!iteration) {
      core.warning(`No current or upcoming iteration found for field "${field.name}"`);
      return false;
    }
    core.info(`Resolved ${DYNAMIC_CURRENT_ITERATION} to "${iteration.title}"`);
  } else {
    // Find the iteration by title (case-insensitive)
    const lowerValue = value.toLowerCase();
    iteration = field.iterations.find((i) => i.title.toLowerCase() === lowerValue);

    if (!iteration) {
      const availableIterations = field.iterations.map((i) => i.title).join(", ");
      core.warning(
        `Iteration "${value}" not found for field "${field.name}". ` +
          `Available iterations: ${availableIterations}`,
      );
      return false;
    }
  }

  await client.mutate<UpdateFieldValueResponse>(UPDATE_ITERATION_FIELD, {
    projectId,
    itemId,
    fieldId: field.id,
    iterationId: iteration.id,
  });

  core.info(`Set "${field.name}" to "${iteration.title}"`);
  return true;
}

/**
 * Set a date field value
 * Supports dynamic values: @today, @iteration_end
 */
async function setDateField(
  client: GraphQLClient,
  projectId: string,
  itemId: string,
  field: FieldInfo,
  value: string,
  allFields: FieldInfo[],
): Promise<boolean> {
  let resolvedValue = value;

  // Handle dynamic value: @today
  if (value === DYNAMIC_TODAY) {
    resolvedValue = getToday();
    core.info(`Resolved ${DYNAMIC_TODAY} to "${resolvedValue}"`);
  }
  // Handle dynamic value: @iteration_end
  else if (value === DYNAMIC_ITERATION_END) {
    // Find the Iteration field to get current iteration
    const iterationField = allFields.find((f) => f.dataType === "ITERATION");
    if (!iterationField || !iterationField.iterations || iterationField.iterations.length === 0) {
      core.warning(`Cannot resolve ${DYNAMIC_ITERATION_END}: No Iteration field found`);
      return false;
    }

    const currentIteration = findCurrentIteration(iterationField.iterations);
    if (!currentIteration) {
      core.warning(`Cannot resolve ${DYNAMIC_ITERATION_END}: No current iteration found`);
      return false;
    }

    resolvedValue = getIterationEndDate(currentIteration);
    core.info(
      `Resolved ${DYNAMIC_ITERATION_END} to "${resolvedValue}" (end of ${currentIteration.title})`,
    );
  }

  // Validate date format (YYYY-MM-DD)
  const dateRegex = /^\d{4}-\d{2}-\d{2}$/;
  if (!dateRegex.test(resolvedValue)) {
    core.warning(
      `Invalid date format for field "${field.name}". Expected YYYY-MM-DD, got "${resolvedValue}"`,
    );
    return false;
  }

  await client.mutate<UpdateFieldValueResponse>(UPDATE_DATE_FIELD, {
    projectId,
    itemId,
    fieldId: field.id,
    date: resolvedValue,
  });

  core.info(`Set "${field.name}" to "${resolvedValue}"`);
  return true;
}

/**
 * Set multiple field values
 */
export async function setFieldValues(
  client: GraphQLClient,
  projectId: string,
  itemId: string,
  fields: FieldInfo[],
  defaults: Record<string, string | number>,
): Promise<{ success: number; failed: number }> {
  let success = 0;
  let failed = 0;

  for (const [fieldName, value] of Object.entries(defaults)) {
    const result = await setFieldValue({
      client,
      projectId,
      itemId,
      fields,
      fieldName,
      value,
    });

    if (result) {
      success++;
    } else {
      failed++;
    }
  }

  return { success, failed };
}
