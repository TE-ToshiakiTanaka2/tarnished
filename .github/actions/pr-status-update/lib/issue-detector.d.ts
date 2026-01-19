import type { DetectedIssues } from "./types.js";
/**
 * Detect issue numbers from PR title and body using keywords
 * @param title PR title
 * @param body PR body (description)
 * @returns Array of detected issue numbers
 */
export declare function detectIssuesFromKeywords(title: string, body: string): number[];
/**
 * Detect issue numbers from branch name using regex pattern
 * @param branchName Branch name
 * @param pattern Optional custom regex pattern (must have a capture group for issue number)
 * @returns Array of detected issue numbers
 */
export declare function detectIssuesFromBranch(branchName: string, pattern?: string): number[];
/**
 * Pull Request context for issue detection
 */
export interface PullRequestContext {
    title: string;
    body: string | null;
    head: {
        ref: string;
    };
}
/**
 * Detect all issues linked to a PR
 * @param pr Pull request context
 * @param branchPattern Optional custom branch pattern
 * @returns DetectedIssues with issues from keywords, branch, and combined unique list
 */
export declare function detectIssues(pr: PullRequestContext, branchPattern?: string): DetectedIssues;
//# sourceMappingURL=issue-detector.d.ts.map