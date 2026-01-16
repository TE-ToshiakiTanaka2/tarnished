import type { DetectedIssues } from './types.js';

/**
 * Default regex pattern for extracting issue number from branch name
 * Matches patterns like: feature/123-name, fix-456, bugfix/789, hotfix/101
 */
const DEFAULT_BRANCH_PATTERN = '^(?:feature|fix|bugfix|hotfix)[/-]?(\\d+)';

/**
 * Regex pattern for detecting GitHub issue linking keywords
 * Matches: close, closes, closed, fix, fixes, fixed, resolve, resolves, resolved
 * Followed by # and issue number
 */
const KEYWORD_PATTERN = /(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?)\s+#(\d+)/gi;

/**
 * Detect issue numbers from PR title and body using keywords
 * @param title PR title
 * @param body PR body (description)
 * @returns Array of detected issue numbers
 */
export function detectIssuesFromKeywords(title: string, body: string): number[] {
  const issues: Set<number> = new Set();
  const content = `${title}\n${body}`;

  let match;
  while ((match = KEYWORD_PATTERN.exec(content)) !== null) {
    const issueNumber = parseInt(match[1] ?? '', 10);
    if (!isNaN(issueNumber) && issueNumber > 0) {
      issues.add(issueNumber);
    }
  }

  // Reset regex state
  KEYWORD_PATTERN.lastIndex = 0;

  return Array.from(issues).sort((a, b) => a - b);
}

/**
 * Detect issue numbers from branch name using regex pattern
 * @param branchName Branch name
 * @param pattern Optional custom regex pattern (must have a capture group for issue number)
 * @returns Array of detected issue numbers
 */
export function detectIssuesFromBranch(branchName: string, pattern?: string): number[] {
  const issues: Set<number> = new Set();
  const regexPattern = pattern ?? DEFAULT_BRANCH_PATTERN;

  try {
    const regex = new RegExp(regexPattern, 'i');
    const match = regex.exec(branchName);

    if (match && match[1]) {
      const issueNumber = parseInt(match[1], 10);
      if (!isNaN(issueNumber) && issueNumber > 0) {
        issues.add(issueNumber);
      }
    }
  } catch {
    // Invalid regex pattern, skip branch detection
  }

  return Array.from(issues);
}

/**
 * Pull Request context for issue detection
 */
export interface PullRequestContext {
  title: string;
  body: string | null;
  head: {
    ref: string; // branch name
  };
}

/**
 * Detect all issues linked to a PR
 * @param pr Pull request context
 * @param branchPattern Optional custom branch pattern
 * @returns DetectedIssues with issues from keywords, branch, and combined unique list
 */
export function detectIssues(pr: PullRequestContext, branchPattern?: string): DetectedIssues {
  const fromKeywords = detectIssuesFromKeywords(pr.title, pr.body ?? '');
  const fromBranch = detectIssuesFromBranch(pr.head.ref, branchPattern);

  // Combine and deduplicate
  const allSet = new Set([...fromKeywords, ...fromBranch]);
  const all = Array.from(allSet).sort((a, b) => a - b);

  return {
    fromKeywords,
    fromBranch,
    all,
  };
}
