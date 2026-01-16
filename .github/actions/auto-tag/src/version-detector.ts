import { exec } from "node:child_process";
import { promisify } from "node:util";
import * as core from "@actions/core";
import type { BranchInfo, VersionConfig, VersionInfo, VersionType } from "./types.js";

const execAsync = promisify(exec);

/**
 * Branch name pattern: {type}/{assignee}/#{issue}/{description}
 * Examples:
 *   - feature/tanaka/#123/add-login
 *   - release/yamada/#45/v2-release
 *   - major/suzuki/99/breaking-change (without #)
 */
const BRANCH_PATTERN = /^([^/]+)\/([^/]+)\/#?(\d+)\/(.+)$/;

/**
 * Version pattern: v1.2.3 or v1.2.3-rc.1
 */
const VERSION_PATTERN = /^v?(\d+)\.(\d+)\.(\d+)(?:-(.+))?$/;

/**
 * Parse branch name into components
 * @param branch - Branch name to parse
 * @returns Parsed branch info
 */
export function parseBranchName(branch: string): BranchInfo {
  const match = branch.match(BRANCH_PATTERN);

  if (!match) {
    core.warning(`Branch name does not match expected pattern: ${branch}`);
    // Return with type extracted from first segment if possible
    const segments = branch.split("/");
    return {
      type: segments[0] || "unknown",
      assignee: segments[1] || "unknown",
      issueNumber: null,
      description: segments.slice(2).join("/") || branch,
      raw: branch,
    };
  }

  return {
    type: match[1],
    assignee: match[2],
    issueNumber: Number.parseInt(match[3], 10),
    description: match[4],
    raw: branch,
  };
}

/**
 * Determine version type from branch info and config
 * @param branchInfo - Parsed branch information
 * @param config - Version configuration
 * @returns Version bump type
 */
export function detectVersionType(branchInfo: BranchInfo, config: VersionConfig): VersionType {
  const { branch_prefixes } = config.versioning;
  const branchPrefix = `${branchInfo.type}/`;

  // Check major prefixes
  if (branch_prefixes.major.some((p) => branchPrefix.startsWith(p))) {
    return "major";
  }

  // Check minor prefixes
  if (branch_prefixes.minor.some((p) => branchPrefix.startsWith(p))) {
    return "minor";
  }

  // Check patch prefixes
  if (branch_prefixes.patch.some((p) => branchPrefix.startsWith(p))) {
    return "patch";
  }

  // Default to RC for unknown prefixes
  return "rc";
}

/**
 * Parse version string to VersionInfo
 * @param version - Version string (e.g., "v1.2.3" or "v1.2.3-rc.1")
 * @returns Parsed version info or null if invalid
 */
export function parseVersion(version: string): VersionInfo | null {
  const match = version.match(VERSION_PATTERN);

  if (!match) {
    return null;
  }

  return {
    major: Number.parseInt(match[1], 10),
    minor: Number.parseInt(match[2], 10),
    patch: Number.parseInt(match[3], 10),
    prerelease: match[4] || null,
  };
}

/**
 * Get latest tag from repository
 * @returns Latest tag or null if no tags exist
 */
export async function getLatestTag(): Promise<string | null> {
  try {
    // Get all tags sorted by version
    const { stdout } = await execAsync("git tag --sort=-v:refname | head -n 1");
    const tag = stdout.trim();

    if (!tag) {
      core.info("No existing tags found");
      return null;
    }

    core.info(`Latest tag: ${tag}`);
    return tag;
  } catch (error) {
    core.warning(`Failed to get latest tag: ${error}`);
    return null;
  }
}

/**
 * Get all RC tags for a specific base version
 * @param baseVersion - Base version to find RCs for (e.g., "v1.2.3")
 * @returns Array of RC tag names
 */
export async function getRcTags(baseVersion: string): Promise<string[]> {
  try {
    const { stdout } = await execAsync("git tag --list");
    const allTags = stdout.trim().split("\n").filter(Boolean);

    // Filter tags that match the pattern: baseVersion-rc.N
    const rcPattern = new RegExp(`^${escapeRegex(baseVersion)}-rc\\.\\d+$`);
    const rcTags = allTags.filter((tag) => rcPattern.test(tag));

    core.info(`Found ${rcTags.length} RC tags for ${baseVersion}`);
    return rcTags;
  } catch (error) {
    core.warning(`Failed to get RC tags: ${error}`);
    return [];
  }
}

/**
 * Calculate next version based on current and bump type
 * @param current - Current version info (null if no tags exist)
 * @param type - Version bump type
 * @param existingRcTags - Existing RC tags for determining RC number
 * @returns Next version string (e.g., "v1.2.4")
 */
export function calculateNextVersion(
  current: VersionInfo | null,
  type: VersionType,
  existingRcTags: string[] = [],
): string {
  // Start from v0.0.0 if no existing tags
  const base = current ?? { major: 0, minor: 0, patch: 0, prerelease: null };

  switch (type) {
    case "major":
      return `v${base.major + 1}.0.0`;

    case "minor":
      return `v${base.major}.${base.minor + 1}.0`;

    case "patch":
      return `v${base.major}.${base.minor}.${base.patch + 1}`;

    case "rc": {
      // RC increments patch and adds -rc.N suffix
      const nextPatch = base.patch + 1;
      const baseVersion = `v${base.major}.${base.minor}.${nextPatch}`;
      const rcNumber = findNextRcNumber(baseVersion, existingRcTags);
      return `${baseVersion}-rc.${rcNumber}`;
    }
  }
}

/**
 * Find the next RC number for a base version
 * @param baseVersion - Base version (e.g., "v1.2.3")
 * @param existingRcTags - Existing RC tags
 * @returns Next RC number
 */
function findNextRcNumber(baseVersion: string, existingRcTags: string[]): number {
  const rcPattern = new RegExp(`^${escapeRegex(baseVersion)}-rc\\.(\\d+)$`);
  let maxRc = 0;

  for (const tag of existingRcTags) {
    const match = tag.match(rcPattern);
    if (match) {
      maxRc = Math.max(maxRc, Number.parseInt(match[1], 10));
    }
  }

  return maxRc + 1;
}

/**
 * Escape special regex characters in a string
 */
function escapeRegex(str: string): string {
  return str.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}
