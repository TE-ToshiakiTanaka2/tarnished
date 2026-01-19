import * as core from "@actions/core";
import * as github from "@actions/github";
import { loadConfig } from "./config.js";
import { GraphQLClient } from "./graphql/client.js";
import { setFieldValues } from "./project/fields.js";
import { findProject } from "./project/finder.js";
import { addItemToProject, findItemInProject } from "./project/item.js";

async function run(): Promise<void> {
  try {
    // Get inputs
    const token = core.getInput("token", { required: true });
    const configPath = core.getInput("config-path") || ".github/project-automation.yml";

    // Get issue context
    const context = github.context;
    const issue = context.payload.issue;

    if (!issue) {
      core.info("No issue found in event payload, skipping");
      return;
    }

    const issueNodeId = issue.node_id as string;
    const issueNumber = issue.number as number;

    core.info(`Processing issue #${issueNumber}`);

    // Load configuration
    const config = loadConfig(configPath);

    // Initialize GraphQL client
    const client = new GraphQLClient(token);

    // Find project and get field information
    const project = await findProject(client, config);
    core.setOutput("project-id", project.id);

    // Check if issue is already in project (idempotency)
    const itemId = await findItemInProject(client, project.id, issueNodeId);
    const alreadyExists = itemId !== null;
    core.setOutput("already-exists", alreadyExists.toString());

    let finalItemId: string;

    if (alreadyExists && itemId !== null) {
      core.info(`Issue #${issueNumber} is already in project "${project.title}"`);
      finalItemId = itemId;
    } else {
      // Add issue to project
      finalItemId = await addItemToProject(client, project.id, issueNodeId);
      core.info(`Issue #${issueNumber} added to project "${project.title}"`);
    }

    core.setOutput("item-id", finalItemId);

    // Set field values if defaults are configured
    if (config.defaults && Object.keys(config.defaults).length > 0) {
      core.info("Setting default field values...");

      const result = await setFieldValues(
        client,
        project.id,
        finalItemId,
        project.fields,
        config.defaults,
      );

      core.info(`Field values set: ${result.success} succeeded, ${result.failed} skipped`);
    } else {
      core.info("No default field values configured");
    }

    core.info("Project automation completed successfully");
  } catch (error) {
    if (error instanceof Error) {
      core.setFailed(error.message);
    } else {
      core.setFailed("An unknown error occurred");
    }
  }
}

run();
