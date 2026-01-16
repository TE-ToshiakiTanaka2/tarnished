import type { TagResult } from "./types.js";
/**
 * Create and push a new tag to the repository
 * @param version - Version string for the tag (e.g., "v1.2.3")
 * @param sha - Commit SHA to tag
 * @param token - GitHub token
 * @returns Tag creation result
 */
export declare function createTag(version: string, sha: string, token: string): Promise<TagResult>;
