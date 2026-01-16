import * as core from "@actions/core";
import * as github from "@actions/github";
import type { VersionType } from "./types.js";

/**
 * Post success comment to PR
 * @param prNumber - Pull request number
 * @param version - Created tag version
 * @param previousVersion - Previous tag version (or null)
 * @param versionType - Version bump type
 * @param token - GitHub token
 */
export async function postSuccessComment(
  prNumber: number,
  version: string,
  previousVersion: string | null,
  versionType: VersionType,
  token: string,
): Promise<void> {
  const octokit = github.getOctokit(token);
  const { owner, repo } = github.context.repo;

  const body = createSuccessMessage(version, previousVersion, versionType);

  try {
    await octokit.rest.issues.createComment({
      owner,
      repo,
      issue_number: prNumber,
      body,
    });

    core.info(`Posted success comment to PR #${prNumber}`);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    core.warning(`Failed to post success comment: ${message}`);
  }
}

/**
 * Post failure comment to PR
 * @param prNumber - Pull request number
 * @param error - Error message
 * @param token - GitHub token
 */
export async function postFailureComment(
  prNumber: number,
  error: string,
  token: string,
): Promise<void> {
  const octokit = github.getOctokit(token);
  const { owner, repo } = github.context.repo;

  const body = createFailureMessage(error);

  try {
    await octokit.rest.issues.createComment({
      owner,
      repo,
      issue_number: prNumber,
      body,
    });

    core.info(`Posted failure comment to PR #${prNumber}`);
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    core.warning(`Failed to post failure comment: ${message}`);
  }
}

/**
 * Create success comment message
 */
function createSuccessMessage(
  version: string,
  previousVersion: string | null,
  versionType: VersionType,
): string {
  const typeEmoji = getTypeEmoji(versionType);
  const previousDisplay = previousVersion ?? "N/A (first tag)";

  return `## ${typeEmoji} Auto Tag Created

| Item | Value |
|------|-------|
| **Version** | \`${version}\` |
| **Previous** | \`${previousDisplay}\` |
| **Type** | ${versionType} |

Tag created successfully!`;
}

/**
 * Create failure comment message
 */
function createFailureMessage(error: string): string {
  return `## ❌ Auto Tag Failed

**Error**: ${error}

Please check the workflow logs for details.

**Expected branch format**: \`{type}/{assignee}/#{issue}/{description}\`

Examples:
- \`feature/username/#123/add-feature\`
- \`release/username/#456/v2-release\`
- \`major/username/#789/breaking-change\``;
}

/**
 * Get emoji for version type
 */
function getTypeEmoji(type: VersionType): string {
  switch (type) {
    case "major":
      return "🎉";
    case "minor":
      return "✨";
    case "patch":
      return "🔧";
    case "rc":
      return "🏷️";
  }
}
