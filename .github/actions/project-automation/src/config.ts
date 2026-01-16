import * as core from '@actions/core';
import * as fs from 'fs';
import * as yaml from 'js-yaml';
import type { ProjectConfig } from './types.js';

/**
 * Load and validate configuration from YAML file
 */
export function loadConfig(configPath: string): ProjectConfig {
  core.info(`Loading configuration from: ${configPath}`);

  if (!fs.existsSync(configPath)) {
    throw new Error(`Configuration file not found: ${configPath}`);
  }

  const content = fs.readFileSync(configPath, 'utf8');
  const config = yaml.load(content) as unknown;

  return validateConfig(config);
}

/**
 * Validate configuration object
 */
export function validateConfig(config: unknown): ProjectConfig {
  if (!config || typeof config !== 'object') {
    throw new Error('Configuration must be an object');
  }

  const cfg = config as Record<string, unknown>;

  // Validate project section
  if (!cfg['project'] || typeof cfg['project'] !== 'object') {
    throw new Error('Configuration must have a "project" section');
  }

  const project = cfg['project'] as Record<string, unknown>;

  // Validate project.type
  if (project['type'] !== 'organization' && project['type'] !== 'repository') {
    throw new Error(
      'project.type must be "organization" or "repository"'
    );
  }

  // Validate project.owner
  if (typeof project['owner'] !== 'string' || project['owner'].length === 0) {
    throw new Error('project.owner must be a non-empty string');
  }

  // Validate project.number
  if (typeof project['number'] !== 'number' || project['number'] <= 0) {
    throw new Error('project.number must be a positive number');
  }

  // Validate defaults (optional)
  const defaults = cfg['defaults'];
  if (defaults !== undefined) {
    if (typeof defaults !== 'object' || defaults === null) {
      throw new Error('defaults must be an object');
    }

    const defaultsObj = defaults as Record<string, unknown>;
    for (const [key, value] of Object.entries(defaultsObj)) {
      if (typeof value !== 'string' && typeof value !== 'number') {
        throw new Error(
          `defaults.${key} must be a string or number`
        );
      }
    }
  }

  return {
    project: {
      type: project['type'] as 'organization' | 'repository',
      owner: project['owner'] as string,
      number: project['number'] as number,
    },
    defaults: defaults as Record<string, string | number> | undefined,
  };
}
