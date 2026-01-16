import { describe, it, expect, vi, beforeEach } from 'vitest';
import { loadConfig, getDefaultConfig, validateConfig } from '../src/config-loader.js';
import { createTag } from '../src/tag-creator.js';
import { postSuccessComment, postFailureComment } from '../src/pr-commenter.js';
import {
  parseBranchName,
  detectVersionType,
  parseVersion,
  calculateNextVersion,
  getLatestTag,
  getRcTags,
} from '../src/version-detector.js';
import { DEFAULT_CONFIG, type VersionConfig } from '../src/types.js';
import * as fs from 'node:fs';
import { exec } from 'node:child_process';

// Mock @actions/core
vi.mock('@actions/core', () => ({
  info: vi.fn(),
  warning: vi.fn(),
  error: vi.fn(),
  debug: vi.fn(),
  setOutput: vi.fn(),
  setFailed: vi.fn(),
  getInput: vi.fn(),
}));

// Mock @actions/github
const mockOctokit = {
  rest: {
    git: {
      createRef: vi.fn(),
    },
    issues: {
      createComment: vi.fn(),
    },
  },
};

vi.mock('@actions/github', () => ({
  getOctokit: vi.fn(() => mockOctokit),
  context: {
    repo: {
      owner: 'test-owner',
      repo: 'test-repo',
    },
  },
}));

// Mock fs for config loading tests
vi.mock('node:fs', async () => {
  const actual = await vi.importActual('node:fs');
  return {
    ...actual,
    existsSync: vi.fn(),
    readFileSync: vi.fn(),
  };
});

// Mock child_process for git commands
vi.mock('node:child_process', async () => {
  const actual = await vi.importActual('node:child_process');
  return {
    ...actual,
    exec: vi.fn(),
  };
});

