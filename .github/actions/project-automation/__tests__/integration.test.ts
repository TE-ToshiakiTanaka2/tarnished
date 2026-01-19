import * as fs from "node:fs";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { loadConfig } from "../src/config.js";
import type { GraphQLClient } from "../src/graphql/client.js";
import { setFieldValues } from "../src/project/fields.js";
import { findProject } from "../src/project/finder.js";
import { addItemToProject, findItemInProject } from "../src/project/item.js";
import type { ProjectConfig } from "../src/types.js";

// Mock @actions/core
vi.mock("@actions/core", () => ({
  info: vi.fn(),
  warning: vi.fn(),
  error: vi.fn(),
  debug: vi.fn(),
  setOutput: vi.fn(),
  setFailed: vi.fn(),
  getInput: vi.fn(),
}));

// Mock fs for config loading tests
vi.mock("fs", async () => {
  const actual = await vi.importActual("fs");
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

describe("Integration: Project Automation Flow", () => {
  let mockClient: ReturnType<typeof createMockClient>;

  beforeEach(() => {
    vi.clearAllMocks();
    mockClient = createMockClient();
  });

  describe("Full workflow: Issue created -> Added to Project -> Fields set", () => {
    const mockProjectResponse = {
      organization: {
        projectV2: {
          id: "PVT_org123",
          title: "Organization Project",
          fields: {
            nodes: [
              {
                id: "FIELD_STATUS",
                name: "Status",
                dataType: "SINGLE_SELECT",
                options: [
                  { id: "OPT_BACKLOG", name: "Backlog" },
                  { id: "OPT_TODO", name: "Todo" },
                  { id: "OPT_PROGRESS", name: "In Progress" },
                  { id: "OPT_DONE", name: "Done" },
                ],
              },
              {
                id: "FIELD_PRIORITY",
                name: "Priority",
                dataType: "SINGLE_SELECT",
                options: [
                  { id: "OPT_HIGH", name: "High" },
                  { id: "OPT_MED", name: "Medium" },
                  { id: "OPT_LOW", name: "Low" },
                ],
              },
            ],
          },
        },
      },
    };

    it("should add new issue to project and set default fields", async () => {
      const issueNodeId = "ISSUE_NEW_123";
      const config: ProjectConfig = {
        project: { type: "organization", owner: "test-org", number: 1 },
        defaults: { Status: "Backlog", Priority: "Medium" },
      };

      // Step 1: Find project
      mockClient.query.mockResolvedValueOnce(mockProjectResponse);
      const project = await findProject(mockClient as unknown as GraphQLClient, config);
      expect(project.id).toBe("PVT_org123");
      expect(project.fields).toHaveLength(2);

      // Step 2: Check if issue already in project (not found)
      mockClient.query.mockResolvedValueOnce({
        node: {
          items: {
            nodes: [],
            pageInfo: { hasNextPage: false, endCursor: null },
          },
        },
      });
      const existingItem = await findItemInProject(
        mockClient as unknown as GraphQLClient,
        project.id,
        issueNodeId,
      );
      expect(existingItem).toBeNull();

      // Step 3: Add issue to project
      mockClient.mutate.mockResolvedValueOnce({
        addProjectV2ItemById: { item: { id: "ITEM_NEW_123" } },
      });
      const itemId = await addItemToProject(
        mockClient as unknown as GraphQLClient,
        project.id,
        issueNodeId,
      );
      expect(itemId).toBe("ITEM_NEW_123");

      // Step 4: Set default field values
      mockClient.mutate
        .mockResolvedValueOnce({
          updateProjectV2ItemFieldValue: { projectV2Item: { id: itemId } },
        })
        .mockResolvedValueOnce({
          updateProjectV2ItemFieldValue: { projectV2Item: { id: itemId } },
        });

      const result = await setFieldValues(
        mockClient as unknown as GraphQLClient,
        project.id,
        itemId,
        project.fields,
        config.defaults ?? {},
      );

      expect(result.success).toBe(2);
      expect(result.failed).toBe(0);
    });

    it("should handle issue already in project (idempotency)", async () => {
      const issueNodeId = "ISSUE_EXISTING_456";
      const existingItemId = "ITEM_EXISTING_456";

      // Issue already exists in project
      mockClient.query.mockResolvedValueOnce({
        node: {
          items: {
            nodes: [{ id: existingItemId, content: { id: issueNodeId } }],
            pageInfo: { hasNextPage: false, endCursor: null },
          },
        },
      });

      const foundItem = await findItemInProject(
        mockClient as unknown as GraphQLClient,
        "PVT_org123",
        issueNodeId,
      );

      expect(foundItem).toBe(existingItemId);
      // addItemToProject should NOT be called
    });
  });

  describe("Configuration loading", () => {
    it("should load organization project config", () => {
      const configYaml = `
project:
  type: organization
  owner: my-org
  number: 5

defaults:
  Status: Backlog
  Priority: Medium
`;

      vi.mocked(fs.existsSync).mockReturnValue(true);
      vi.mocked(fs.readFileSync).mockReturnValue(configYaml);

      const config = loadConfig(".github/project-automation.yml");

      expect(config.project.type).toBe("organization");
      expect(config.project.owner).toBe("my-org");
      expect(config.project.number).toBe(5);
      expect(config.defaults?.Status).toBe("Backlog");
      expect(config.defaults?.Priority).toBe("Medium");
    });

    it("should load user project config", () => {
      const configYaml = `
project:
  type: user
  owner: my-user
  number: 1
`;

      vi.mocked(fs.existsSync).mockReturnValue(true);
      vi.mocked(fs.readFileSync).mockReturnValue(configYaml);

      const config = loadConfig(".github/project-automation.yml");

      expect(config.project.type).toBe("user");
      expect(config.defaults).toBeUndefined();
    });

    it("should throw error for missing config file", () => {
      vi.mocked(fs.existsSync).mockReturnValue(false);

      expect(() => loadConfig(".github/nonexistent.yml")).toThrow("Configuration file not found");
    });
  });

  describe("Error scenarios", () => {
    it("should handle project not found", async () => {
      mockClient.query.mockResolvedValueOnce({
        organization: { projectV2: null },
      });

      const config: ProjectConfig = {
        project: { type: "organization", owner: "test-org", number: 999 },
      };

      await expect(findProject(mockClient as unknown as GraphQLClient, config)).rejects.toThrow(
        "Project not found",
      );
    });

    it("should handle partial field update failures", async () => {
      const fields = [
        {
          id: "FIELD_STATUS",
          name: "Status",
          dataType: "SINGLE_SELECT" as const,
          options: [{ id: "OPT_1", name: "Todo" }],
        },
      ];

      // First field succeeds, second fails (field not found)
      mockClient.mutate.mockResolvedValueOnce({
        updateProjectV2ItemFieldValue: { projectV2Item: { id: "ITEM_1" } },
      });

      const result = await setFieldValues(
        mockClient as unknown as GraphQLClient,
        "PVT_123",
        "ITEM_1",
        fields,
        { Status: "Todo", NonExistent: "Value" },
      );

      expect(result.success).toBe(1);
      expect(result.failed).toBe(1);
    });
  });

  describe("User project workflow", () => {
    it("should work with user projects", async () => {
      const mockUserProjectResponse = {
        user: {
          projectV2: {
            id: "PVT_user789",
            title: "User Project",
            fields: {
              nodes: [
                {
                  id: "FIELD_STATUS",
                  name: "Status",
                  dataType: "SINGLE_SELECT",
                  options: [{ id: "OPT_1", name: "Done" }],
                },
              ],
            },
          },
        },
      };

      mockClient.query.mockResolvedValueOnce(mockUserProjectResponse);

      const config: ProjectConfig = {
        project: { type: "user", owner: "test-user", number: 2 },
      };

      const project = await findProject(mockClient as unknown as GraphQLClient, config);

      expect(project.id).toBe("PVT_user789");
      expect(project.title).toBe("User Project");
    });
  });
});
