import { describe, expect, it } from "vitest";
import { validateConfig } from "../src/config.js";

describe("validateConfig", () => {
  describe("basic validation", () => {
    it("validates a minimal valid config", () => {
      const config = {
        project: {
          type: "organization",
          owner: "my-org",
          number: 1,
        },
      };
      const result = validateConfig(config);
      expect(result.project.type).toBe("organization");
      expect(result.project.owner).toBe("my-org");
      expect(result.project.number).toBe(1);
      expect(result.defaults).toBeUndefined();
      expect(result.pr).toBeUndefined();
    });

    it("validates config with user type", () => {
      const config = {
        project: {
          type: "user",
          owner: "my-user",
          number: 2,
        },
      };
      const result = validateConfig(config);
      expect(result.project.type).toBe("user");
    });

    it("throws for missing project section", () => {
      const config = {};
      expect(() => validateConfig(config)).toThrow('must have a "project" section');
    });

    it("throws for invalid project type", () => {
      const config = {
        project: {
          type: "invalid",
          owner: "test",
          number: 1,
        },
      };
      expect(() => validateConfig(config)).toThrow("project.type must be");
    });

    it("throws for empty owner", () => {
      const config = {
        project: {
          type: "organization",
          owner: "",
          number: 1,
        },
      };
      expect(() => validateConfig(config)).toThrow("project.owner must be");
    });

    it("throws for non-positive number", () => {
      const config = {
        project: {
          type: "organization",
          owner: "test",
          number: 0,
        },
      };
      expect(() => validateConfig(config)).toThrow("project.number must be");
    });
  });

  describe("defaults validation", () => {
    it("validates config with defaults", () => {
      const config = {
        project: {
          type: "organization",
          owner: "test",
          number: 1,
        },
        defaults: {
          Status: "Backlog",
          Priority: "High",
        },
      };
      const result = validateConfig(config);
      expect(result.defaults).toEqual({
        Status: "Backlog",
        Priority: "High",
      });
    });

    it("validates defaults with number values", () => {
      const config = {
        project: {
          type: "organization",
          owner: "test",
          number: 1,
        },
        defaults: {
          Points: 5,
        },
      };
      const result = validateConfig(config);
      expect(result.defaults?.Points).toBe(5);
    });

    it("throws for invalid defaults value type", () => {
      const config = {
        project: {
          type: "organization",
          owner: "test",
          number: 1,
        },
        defaults: {
          Invalid: { nested: "object" },
        },
      };
      expect(() => validateConfig(config)).toThrow("defaults.Invalid must be");
    });
  });

  describe("pr section validation", () => {
    it("validates config with pr section", () => {
      const config = {
        project: {
          type: "organization",
          owner: "test",
          number: 1,
        },
        pr: {
          status: "In Review",
        },
      };
      const result = validateConfig(config);
      expect(result.pr?.status).toBe("In Review");
      expect(result.pr?.branch_pattern).toBeUndefined();
    });

    it("validates pr section with branch_pattern", () => {
      const config = {
        project: {
          type: "organization",
          owner: "test",
          number: 1,
        },
        pr: {
          status: "In Review",
          branch_pattern: "^feature/(\\d+)",
        },
      };
      const result = validateConfig(config);
      expect(result.pr?.status).toBe("In Review");
      expect(result.pr?.branch_pattern).toBe("^feature/(\\d+)");
    });

    it("throws for empty pr.status", () => {
      const config = {
        project: {
          type: "organization",
          owner: "test",
          number: 1,
        },
        pr: {
          status: "",
        },
      };
      expect(() => validateConfig(config)).toThrow("pr.status must be");
    });

    it("throws for missing pr.status", () => {
      const config = {
        project: {
          type: "organization",
          owner: "test",
          number: 1,
        },
        pr: {},
      };
      expect(() => validateConfig(config)).toThrow("pr.status must be");
    });

    it("throws for invalid pr.branch_pattern type", () => {
      const config = {
        project: {
          type: "organization",
          owner: "test",
          number: 1,
        },
        pr: {
          status: "In Review",
          branch_pattern: 123,
        },
      };
      expect(() => validateConfig(config)).toThrow("pr.branch_pattern must be");
    });

    it("throws for invalid regex in pr.branch_pattern", () => {
      const config = {
        project: {
          type: "organization",
          owner: "test",
          number: 1,
        },
        pr: {
          status: "In Review",
          branch_pattern: "[invalid",
        },
      };
      expect(() => validateConfig(config)).toThrow("valid regular expression");
    });
  });

  describe("backward compatibility", () => {
    it("works without pr section (existing configs)", () => {
      const config = {
        project: {
          type: "organization",
          owner: "test",
          number: 1,
        },
        defaults: {
          Status: "Backlog",
        },
      };
      const result = validateConfig(config);
      expect(result.pr).toBeUndefined();
      expect(result.defaults?.Status).toBe("Backlog");
    });
  });

  describe("full config validation", () => {
    it("validates a complete config with all sections", () => {
      const config = {
        project: {
          type: "organization",
          owner: "my-org",
          number: 1,
        },
        defaults: {
          Status: "Backlog",
          Priority: "Medium",
        },
        pr: {
          status: "In Review",
          branch_pattern: "^(?:feature|fix)/(\\d+)",
        },
      };
      const result = validateConfig(config);

      expect(result.project.type).toBe("organization");
      expect(result.project.owner).toBe("my-org");
      expect(result.project.number).toBe(1);
      expect(result.defaults?.Status).toBe("Backlog");
      expect(result.defaults?.Priority).toBe("Medium");
      expect(result.pr?.status).toBe("In Review");
      expect(result.pr?.branch_pattern).toBe("^(?:feature|fix)/(\\d+)");
    });
  });
});
