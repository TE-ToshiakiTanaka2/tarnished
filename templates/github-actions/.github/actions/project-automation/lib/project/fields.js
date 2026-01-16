import * as core from '@actions/core';
import { UPDATE_SINGLE_SELECT_FIELD, UPDATE_TEXT_FIELD, UPDATE_NUMBER_FIELD, UPDATE_ITERATION_FIELD, UPDATE_DATE_FIELD, } from '../graphql/mutations.js';
import { findFieldByName } from './finder.js';
/**
 * Set a field value for a project item
 */
export async function setFieldValue(params) {
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
            case 'SINGLE_SELECT':
                return await setSingleSelectField(client, projectId, itemId, field, String(value));
            case 'TEXT':
                return await setTextField(client, projectId, itemId, field, String(value));
            case 'NUMBER':
                return await setNumberField(client, projectId, itemId, field, Number(value));
            case 'ITERATION':
                return await setIterationField(client, projectId, itemId, field, String(value));
            case 'DATE':
                return await setDateField(client, projectId, itemId, field, String(value));
            default:
                core.warning(`Field type "${field.dataType}" is not supported for field "${fieldName}", skipping`);
                return false;
        }
    }
    catch (error) {
        if (error instanceof Error) {
            core.warning(`Failed to set field "${fieldName}": ${error.message}`);
        }
        return false;
    }
}
/**
 * Set a single select field value
 */
async function setSingleSelectField(client, projectId, itemId, field, value) {
    if (!field.options || field.options.length === 0) {
        core.warning(`Field "${field.name}" has no options defined`);
        return false;
    }
    // Find the option by name (case-insensitive)
    const lowerValue = value.toLowerCase();
    const option = field.options.find((o) => o.name.toLowerCase() === lowerValue);
    if (!option) {
        const availableOptions = field.options.map((o) => o.name).join(', ');
        core.warning(`Option "${value}" not found for field "${field.name}". ` +
            `Available options: ${availableOptions}`);
        return false;
    }
    await client.mutate(UPDATE_SINGLE_SELECT_FIELD, {
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
async function setTextField(client, projectId, itemId, field, value) {
    await client.mutate(UPDATE_TEXT_FIELD, {
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
async function setNumberField(client, projectId, itemId, field, value) {
    if (isNaN(value)) {
        core.warning(`Invalid number value for field "${field.name}"`);
        return false;
    }
    await client.mutate(UPDATE_NUMBER_FIELD, {
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
 */
async function setIterationField(client, projectId, itemId, field, value) {
    if (!field.iterations || field.iterations.length === 0) {
        core.warning(`Field "${field.name}" has no iterations defined`);
        return false;
    }
    // Find the iteration by title (case-insensitive)
    const lowerValue = value.toLowerCase();
    const iteration = field.iterations.find((i) => i.title.toLowerCase() === lowerValue);
    if (!iteration) {
        const availableIterations = field.iterations.map((i) => i.title).join(', ');
        core.warning(`Iteration "${value}" not found for field "${field.name}". ` +
            `Available iterations: ${availableIterations}`);
        return false;
    }
    await client.mutate(UPDATE_ITERATION_FIELD, {
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
 */
async function setDateField(client, projectId, itemId, field, value) {
    // Validate date format (YYYY-MM-DD)
    const dateRegex = /^\d{4}-\d{2}-\d{2}$/;
    if (!dateRegex.test(value)) {
        core.warning(`Invalid date format for field "${field.name}". Expected YYYY-MM-DD, got "${value}"`);
        return false;
    }
    await client.mutate(UPDATE_DATE_FIELD, {
        projectId,
        itemId,
        fieldId: field.id,
        date: value,
    });
    core.info(`Set "${field.name}" to "${value}"`);
    return true;
}
/**
 * Set multiple field values
 */
export async function setFieldValues(client, projectId, itemId, fields, defaults) {
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
        }
        else {
            failed++;
        }
    }
    return { success, failed };
}
//# sourceMappingURL=fields.js.map