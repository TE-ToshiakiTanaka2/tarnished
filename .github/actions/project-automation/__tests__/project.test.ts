import { beforeEach, describe, expect, it, vi } from "vitest";
import type { GraphQLClient } from "../src/graphql/client.js";
import { setFieldValue, setFieldValues } from "../src/project/fields.js";
import { findFieldByName, findProject } from "../src/project/finder.js";
import { addItemToProject, findItemInProject } from "../src/project/item.js";
import type { FieldInfo, ProjectConfig } from "../src/types.js";

// Mock @actions/core
vi.mock("@actions/core", () => ({
  info: vi.fn(),
  warning: vi.fn(),
  error: vi.fn(),
  debug: vi.fn(),
}));

// Create mock GraphQL client
const createMockClient = () => ({
  query: vi.fn(),
  mutate: vi.fn(),
});

describe("project/finder", () => {
  describe("findProject", () => {
    it("should find an organization project", async () => {
      const mockClient = createMockClient();
      const config: ProjectConfig = {
        project: {
          type: "organization",
          owner: "my-org",
          number: 1,
        },
      };

      mockClient.query.mockResolvedValue({
        organization: {
          projectV2: {
            id: "PVT_123",
            title: "My Project",
            fields: {
              nodes: [
                {
                  id: "FIELD_1",
                  name: "Status",
                  dataType: "SINGLE_SELECT",
                  options: [{ id: "OPT_1", name: "Todo" }],
                },
                {
                  id: "FIELD_2",
                  name: "Priority",
                  dataType: "SINGLE_SELECT",
                  options: [{ id: "OPT_2", name: "High" }],
                },
              ],
            },
          },
        },
      });

      const result = await findProject(mockClient as unknown as GraphQLClient, config);

      expect(result.id).toBe("PVT_123");
      expect(result.title).toBe("My Project");
      expect(result.fields).toHaveLength(2);
      expect(result.fields[0]?.name).toBe("Status");
    });

    it("should find a user project", async () => {
      const mockClient = createMockClient();
      const config: ProjectConfig = {
        project: {
          type: "user",
          owner: "my-user",
          number: 2,
        },
      };

      mockClient.query.mockResolvedValue({
        user: {
          projectV2: {
            id: "PVT_456",
            title: "User Project",
            fields: {
              nodes: [{ id: "FIELD_1", name: "Status", dataType: "SINGLE_SELECT" }],
            },
          },
        },
      });

      const result = await findProject(mockClient as unknown as GraphQLClient, config);

      expect(result.id).toBe("PVT_456");
      expect(result.title).toBe("User Project");
    });

    it("should throw error if project not found", async () => {
      const mockClient = createMockClient();
      const config: ProjectConfig = {
        project: {
          type: "organization",
          owner: "my-org",
          number: 999,
        },
      };

      mockClient.query.mockResolvedValue({
        organization: {
          projectV2: null,
        },
      });

      await expect(findProject(mockClient as unknown as GraphQLClient, config)).rejects.toThrow(
        "Project not found",
      );
    });
  });

  describe("findFieldByName", () => {
    const fields: FieldInfo[] = [
      { id: "F1", name: "Status", dataType: "SINGLE_SELECT" },
      { id: "F2", name: "Priority", dataType: "SINGLE_SELECT" },
      { id: "F3", name: "Size", dataType: "NUMBER" },
    ];

    it("should find field by exact name", () => {
      const result = findFieldByName(fields, "Status");
      expect(result?.id).toBe("F1");
    });

    it("should find field case-insensitively", () => {
      const result = findFieldByName(fields, "status");
      expect(result?.id).toBe("F1");
    });

    it("should return undefined for non-existent field", () => {
      const result = findFieldByName(fields, "NonExistent");
      expect(result).toBeUndefined();
    });
  });
});

describe("project/item", () => {
  describe("findItemInProject", () => {
    it("should find existing item in project", async () => {
      const mockClient = createMockClient();
      mockClient.query.mockResolvedValue({
        node: {
          items: {
            nodes: [
              { id: "ITEM_1", content: { id: "ISSUE_123" } },
              { id: "ITEM_2", content: { id: "ISSUE_456" } },
            ],
            pageInfo: { hasNextPage: false, endCursor: null },
          },
        },
      });

      const result = await findItemInProject(
        mockClient as unknown as GraphQLClient,
        "PVT_123",
        "ISSUE_123",
      );

      expect(result).toBe("ITEM_1");
    });

    it("should return null if item not found", async () => {
      const mockClient = createMockClient();
      mockClient.query.mockResolvedValue({
        node: {
          items: {
            nodes: [{ id: "ITEM_1", content: { id: "ISSUE_456" } }],
            pageInfo: { hasNextPage: false, endCursor: null },
          },
        },
      });

      const result = await findItemInProject(
        mockClient as unknown as GraphQLClient,
        "PVT_123",
        "ISSUE_123",
      );

      expect(result).toBeNull();
    });

    it("should handle pagination", async () => {
      const mockClient = createMockClient();
      mockClient.query
        .mockResolvedValueOnce({
          node: {
            items: {
              nodes: [{ id: "ITEM_1", content: { id: "ISSUE_1" } }],
              pageInfo: { hasNextPage: true, endCursor: "cursor1" },
            },
          },
        })
        .mockResolvedValueOnce({
          node: {
            items: {
              nodes: [{ id: "ITEM_2", content: { id: "ISSUE_123" } }],
              pageInfo: { hasNextPage: false, endCursor: null },
            },
          },
        });

      const result = await findItemInProject(
        mockClient as unknown as GraphQLClient,
        "PVT_123",
        "ISSUE_123",
      );

      expect(result).toBe("ITEM_2");
      expect(mockClient.query).toHaveBeenCalledTimes(2);
    });
  });

  describe("addItemToProject", () => {
    it("should add item to project", async () => {
      const mockClient = createMockClient();
      mockClient.mutate.mockResolvedValue({
        addProjectV2ItemById: {
          item: { id: "NEW_ITEM_123" },
        },
      });

      const result = await addItemToProject(
        mockClient as unknown as GraphQLClient,
        "PVT_123",
        "ISSUE_123",
      );

      expect(result).toBe("NEW_ITEM_123");
    });
  });
});

