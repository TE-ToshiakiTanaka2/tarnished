import * as fs from "node:fs";
import * as path from "node:path";
import * as core from "@actions/core";
import * as yaml from "js-yaml";
import { DEFAULT_CONFIG, type VersionConfig } from "./types.js";

const DEFAULT_CONFIG_PATH = ".github/version.yml";

/**
 * Load and validate version configuration from file
 * @param configPath - Path to version.yml (default: .github/version.yml)
 * @returns Validated configuration or default config if file not found
 */
export async function loadConfig(configPath?: string): Promise<VersionConfig> {
  const filePath = configPath ?? DEFAULT_CONFIG_PATH;
  const absolutePath = path.resolve(process.cwd(), filePath);

  try {
    if (!fs.existsSync(absolutePath)) {
      core.info(`Configuration file not found at ${filePath}, using default config`);
      return getDefaultConfig();
    }

    const content = fs.readFileSync(absolutePath, "utf-8");
    const parsed = yaml.load(content);

    if (!validateConfig(parsed)) {
      core.warning(`Invalid configuration in ${filePath}, using default config`);
      return getDefaultConfig();
    }

    // Merge with defaults to ensure all fields are present
    return mergeWithDefaults(parsed);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    core.warning(`Failed to load configuration: ${message}, using default config`);
    return getDefaultConfig();
  }
}

/**
 * Get the default configuration
 */
export function getDefaultConfig(): VersionConfig {
  return structuredClone(DEFAULT_CONFIG);
}

/**
 * Validate configuration structure
 */
export function validateConfig(config: unknown): config is VersionConfig {
  if (!config || typeof config !== "object") {
    return false;
  }

  const cfg = config as Record<string, unknown>;

  if (!cfg.versioning || typeof cfg.versioning !== "object") {
    return false;
  }

  const versioning = cfg.versioning as Record<string, unknown>;

  if (!versioning.branch_prefixes || typeof versioning.branch_prefixes !== "object") {
    return false;
  }

  const prefixes = versioning.branch_prefixes as Record<string, unknown>;

  // Check that at least one of major, minor, or patch is an array
  const hasMajor = Array.isArray(prefixes.major);
  const hasMinor = Array.isArray(prefixes.minor);
  const hasPatch = Array.isArray(prefixes.patch);

  if (!hasMajor && !hasMinor && !hasPatch) {
    return false;
  }

  // Validate that array elements are strings
  if (hasMajor && !(prefixes.major as unknown[]).every((p) => typeof p === "string")) {
    return false;
  }
  if (hasMinor && !(prefixes.minor as unknown[]).every((p) => typeof p === "string")) {
    return false;
  }
  if (hasPatch && !(prefixes.patch as unknown[]).every((p) => typeof p === "string")) {
    return false;
  }

  return true;
}

/**
 * Merge partial config with defaults
 */
function mergeWithDefaults(config: VersionConfig): VersionConfig {
  const defaults = getDefaultConfig();

  return {
    versioning: {
      branch_prefixes: {
        major: config.versioning.branch_prefixes.major ?? defaults.versioning.branch_prefixes.major,
        minor: config.versioning.branch_prefixes.minor ?? defaults.versioning.branch_prefixes.minor,
        patch: config.versioning.branch_prefixes.patch ?? defaults.versioning.branch_prefixes.patch,
      },
    },
  };
}