describe('Integration: Auto Tag Flow', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  describe('Full workflow: PR merged -> Tag created', () => {
    it('should create patch version tag for feature branch', async () => {
      // Step 1: Parse branch name
      const branchName = 'feature/tanaka/#123/add-login';
      const branchInfo = parseBranchName(branchName);

      expect(branchInfo.type).toBe('feature');
      expect(branchInfo.assignee).toBe('tanaka');
      expect(branchInfo.issueNumber).toBe(123);
      expect(branchInfo.description).toBe('add-login');

      // Step 2: Load configuration (mock fs)
      vi.mocked(fs.existsSync).mockReturnValue(false);
      const config = await loadConfig();

      expect(config).toEqual(DEFAULT_CONFIG);

      // Step 3: Detect version type
      const versionType = detectVersionType(branchInfo, config);
      expect(versionType).toBe('patch');

      // Step 4: Get latest tag (mock git command)
      vi.mocked(exec).mockImplementation(((
        cmd: string,
        callback?: (error: Error | null, result: { stdout: string; stderr: string }) => void
      ) => {
        if (cmd.includes('--sort=-v:refname')) {
          callback?.(null, { stdout: 'v1.2.3\n', stderr: '' });
        }
        return {} as ReturnType<typeof exec>;
      }) as typeof exec);

      const latestTag = await getLatestTag();
      expect(latestTag).toBe('v1.2.3');

      // Step 5: Calculate next version
      const currentVersion = parseVersion(latestTag!);
      const nextVersion = calculateNextVersion(currentVersion, versionType);

      expect(nextVersion).toBe('v1.2.4');

      // Step 6: Create tag (mock octokit)
      mockOctokit.rest.git.createRef.mockResolvedValueOnce({});

      const sha = 'abc123def456';
      const result = await createTag(nextVersion, sha, 'mock-token');

      expect(result.success).toBe(true);
      expect(result.version).toBe('v1.2.4');
      expect(mockOctokit.rest.git.createRef).toHaveBeenCalledWith({
        owner: 'test-owner',
        repo: 'test-repo',
        ref: 'refs/tags/v1.2.4',
        sha,
      });

      // Step 7: Post success comment
      mockOctokit.rest.issues.createComment.mockResolvedValueOnce({});
      await postSuccessComment(123, nextVersion, latestTag, versionType, 'mock-token');

      expect(mockOctokit.rest.issues.createComment).toHaveBeenCalled();
    });

    it('should create minor version tag for release branch', async () => {
      const branchName = 'release/yamada/#45/v2-release';
      const branchInfo = parseBranchName(branchName);

      expect(branchInfo.type).toBe('release');
      expect(branchInfo.issueNumber).toBe(45);

      const config = getDefaultConfig();
      const versionType = detectVersionType(branchInfo, config);
      expect(versionType).toBe('minor');

      const currentVersion = parseVersion('v1.2.3');
      const nextVersion = calculateNextVersion(currentVersion, versionType);

      expect(nextVersion).toBe('v1.3.0');
    });

    it('should create major version tag for major branch', async () => {
      const branchName = 'major/suzuki/#99/breaking-change';
      const branchInfo = parseBranchName(branchName);

      expect(branchInfo.type).toBe('major');
      expect(branchInfo.issueNumber).toBe(99);

      const config = getDefaultConfig();
      const versionType = detectVersionType(branchInfo, config);
      expect(versionType).toBe('major');

      const currentVersion = parseVersion('v1.2.3');
      const nextVersion = calculateNextVersion(currentVersion, versionType);

      expect(nextVersion).toBe('v2.0.0');
    });

    it('should create first version tag when no previous tags exist', async () => {
      const branchInfo = parseBranchName('feature/dev/#1/initial-feature');
      const config = getDefaultConfig();
      const versionType = detectVersionType(branchInfo, config);

      // No existing tags
      const nextVersion = calculateNextVersion(null, versionType);

      expect(nextVersion).toBe('v0.0.1');
    });
  });

  describe('RC version handling', () => {
    it('should create first RC tag for unknown branch prefix', async () => {
      const branchInfo = parseBranchName('hotfix/dev/#10/urgent-fix');
      const config = getDefaultConfig();
      const versionType = detectVersionType(branchInfo, config);

      expect(versionType).toBe('rc');

      const currentVersion = parseVersion('v1.2.3');
      const nextVersion = calculateNextVersion(currentVersion, versionType, []);

      expect(nextVersion).toBe('v1.2.4-rc.1');
    });

    it('should increment RC number when previous RCs exist', async () => {
      const branchInfo = parseBranchName('bugfix/dev/#20/fix-bug');
      const config = getDefaultConfig();
      const versionType = detectVersionType(branchInfo, config);

      expect(versionType).toBe('rc');

      const currentVersion = parseVersion('v1.2.3');
      const existingRcs = ['v1.2.4-rc.1', 'v1.2.4-rc.2'];
      const nextVersion = calculateNextVersion(currentVersion, versionType, existingRcs);

      expect(nextVersion).toBe('v1.2.4-rc.3');
    });

    it('should fetch RC tags correctly', async () => {
      vi.mocked(exec).mockImplementation(((
        cmd: string,
        callback?: (error: Error | null, result: { stdout: string; stderr: string }) => void
      ) => {
        if (cmd.includes('--list')) {
          callback?.(null, {
            stdout: 'v1.0.0\nv1.0.1\nv1.0.2-rc.1\nv1.0.2-rc.2\nv1.1.0\n',
            stderr: '',
          });
        }
        return {} as ReturnType<typeof exec>;
      }) as typeof exec);

      const rcTags = await getRcTags('v1.0.2');
      expect(rcTags).toEqual(['v1.0.2-rc.1', 'v1.0.2-rc.2']);
    });
  });

  describe('Configuration loading', () => {
    it('should load custom configuration from file', async () => {
      const configYaml = `
versioning:
  branch_prefixes:
    major:
      - breaking/
      - major/
    minor:
      - feature/
      - release/
    patch:
      - fix/
      - bugfix/
`;

      vi.mocked(fs.existsSync).mockReturnValue(true);
      vi.mocked(fs.readFileSync).mockReturnValue(configYaml);

      const config = await loadConfig('.github/version.yml');

      expect(config.versioning.branch_prefixes.major).toContain('breaking/');
      expect(config.versioning.branch_prefixes.minor).toContain('feature/');
      expect(config.versioning.branch_prefixes.patch).toContain('bugfix/');
    });

    it('should fall back to default config for missing file', async () => {
      vi.mocked(fs.existsSync).mockReturnValue(false);

      const config = await loadConfig('.github/version.yml');

      expect(config).toEqual(DEFAULT_CONFIG);
    });

    it('should fall back to default config for invalid YAML', async () => {
      vi.mocked(fs.existsSync).mockReturnValue(true);
      vi.mocked(fs.readFileSync).mockReturnValue('invalid: yaml: content:');

      const config = await loadConfig('.github/version.yml');

      expect(config).toEqual(DEFAULT_CONFIG);
    });

    it('should validate config correctly', () => {
      const validConfig: VersionConfig = {
        versioning: {
          branch_prefixes: {
            major: ['major/'],
            minor: ['minor/'],
            patch: ['patch/'],
          },
        },
      };

      expect(validateConfig(validConfig)).toBe(true);
      expect(validateConfig(null)).toBe(false);
      expect(validateConfig({})).toBe(false);
      expect(validateConfig({ versioning: {} })).toBe(false);
    });
  });

  describe('Error scenarios', () => {
    it('should handle tag already exists error', async () => {
      mockOctokit.rest.git.createRef.mockRejectedValueOnce(
        new Error('Reference already exists')
      );

      const result = await createTag('v1.0.0', 'sha123', 'token');

      expect(result.success).toBe(false);
      expect(result.error).toContain('already exists');
    });

    it('should handle generic tag creation error', async () => {
      mockOctokit.rest.git.createRef.mockRejectedValueOnce(
        new Error('Permission denied')
      );

      const result = await createTag('v1.0.0', 'sha123', 'token');

      expect(result.success).toBe(false);
      expect(result.error).toBe('Permission denied');
    });

    it('should handle invalid branch format gracefully', () => {
      const branchInfo = parseBranchName('main');

      expect(branchInfo.type).toBe('main');
      expect(branchInfo.issueNumber).toBeNull();
    });

    it('should handle git command failure gracefully', async () => {
      vi.mocked(exec).mockImplementation(((
        cmd: string,
        callback?: (error: Error | null, result: { stdout: string; stderr: string }) => void
      ) => {
        callback?.(new Error('Git error'), { stdout: '', stderr: 'error' });
        return {} as ReturnType<typeof exec>;
      }) as typeof exec);

      const latestTag = await getLatestTag();
      expect(latestTag).toBeNull();

      const rcTags = await getRcTags('v1.0.0');
      expect(rcTags).toEqual([]);
    });

    it('should post failure comment on error', async () => {
      mockOctokit.rest.issues.createComment.mockResolvedValueOnce({});

      await postFailureComment(123, 'Tag creation failed', 'token');

      expect(mockOctokit.rest.issues.createComment).toHaveBeenCalledWith(
        expect.objectContaining({
          owner: 'test-owner',
          repo: 'test-repo',
          issue_number: 123,
          body: expect.stringContaining('Auto Tag Failed'),
        })
      );
    });

    it('should handle comment posting failure gracefully', async () => {
      mockOctokit.rest.issues.createComment.mockRejectedValueOnce(
        new Error('API error')
      );

      // Should not throw
      await expect(
        postSuccessComment(123, 'v1.0.0', null, 'patch', 'token')
      ).resolves.not.toThrow();
    });
  });

  describe('Branch parsing edge cases', () => {
    it('should parse branch without hash before issue number', () => {
      const branchInfo = parseBranchName('feature/tanaka/123/add-login');

      expect(branchInfo.type).toBe('feature');
      expect(branchInfo.assignee).toBe('tanaka');
      expect(branchInfo.issueNumber).toBe(123);
    });

    it('should parse branch with complex description', () => {
      const branchInfo = parseBranchName('release/yamada/#45/v2-major-release-update');

      expect(branchInfo.description).toBe('v2-major-release-update');
    });

    it('should handle partial branch names', () => {
      const branchInfo = parseBranchName('feature/tanaka');

      expect(branchInfo.type).toBe('feature');
      expect(branchInfo.assignee).toBe('tanaka');
      expect(branchInfo.issueNumber).toBeNull();
    });
  });

  describe('Version parsing edge cases', () => {
    it('should parse version with prerelease', () => {
      const version = parseVersion('v1.2.3-beta.1');

      expect(version).toEqual({
        major: 1,
        minor: 2,
        patch: 3,
        prerelease: 'beta.1',
      });
    });

    it('should parse version without v prefix', () => {
      const version = parseVersion('1.2.3');

      expect(version).toEqual({
        major: 1,
        minor: 2,
        patch: 3,
        prerelease: null,
      });
    });

    it('should return null for invalid version', () => {
      expect(parseVersion('invalid')).toBeNull();
      expect(parseVersion('')).toBeNull();
      expect(parseVersion('v1.2')).toBeNull();
    });
  });
});
