import * as core from "@actions/core";
import * as github from "@actions/github";
import type { TagResult } from "./types.js";

/**
 * Create and push a new tag to the repository
 * @param version - Version string for the tag (e.g., "v1.2.3")
 * @param sha - Commit SHA to tag
 * @param token - GitHub token
 * @returns Tag creation result
 */
export async function createTag(version: string, sha: string, token: string): Promise<TagResult> {
  const octokit = github.getOctokit(token);
  const { owner, repo } = github.context.repo;

  try {
    core.info(`Creating tag ${version} at ${sha}`);

    await octokit.rest.git.createRef({
      owner,
      repo,
      ref: `refs/tags/${version}`,
      sha,
    });

    core.info(`Successfully created tag ${version}`);

    return {
      success: true,
      version,
      sha,
    };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);

    // Check if tag already exists
    if (message.includes("Reference already exists")) {
      core.error(`Tag ${version} already exists`);
      return {
        success: false,
        version,
        sha,
        error: `Tag ${version} already exists`,
      };
    }

    core.error(`Failed to create tag: ${message}`);
    return {
      success: false,
      version,
      sha,
      error: message,
    };
  }
}
