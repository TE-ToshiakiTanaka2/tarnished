import type { ExtendedProjectConfig } from './types.js';
/**
 * Load and validate configuration from YAML file
 */
export declare function loadConfig(configPath: string): ExtendedProjectConfig;
/**
 * Validate configuration object
 */
export declare function validateConfig(config: unknown): ExtendedProjectConfig;
