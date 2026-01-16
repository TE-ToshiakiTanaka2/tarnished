import * as core from '@actions/core';
import * as github from '@actions/github';
import { loadConfig } from './config.js';
import { GraphQLClient } from './graphql/client.js';
import { findProject } from './project/finder.js';
import { findItemInProject, addItemToProject, getIssueNodeId } from './project/item.js';
import { setFieldValue } from './project/fields.js';
import { detectIssues, type PullRequestContext } from './issue-detector.js';

async function run(): Promise<void> {
  try {
    // Get inputs
    const token = core.getInput('token', { required: true });
    const configPath = core.getInput('config-path') || '.github/project-automation.yml';

    // Get PR context
    const context = github.context;
    const pr = context.payload.pull_request;

    if (!pr) {
      core.info('No pull request found in event payload, skipping');
      return;
    }

    const prNumber = pr.number as number;
    const prTitle = pr.title as string;

    core.info(`Processing PR #${prNumber}: ${prTitle}`);

    // Load configuration
    const config = loadConfig(configPath);

    // Check if PR section is configured
    if (!config.pr) {
      core.info('No PR configuration found, skipping status update');
      core.info('To enable PR status updates, add a "pr" section to your config file');
      return;
    }

    const statusValue = config.pr.status;
    const branchPattern = config.pr.branch_pattern;

    // Detect linked issues
    const prContext: PullRequestContext = {
      title: pr.title as string,
      body: pr.body as string | null,
      head: {
        ref: pr.head?.ref as string,
      },
    };

    const detectedIssues = detectIssues(prContext, branchPattern);

    core.info(`Detected ${detectedIssues.all.length} linked issue(s)`);
    if (detectedIssues.fromKeywords.length > 0) {
      core.info(`  From keywords: ${detectedIssues.fromKeywords.map(n => `#${n}`).join(', ')}`);
    }
    if (detectedIssues.fromBranch.length > 0) {
      core.info(`  From branch: ${detectedIssues.fromBranch.map(n => `#${n}`).join(', ')}`);
    }

    if (detectedIssues.all.length === 0) {
      core.info('No linked issues detected, skipping');
      core.setOutput('issues-updated', '');
      core.setOutput('issues-count', '0');
      return;
    }

    // Initialize GraphQL client
    const client = new GraphQLClient(token);

    // Find project and get field information
    const project = await findProject(client, config);
    core.setOutput('project-id', project.id);

    // Get repository info for issue lookup
    const owner = context.repo.owner;
    const repo = context.repo.repo;

    // Process each detected issue
    const updatedIssues: number[] = [];

    for (const issueNumber of detectedIssues.all) {
      try {
        core.info(`Processing issue #${issueNumber}...`);

        // Get issue node ID
        const issueNodeId = await getIssueNodeId(client, owner, repo, issueNumber);
        if (!issueNodeId) {
          core.warning(`Issue #${issueNumber} not found, skipping`);
          continue;
        }

        // Check if issue is already in project
        let itemId = await findItemInProject(client, project.id, issueNodeId);

        if (!itemId) {
          // Add issue to project first
          core.info(`Issue #${issueNumber} is not in project, adding...`);
          itemId = await addItemToProject(client, project.id, issueNodeId);
        }

        // Update status field
        const success = await setFieldValue({
          client,
          projectId: project.id,
          itemId,
          fields: project.fields,
          fieldName: 'Status',
          value: statusValue,
        });

        if (success) {
          updatedIssues.push(issueNumber);
          core.info(`Issue #${issueNumber} status updated to "${statusValue}"`);
        }
      } catch (error) {
        // Log warning but continue with other issues
        if (error instanceof Error) {
          core.warning(`Failed to process issue #${issueNumber}: ${error.message}`);
        }
      }
    }

    // Set outputs
    core.setOutput('issues-updated', updatedIssues.map(n => `#${n}`).join(', '));
    core.setOutput('issues-count', updatedIssues.length.toString());

    core.info(`PR status update completed: ${updatedIssues.length} issue(s) updated`);
  } catch (error) {
    if (error instanceof Error) {
      core.setFailed(error.message);
    } else {
      core.setFailed('An unknown error occurred');
    }
  }
}

run();
