import type { BranchInfo, VersionConfig, VersionInfo, VersionType } from "./types.js";
/**
 * Parse branch name into components
 * @param branch - Branch name to parse
 * @returns Parsed branch info
 */
export declare function parseBranchName(branch: string): BranchInfo;
/**
 * Determine version type from branch info and config
 * @param branchInfo - Parsed branch information
 * @param config - Version configuration
 * @returns Version bump type
 */
export declare function detectVersionType(branchInfo: BranchInfo, config: VersionConfig): VersionType;
/**
 * Parse version string to VersionInfo
 * @param version - Version string (e.g., "v1.2.3" or "v1.2.3-rc.1")
 * @returns Parsed version info or null if invalid
 */
export declare function parseVersion(version: string): VersionInfo | null;
/**
 * Get latest tag from repository
 * @returns Latest tag or null if no tags exist
 */
export declare function getLatestTag(): Promise<string | null>;
/**
 * Get all RC tags for a specific base version
 * @param baseVersion - Base version to find RCs for (e.g., "v1.2.3")
 * @returns Array of RC tag names
 */
export declare function getRcTags(baseVersion: string): Promise<string[]>;
/**
 * Calculate next version based on current and bump type
 * @param current - Current version info (null if no tags exist)
 * @param type - Version bump type
 * @param existingRcTags - Existing RC tags for determining RC number
 * @returns Next version string (e.g., "v1.2.4")
 */
export declare function calculateNextVersion(current: VersionInfo | null, type: VersionType, existingRcTags?: string[]): string;
