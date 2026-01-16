/**
 * Version bump types
 */
export type VersionType = "major" | "minor" | "patch" | "rc";

/**
 * Parsed branch information
 * Pattern: {type}/{assignee}/#{issue}/{description}
 */
export interface BranchInfo {
  /** Branch type (e.g., 'feature', 'release', 'major') */
  type: string;
  /** Assignee username */
  assignee: string;
  /** Related issue number (null if not found) */
  issueNumber: number | null;
  /** Branch description */
  description: string;
  /** Raw branch name */
  raw: string;
}

/**
 * Parsed version information
 */
export interface VersionInfo {
  major: number;
  minor: number;
  patch: number;
  /** Pre-release identifier (e.g., 'rc.1', 'rc.2') */
  prerelease: string | null;
}

/**
 * Configuration file structure (.github/version.yml)
 */
export interface VersionConfig {
  versioning: {
    branch_prefixes: {
      major: string[];
      minor: string[];
      patch: string[];
    };
  };
}

/**
 * Tag creation result
 */
export interface TagResult {
  success: boolean;
  version: string;
  sha: string;
  error?: string;
}

/**
 * Default configuration when .github/version.yml is not found
 */
export const DEFAULT_CONFIG: VersionConfig = {
  versioning: {
    branch_prefixes: {
      major: ["major/"],
      minor: ["release/"],
      patch: ["feature/"],
    },
  },
};
