import type { VersionType } from "./types.js";
/**
 * Post success comment to PR
 * @param prNumber - Pull request number
 * @param version - Created tag version
 * @param previousVersion - Previous tag version (or null)
 * @param versionType - Version bump type
 * @param token - GitHub token
 */
export declare function postSuccessComment(prNumber: number, version: string, previousVersion: string | null, versionType: VersionType, token: string): Promise<void>;
/**
 * Post failure comment to PR
 * @param prNumber - Pull request number
 * @param error - Error message
 * @param token - GitHub token
 */
export declare function postFailureComment(prNumber: number, error: string, token: string): Promise<void>;
