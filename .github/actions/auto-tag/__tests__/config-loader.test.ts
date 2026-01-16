import { describe, expect, it } from "vitest";
import { getDefaultConfig, validateConfig } from "../src/config-loader.js";
import { DEFAULT_CONFIG } from "../src/types.js";

describe("validateConfig", () => {
  it("should validate correct config", () => {
    const config = {
      versioning: {
        branch_prefixes: {
          major: ["major/"],
          minor: ["release/"],
          patch: ["feature/"],
        },
      },
    };

    expect(validateConfig(config)).toBe(true);
  });

  it("should validate config with multiple prefixes", () => {
    const config = {
      versioning: {
        branch_prefixes: {
          major: ["major/", "breaking/"],
          minor: ["release/", "feat/"],
          patch: ["feature/", "fix/"],
        },
      },
    };

    expect(validateConfig(config)).toBe(true);
  });

  it("should validate partial config (only some prefixes)", () => {
    const config = {
      versioning: {
        branch_prefixes: {
          major: ["major/"],
          minor: [],
          patch: ["feature/"],
        },
      },
    };

    expect(validateConfig(config)).toBe(true);
  });

  it("should reject null", () => {
    expect(validateConfig(null)).toBe(false);
  });

  it("should reject undefined", () => {
    expect(validateConfig(undefined)).toBe(false);
  });

  it("should reject empty object", () => {
    expect(validateConfig({})).toBe(false);
  });

  it("should reject config without versioning", () => {
    expect(validateConfig({ other: "value" })).toBe(false);
  });

  it("should reject config without branch_prefixes", () => {
    expect(validateConfig({ versioning: {} })).toBe(false);
  });

  it("should reject config with non-array prefixes", () => {
    const config = {
      versioning: {
        branch_prefixes: {
          major: "major/",
          minor: "release/",
          patch: "feature/",
        },
      },
    };

    expect(validateConfig(config)).toBe(false);
  });

  it("should reject config with non-string array elements", () => {
    const config = {
      versioning: {
        branch_prefixes: {
          major: [123],
          minor: ["release/"],
          patch: ["feature/"],
        },
      },
    };

    expect(validateConfig(config)).toBe(false);
  });
});

describe("getDefaultConfig", () => {
  it("should return default config", () => {
    const config = getDefaultConfig();

    expect(config).toEqual(DEFAULT_CONFIG);
  });

  it("should return a new object each time", () => {
    const config1 = getDefaultConfig();
    const config2 = getDefaultConfig();

    expect(config1).not.toBe(config2);
    expect(config1).toEqual(config2);
  });

  it("should have correct default major prefixes", () => {
    const config = getDefaultConfig();

    expect(config.versioning.branch_prefixes.major).toContain("major/");
  });

  it("should have correct default minor prefixes", () => {
    const config = getDefaultConfig();

    expect(config.versioning.branch_prefixes.minor).toContain("release/");
  });

  it("should have correct default patch prefixes", () => {
    const config = getDefaultConfig();

    expect(config.versioning.branch_prefixes.patch).toContain("feature/");
  });
});
