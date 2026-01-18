import { describe, it, expect, vi, beforeEach } from 'vitest';
import * as fs from 'fs';
import { loadConfig, validateConfig } from '../src/config.js';

// Mock fs module
vi.mock('fs');

// Mock @actions/core
vi.mock('@actions/core', () => ({
  info: vi.fn(),
  warning: vi.fn(),
  error: vi.fn(),
  debug: vi.fn(),
}));

describe('config', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  describe('validateConfig', () => {
    it('should validate a valid organization config', () => {
      const config = {
        project: {
          type: 'organization',
          owner: 'my-org',
          number: 1,
        },
        defaults: {
          status: 'Backlog',
          priority: 'Medium',
        },
      };

      const result = validateConfig(config);

      expect(result.project.type).toBe('organization');
      expect(result.project.owner).toBe('my-org');
      expect(result.project.number).toBe(1);
      expect(result.defaults?.status).toBe('Backlog');
      expect(result.defaults?.priority).toBe('Medium');
    });

    it('should validate a valid user config', () => {
      const config = {
        project: {
          type: 'user',
          owner: 'my-user',
          number: 5,
        },
      };

      const result = validateConfig(config);

      expect(result.project.type).toBe('user');
      expect(result.project.owner).toBe('my-user');
      expect(result.project.number).toBe(5);
      expect(result.defaults).toBeUndefined();
    });

    it('should throw error for missing project section', () => {
      const config = {};

      expect(() => validateConfig(config)).toThrow('Configuration must have a "project" section');
    });

    it('should throw error for invalid project type', () => {
      const config = {
        project: {
          type: 'invalid',
          owner: 'my-org',
          number: 1,
        },
      };

      expect(() => validateConfig(config)).toThrow('project.type must be "organization" or "user"');
    });

    it('should throw error for empty owner', () => {
      const config = {
        project: {
          type: 'organization',
          owner: '',
          number: 1,
        },
      };

      expect(() => validateConfig(config)).toThrow('project.owner must be a non-empty string');
    });

    it('should throw error for invalid project number', () => {
      const config = {
        project: {
          type: 'organization',
          owner: 'my-org',
          number: 0,
        },
      };

      expect(() => validateConfig(config)).toThrow('project.number must be a positive number');
    });

    it('should throw error for negative project number', () => {
      const config = {
        project: {
          type: 'organization',
          owner: 'my-org',
          number: -1,
        },
      };

      expect(() => validateConfig(config)).toThrow('project.number must be a positive number');
    });

    it('should throw error for invalid defaults value', () => {
      const config = {
        project: {
          type: 'organization',
          owner: 'my-org',
          number: 1,
        },
        defaults: {
          status: { invalid: 'object' },
        },
      };

      expect(() => validateConfig(config)).toThrow('defaults.status must be a string or number');
    });

    it('should allow number values in defaults', () => {
      const config = {
        project: {
          type: 'organization',
          owner: 'my-org',
          number: 1,
        },
        defaults: {
          size: 5,
        },
      };

      const result = validateConfig(config);

      expect(result.defaults?.size).toBe(5);
    });
  });

  describe('loadConfig', () => {
    it('should load and validate config from file', () => {
      const yamlContent = `
project:
  type: organization
  owner: my-org
  number: 1
defaults:
  status: Backlog
`;
      vi.mocked(fs.existsSync).mockReturnValue(true);
      vi.mocked(fs.readFileSync).mockReturnValue(yamlContent);

      const result = loadConfig('.github/project-automation.yml');

      expect(result.project.type).toBe('organization');
      expect(result.project.owner).toBe('my-org');
      expect(result.project.number).toBe(1);
    });

    it('should throw error if config file not found', () => {
      vi.mocked(fs.existsSync).mockReturnValue(false);

      expect(() => loadConfig('.github/project-automation.yml')).toThrow('Configuration file not found');
    });
  });
});
