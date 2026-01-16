import { type VersionConfig } from "./types.js";
/**
 * Load and validate version configuration from file
 * @param configPath - Path to version.yml (default: .github/version.yml)
 * @returns Validated configuration or default config if file not found
 */
export declare function loadConfig(configPath?: string): Promise<VersionConfig>;
/**
 * Get the default configuration
 */
export declare function getDefaultConfig(): VersionConfig;
/**
 * Validate configuration structure
 */
export declare function validateConfig(config: unknown): config is VersionConfig;
