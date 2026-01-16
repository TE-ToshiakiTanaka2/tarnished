import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { findProject } from '../src/project/finder.js';
import { findItemInProject, addItemToProject, getIssueNodeId } from '../src/project/item.js';
import { setFieldValue } from '../src/project/fields.js';
import { detectIssues } from '../src/issue-detector.js';
import { loadConfig } from '../src/config.js';
import { GraphQLClient } from '../src/graphql/client.js';
import type { FieldInfo, ExtendedProjectConfig } from '../src/types.js';
import * as fs from 'fs';

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

// Mock fs for config loading tests
vi.mock('fs', async () => {
  const actual = await vi.importActual('fs');
  return {
    ...actual,
    existsSync: vi.fn(),
    readFileSync: vi.fn(),
  };
});

// Create mock GraphQL client
const createMockClient = () => ({
  query: vi.fn(),
  mutate: vi.fn(),
});

describe('Integration: PR Status Update Flow', () => {
  let mockClient: ReturnType<typeof createMockClient>;

  beforeEach(() => {
    vi.clearAllMocks();
    mockClient = createMockClient();
  });

  describe('Full workflow: PR opens -> Issues detected -> Status updated', () => {
    const mockProjectResponse = {
      organization: {
        projectV2: {
          id: 'PVT_test123',
          title: 'Test Project',
          fields: {
            nodes: [
              {
                id: 'FIELD_STATUS',
                name: 'Status',
                dataType: 'SINGLE_SELECT',
                options: [
                  { id: 'OPT_BACKLOG', name: 'Backlog' },
                  { id: 'OPT_REVIEW', name: 'In Review' },
                  { id: 'OPT_DONE', name: 'Done' },
                ],
              },
            ],
          },
        },
      },
    };

    const mockIssueResponse = {
      repository: {
        issue: {
          id: 'ISSUE_NODE_123',
          number: 123,
          title: 'Test Issue',
          state: 'OPEN',
        },
      },
    };

    it('should detect issues from PR and update their status in project', async () => {
      // Setup: PR context
      const prContext = {
        title: 'feat: add new feature',
        body: 'This PR implements the feature.\n\nCloses #123',
        head: { ref: 'feature/123-new-feature' },
      };

      // Step 1: Detect issues from PR
      const detectedIssues = detectIssues(prContext);
      expect(detectedIssues.fromKeywords).toContain(123);
      expect(detectedIssues.fromBranch).toContain(123);
      expect(detectedIssues.all).toEqual([123]); // Deduplicated

      // Step 2: Find project
      mockClient.query.mockResolvedValueOnce(mockProjectResponse);
      const config: ExtendedProjectConfig = {
        project: { type: 'organization', owner: 'test-org', number: 1 },
        pr: { status: 'In Review' },
      };
      const project = await findProject(mockClient as unknown as GraphQLClient, config);
      expect(project.id).toBe('PVT_test123');
      expect(project.fields).toHaveLength(1);

      // Step 3: Get issue node ID
      mockClient.query.mockResolvedValueOnce(mockIssueResponse);
      const issueNodeId = await getIssueNodeId(
        mockClient as unknown as GraphQLClient,
        'test-owner',
        'test-repo',
        123
      );
      expect(issueNodeId).toBe('ISSUE_NODE_123');

      // Step 4: Check if issue is in project (not found)
      mockClient.query.mockResolvedValueOnce({
        node: {
          items: {
            nodes: [],
            pageInfo: { hasNextPage: false, endCursor: null },
          },
        },
      });
      const existingItemId = await findItemInProject(
        mockClient as unknown as GraphQLClient,
        project.id,
        issueNodeId!
      );
      expect(existingItemId).toBeNull();

      // Step 5: Add issue to project
      mockClient.mutate.mockResolvedValueOnce({
        addProjectV2ItemById: {
          item: { id: 'ITEM_NEW_123' },
        },
      });
      const newItemId = await addItemToProject(
        mockClient as unknown as GraphQLClient,
        project.id,
        issueNodeId!
      );
      expect(newItemId).toBe('ITEM_NEW_123');

      // Step 6: Update status field
      mockClient.mutate.mockResolvedValueOnce({
        updateProjectV2ItemFieldValue: { projectV2Item: { id: newItemId } },
      });
      const updateResult = await setFieldValue({
        client: mockClient as unknown as GraphQLClient,
        projectId: project.id,
        itemId: newItemId,
        fields: project.fields,
        fieldName: 'Status',
        value: 'In Review',
      });
      expect(updateResult).toBe(true);

      // Verify the mutation was called with correct option ID
      expect(mockClient.mutate).toHaveBeenLastCalledWith(
        expect.any(String),
        expect.objectContaining({
          optionId: 'OPT_REVIEW',
        })
      );
    });

    it('should handle issue already in project (skip add, update status)', async () => {
      const issueNodeId = 'ISSUE_NODE_456';
      const existingItemId = 'ITEM_EXISTING_456';

      // Issue already in project
      mockClient.query.mockResolvedValueOnce({
        node: {
          items: {
            nodes: [{ id: existingItemId, content: { id: issueNodeId } }],
            pageInfo: { hasNextPage: false, endCursor: null },
          },
        },
      });

      const foundItemId = await findItemInProject(
        mockClient as unknown as GraphQLClient,
        'PVT_test123',
        issueNodeId
      );
      expect(foundItemId).toBe(existingItemId);

      // Should not call addItemToProject, directly update status
      mockClient.mutate.mockResolvedValueOnce({
        updateProjectV2ItemFieldValue: { projectV2Item: { id: existingItemId } },
      });

      const fields: FieldInfo[] = [
        {
          id: 'FIELD_STATUS',
          name: 'Status',
          dataType: 'SINGLE_SELECT',
          options: [
            { id: 'OPT_REVIEW', name: 'In Review' },
          ],
        },
      ];

      const updateResult = await setFieldValue({
        client: mockClient as unknown as GraphQLClient,
        projectId: 'PVT_test123',
        itemId: foundItemId!,
        fields,
        fieldName: 'Status',
        value: 'In Review',
      });
      expect(updateResult).toBe(true);
    });

    it('should handle multiple issues from single PR', async () => {
      const prContext = {
        title: 'feat: implement features',
        body: 'Closes #100, Fixes #200, Resolves #300',
        head: { ref: 'main' },
      };

      const detectedIssues = detectIssues(prContext);
      expect(detectedIssues.all).toEqual([100, 200, 300]);
      expect(detectedIssues.all).toHaveLength(3);
    });

    it('should handle PR with no linked issues', async () => {
      const prContext = {
        title: 'chore: update dependencies',
        body: 'Regular maintenance update',
        head: { ref: 'chore/update-deps' },
      };

      const detectedIssues = detectIssues(prContext);
      expect(detectedIssues.all).toHaveLength(0);
    });
  });

  describe('Error handling in workflow', () => {
    it('should handle issue not found in repository', async () => {
      mockClient.query.mockResolvedValueOnce({
        repository: {
          issue: null,
        },
      });

      const issueNodeId = await getIssueNodeId(
        mockClient as unknown as GraphQLClient,
        'test-owner',
        'test-repo',
        999
      );
      expect(issueNodeId).toBeNull();
    });

    it('should handle project not found', async () => {
      mockClient.query.mockResolvedValueOnce({
        organization: {
          projectV2: null,
        },
      });

      const config: ExtendedProjectConfig = {
        project: { type: 'organization', owner: 'test-org', number: 999 },
      };

      await expect(
        findProject(mockClient as unknown as GraphQLClient, config)
      ).rejects.toThrow('Project not found');
    });

    it('should handle invalid status option gracefully', async () => {
      const fields: FieldInfo[] = [
        {
          id: 'FIELD_STATUS',
          name: 'Status',
          dataType: 'SINGLE_SELECT',
          options: [
            { id: 'OPT_1', name: 'Todo' },
            { id: 'OPT_2', name: 'Done' },
          ],
        },
      ];

      const result = await setFieldValue({
        client: mockClient as unknown as GraphQLClient,
        projectId: 'PVT_123',
        itemId: 'ITEM_1',
        fields,
        fieldName: 'Status',
        value: 'NonExistentStatus',
      });

      expect(result).toBe(false);
      expect(mockClient.mutate).not.toHaveBeenCalled();
    });

    it('should handle GraphQL API errors gracefully', async () => {
      mockClient.query.mockRejectedValueOnce(new Error('GraphQL API error'));

      await expect(
        getIssueNodeId(
          mockClient as unknown as GraphQLClient,
          'test-owner',
          'test-repo',
          123
        )
      ).resolves.toBeNull(); // Should return null, not throw
    });
  });

  describe('Configuration integration', () => {
    it('should load config with PR section', () => {
      const configYaml = `
project:
  type: organization
  owner: my-org
  number: 1
defaults:
  Status: Backlog
pr:
  status: In Review
  branch_pattern: "^feature/(\\\\d+)"
`;

      vi.mocked(fs.existsSync).mockReturnValue(true);
      vi.mocked(fs.readFileSync).mockReturnValue(configYaml);

      const config = loadConfig('.github/project-automation.yml');

      expect(config.project.type).toBe('organization');
      expect(config.project.owner).toBe('my-org');
      expect(config.pr?.status).toBe('In Review');
      expect(config.pr?.branch_pattern).toBe('^feature/(\\d+)');
    });

    it('should load config without PR section (backward compatible)', () => {
      const configYaml = `
project:
  type: repository
  owner: my-user
  number: 2
defaults:
  Status: Backlog
`;

      vi.mocked(fs.existsSync).mockReturnValue(true);
      vi.mocked(fs.readFileSync).mockReturnValue(configYaml);

      const config = loadConfig('.github/project-automation.yml');

      expect(config.project.type).toBe('repository');
      expect(config.pr).toBeUndefined();
    });

    it('should use custom branch pattern from config', () => {
      const prContext = {
        title: 'Test PR',
        body: null,
        head: { ref: 'custom-999-branch' },
      };

      // Default pattern won't match
      const defaultResult = detectIssues(prContext);
      expect(defaultResult.fromBranch).toHaveLength(0);

      // Custom pattern matches
      const customResult = detectIssues(prContext, '^custom-(\\d+)');
      expect(customResult.fromBranch).toContain(999);
    });
  });

  describe('Pagination handling', () => {
    it('should handle paginated project items', async () => {
      const targetIssueId = 'ISSUE_TARGET';

      // First page - not found
      mockClient.query.mockResolvedValueOnce({
        node: {
          items: {
            nodes: [
              { id: 'ITEM_1', content: { id: 'ISSUE_1' } },
              { id: 'ITEM_2', content: { id: 'ISSUE_2' } },
            ],
            pageInfo: { hasNextPage: true, endCursor: 'cursor_1' },
          },
        },
      });

      // Second page - not found
      mockClient.query.mockResolvedValueOnce({
        node: {
          items: {
            nodes: [
              { id: 'ITEM_3', content: { id: 'ISSUE_3' } },
              { id: 'ITEM_4', content: { id: 'ISSUE_4' } },
            ],
            pageInfo: { hasNextPage: true, endCursor: 'cursor_2' },
          },
        },
      });

      // Third page - found!
      mockClient.query.mockResolvedValueOnce({
        node: {
          items: {
            nodes: [
              { id: 'ITEM_TARGET', content: { id: targetIssueId } },
            ],
            pageInfo: { hasNextPage: false, endCursor: null },
          },
        },
      });

      const result = await findItemInProject(
        mockClient as unknown as GraphQLClient,
        'PVT_123',
        targetIssueId
      );

      expect(result).toBe('ITEM_TARGET');
      expect(mockClient.query).toHaveBeenCalledTimes(3);
    });
  });
});
