import { describe, expect, it } from "vitest";
import { DEFAULT_CONFIG } from "../src/types.js";
import {
  calculateNextVersion,
  detectVersionType,
  parseBranchName,
  parseVersion,
} from "../src/version-detector.js";

describe("parseBranchName", () => {
  it("should parse standard branch name with hash", () => {
    const result = parseBranchName("feature/tanaka/#123/add-login");

    expect(result).toEqual({
      type: "feature",
      assignee: "tanaka",
      issueNumber: 123,
      description: "add-login",
      raw: "feature/tanaka/#123/add-login",
    });
  });

  it("should parse branch name without hash", () => {
    const result = parseBranchName("feature/tanaka/123/add-login");

    expect(result).toEqual({
      type: "feature",
      assignee: "tanaka",
      issueNumber: 123,
      description: "add-login",
      raw: "feature/tanaka/123/add-login",
    });
  });

  it("should handle complex descriptions with hyphens", () => {
    const result = parseBranchName("release/yamada/#45/v2-major-release-update");

    expect(result).toEqual({
      type: "release",
      assignee: "yamada",
      issueNumber: 45,
      description: "v2-major-release-update",
      raw: "release/yamada/#45/v2-major-release-update",
    });
  });

  it("should handle invalid format gracefully", () => {
    const result = parseBranchName("main");

    expect(result.type).toBe("main");
    expect(result.issueNumber).toBeNull();
  });

  it("should handle partial branch names", () => {
    const result = parseBranchName("feature/tanaka");

    expect(result.type).toBe("feature");
    expect(result.assignee).toBe("tanaka");
    expect(result.issueNumber).toBeNull();
  });
});

describe("detectVersionType", () => {
  it("should detect major version type", () => {
    const branchInfo = parseBranchName("major/tanaka/#1/breaking-change");
    const result = detectVersionType(branchInfo, DEFAULT_CONFIG);

    expect(result).toBe("major");
  });

  it("should detect minor version type from release prefix", () => {
    const branchInfo = parseBranchName("release/tanaka/#2/new-feature");
    const result = detectVersionType(branchInfo, DEFAULT_CONFIG);

    expect(result).toBe("minor");
  });

  it("should detect patch version type from feature prefix", () => {
    const branchInfo = parseBranchName("feature/tanaka/#3/add-button");
    const result = detectVersionType(branchInfo, DEFAULT_CONFIG);

    expect(result).toBe("patch");
  });

  it("should default to rc for unknown prefixes", () => {
    const branchInfo = parseBranchName("bugfix/tanaka/#4/fix-bug");
    const result = detectVersionType(branchInfo, DEFAULT_CONFIG);

    expect(result).toBe("rc");
  });

  it("should default to rc for hotfix prefix", () => {
    const branchInfo = parseBranchName("hotfix/tanaka/#5/urgent-fix");
    const result = detectVersionType(branchInfo, DEFAULT_CONFIG);

    expect(result).toBe("rc");
  });

  it("should default to rc for docs prefix", () => {
    const branchInfo = parseBranchName("docs/tanaka/#6/update-readme");
    const result = detectVersionType(branchInfo, DEFAULT_CONFIG);

    expect(result).toBe("rc");
  });
});

describe("parseVersion", () => {
  it("should parse version with v prefix", () => {
    const result = parseVersion("v1.2.3");

    expect(result).toEqual({
      major: 1,
      minor: 2,
      patch: 3,
      prerelease: null,
    });
  });

  it("should parse version without v prefix", () => {
    const result = parseVersion("1.2.3");

    expect(result).toEqual({
      major: 1,
      minor: 2,
      patch: 3,
      prerelease: null,
    });
  });

  it("should parse version with prerelease", () => {
    const result = parseVersion("v1.2.3-rc.1");

    expect(result).toEqual({
      major: 1,
      minor: 2,
      patch: 3,
      prerelease: "rc.1",
    });
  });

  it("should parse version with complex prerelease", () => {
    const result = parseVersion("v1.2.3-beta.2.test");

    expect(result).toEqual({
      major: 1,
      minor: 2,
      patch: 3,
      prerelease: "beta.2.test",
    });
  });

  it("should return null for invalid version", () => {
    const result = parseVersion("invalid");

    expect(result).toBeNull();
  });

  it("should return null for empty string", () => {
    const result = parseVersion("");

    expect(result).toBeNull();
  });
});

describe("calculateNextVersion", () => {
  it("should increment major version", () => {
    const current = { major: 1, minor: 2, patch: 3, prerelease: null };
    const result = calculateNextVersion(current, "major");

    expect(result).toBe("v2.0.0");
  });

  it("should increment minor version", () => {
    const current = { major: 1, minor: 2, patch: 3, prerelease: null };
    const result = calculateNextVersion(current, "minor");

    expect(result).toBe("v1.3.0");
  });

  it("should increment patch version", () => {
    const current = { major: 1, minor: 2, patch: 3, prerelease: null };
    const result = calculateNextVersion(current, "patch");

    expect(result).toBe("v1.2.4");
  });

  it("should create first RC version", () => {
    const current = { major: 1, minor: 0, patch: 0, prerelease: null };
    const result = calculateNextVersion(current, "rc", []);

    expect(result).toBe("v1.0.1-rc.1");
  });

  it("should increment RC version", () => {
    const current = { major: 1, minor: 0, patch: 0, prerelease: null };
    const existingRcs = ["v1.0.1-rc.1", "v1.0.1-rc.2"];
    const result = calculateNextVersion(current, "rc", existingRcs);

    expect(result).toBe("v1.0.1-rc.3");
  });

  it("should start from v0.0.1 when no existing tags", () => {
    const result = calculateNextVersion(null, "patch");

    expect(result).toBe("v0.0.1");
  });

  it("should create major version from null", () => {
    const result = calculateNextVersion(null, "major");

    expect(result).toBe("v1.0.0");
  });

  it("should create minor version from null", () => {
    const result = calculateNextVersion(null, "minor");

    expect(result).toBe("v0.1.0");
  });

  it("should create RC from null", () => {
    const result = calculateNextVersion(null, "rc", []);

    expect(result).toBe("v0.0.1-rc.1");
  });
});