describe("project/fields", () => {
  const fields: FieldInfo[] = [
    {
      id: "F1",
      name: "Status",
      dataType: "SINGLE_SELECT",
      options: [
        { id: "OPT_1", name: "Todo" },
        { id: "OPT_2", name: "In Progress" },
        { id: "OPT_3", name: "Done" },
      ],
    },
    {
      id: "F2",
      name: "Priority",
      dataType: "SINGLE_SELECT",
      options: [
        { id: "OPT_HIGH", name: "High" },
        { id: "OPT_MED", name: "Medium" },
        { id: "OPT_LOW", name: "Low" },
      ],
    },
    { id: "F3", name: "Size", dataType: "NUMBER" },
    { id: "F4", name: "Notes", dataType: "TEXT" },
  ];

  describe("setFieldValue", () => {
    it("should set single select field value", async () => {
      const mockClient = createMockClient();
      mockClient.mutate.mockResolvedValue({
        updateProjectV2ItemFieldValue: { projectV2Item: { id: "ITEM_1" } },
      });

      const result = await setFieldValue({
        client: mockClient as unknown as GraphQLClient,
        projectId: "PVT_123",
        itemId: "ITEM_1",
        fields,
        fieldName: "Status",
        value: "Todo",
      });

      expect(result).toBe(true);
      expect(mockClient.mutate).toHaveBeenCalledWith(
        expect.any(String),
        expect.objectContaining({
          optionId: "OPT_1",
        }),
      );
    });

    it("should set single select field case-insensitively", async () => {
      const mockClient = createMockClient();
      mockClient.mutate.mockResolvedValue({
        updateProjectV2ItemFieldValue: { projectV2Item: { id: "ITEM_1" } },
      });

      const result = await setFieldValue({
        client: mockClient as unknown as GraphQLClient,
        projectId: "PVT_123",
        itemId: "ITEM_1",
        fields,
        fieldName: "status",
        value: "todo",
      });

      expect(result).toBe(true);
    });

    it("should return false for non-existent field", async () => {
      const mockClient = createMockClient();

      const result = await setFieldValue({
        client: mockClient as unknown as GraphQLClient,
        projectId: "PVT_123",
        itemId: "ITEM_1",
        fields,
        fieldName: "NonExistent",
        value: "Value",
      });

      expect(result).toBe(false);
      expect(mockClient.mutate).not.toHaveBeenCalled();
    });

    it("should return false for invalid option value", async () => {
      const mockClient = createMockClient();

      const result = await setFieldValue({
        client: mockClient as unknown as GraphQLClient,
        projectId: "PVT_123",
        itemId: "ITEM_1",
        fields,
        fieldName: "Status",
        value: "InvalidOption",
      });

      expect(result).toBe(false);
    });

    it("should set number field value", async () => {
      const mockClient = createMockClient();
      mockClient.mutate.mockResolvedValue({
        updateProjectV2ItemFieldValue: { projectV2Item: { id: "ITEM_1" } },
      });

      const result = await setFieldValue({
        client: mockClient as unknown as GraphQLClient,
        projectId: "PVT_123",
        itemId: "ITEM_1",
        fields,
        fieldName: "Size",
        value: 5,
      });

      expect(result).toBe(true);
      expect(mockClient.mutate).toHaveBeenCalledWith(
        expect.any(String),
        expect.objectContaining({
          number: 5,
        }),
      );
    });

    it("should set text field value", async () => {
      const mockClient = createMockClient();
      mockClient.mutate.mockResolvedValue({
        updateProjectV2ItemFieldValue: { projectV2Item: { id: "ITEM_1" } },
      });

      const result = await setFieldValue({
        client: mockClient as unknown as GraphQLClient,
        projectId: "PVT_123",
        itemId: "ITEM_1",
        fields,
        fieldName: "Notes",
        value: "Some notes",
      });

      expect(result).toBe(true);
      expect(mockClient.mutate).toHaveBeenCalledWith(
        expect.any(String),
        expect.objectContaining({
          text: "Some notes",
        }),
      );
    });
  });

  describe("setFieldValues", () => {
    it("should set multiple field values", async () => {
      const mockClient = createMockClient();
      mockClient.mutate.mockResolvedValue({
        updateProjectV2ItemFieldValue: { projectV2Item: { id: "ITEM_1" } },
      });

      const result = await setFieldValues(
        mockClient as unknown as GraphQLClient,
        "PVT_123",
        "ITEM_1",
        fields,
        { status: "Todo", priority: "High" },
      );

      expect(result.success).toBe(2);
      expect(result.failed).toBe(0);
    });

    it("should count failed fields", async () => {
      const mockClient = createMockClient();
      mockClient.mutate.mockResolvedValue({
        updateProjectV2ItemFieldValue: { projectV2Item: { id: "ITEM_1" } },
      });

      const result = await setFieldValues(
        mockClient as unknown as GraphQLClient,
        "PVT_123",
        "ITEM_1",
        fields,
        { status: "Todo", nonexistent: "Value" },
      );

      expect(result.success).toBe(1);
      expect(result.failed).toBe(1);
    });
  });
});
