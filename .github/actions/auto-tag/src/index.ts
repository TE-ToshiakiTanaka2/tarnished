import * as core from "@actions/core";
import * as github from "@actions/github";
import { loadConfig } from "./config-loader.js";
import { postFailureComment, postSuccessComment } from "./pr-commenter.js";
import { createTag } from "./tag-creator.js";
import {
  calculateNextVersion,
  detectVersionType,
  getLatestTag,
  getRcTags,
  parseBranchName,
  parseVersion,
} from "./version-detector.js";

async function run(): Promise<void> {
  let prNumber: number | undefined;
  let token: string | undefined;

  try {
    // 1. Get inputs
    token = core.getInput("token", { required: true });

    // 2. Get PR context
    const context = github.context;
    const payload = context.payload;

    prNumber = payload.pull_request?.number;
    const branchName = payload.pull_request?.head?.ref as string | undefined;
    const sha = payload.pull_request?.merge_commit_sha as string | undefined;
    const merged = payload.pull_request?.merged as boolean | undefined;

    // 3. Validate context
    if (!prNumber) {
      throw new Error("This action must be triggered by a pull_request event");
    }

    if (!merged) {
      core.info("PR was not merged, skipping tag creation");
      return;
    }

    if (!branchName) {
      throw new Error("Could not determine branch name from PR");
    }

    if (!sha) {
      throw new Error("Could not determine merge commit SHA");
    }

    core.info(`Processing PR #${prNumber}`);
    core.info(`Branch: ${branchName}`);
    core.info(`Merge commit: ${sha}`);

    // 4. Load configuration
    const config = await loadConfig();
    core.info("Configuration loaded");

    // 5. Parse branch and detect version type
    const branchInfo = parseBranchName(branchName);
    core.info(`Branch type: ${branchInfo.type}`);
    core.info(`Assignee: ${branchInfo.assignee}`);
    core.info(`Issue: ${branchInfo.issueNumber ?? "N/A"}`);

    const versionType = detectVersionType(branchInfo, config);
    core.info(`Version type: ${versionType}`);

    // 6. Get latest tag and calculate next version
    const latestTag = await getLatestTag();
    const currentVersion = latestTag ? parseVersion(latestTag) : null;

    // Get RC tags if needed
    let rcTags: string[] = [];
    if (versionType === "rc" && currentVersion) {
      const nextPatch = currentVersion.patch + 1;
      const baseVersion = `v${currentVersion.major}.${currentVersion.minor}.${nextPatch}`;
      rcTags = await getRcTags(baseVersion);
    }

    const nextVersion = calculateNextVersion(currentVersion, versionType, rcTags);
    core.info(`Next version: ${nextVersion}`);

    // 7. Create tag
    const result = await createTag(nextVersion, sha, token);

    // 8. Post comment and set outputs
    if (result.success) {
      await postSuccessComment(prNumber, nextVersion, latestTag, versionType, token);

      core.setOutput("version", nextVersion);
      core.setOutput("previous-version", latestTag ?? "");
      core.setOutput("version-type", versionType);

      core.info(`Successfully created tag ${nextVersion}`);
    } else {
      throw new Error(result.error ?? "Unknown error creating tag");
    }
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);

    // Post failure comment if we have PR context
    if (prNumber && token) {
      await postFailureComment(prNumber, message, token);
    }

    core.setFailed(message);
  }
}

run();
