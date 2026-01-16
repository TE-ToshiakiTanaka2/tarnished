import { describe, it, expect, vi, beforeEach } from 'vitest';
import { GraphQLClient } from '../src/graphql/client.js';
import {
  GET_ORGANIZATION_PROJECT,
  GET_USER_PROJECT,
  GET_PROJECT_ITEMS,
} from '../src/graphql/queries.js';
import {
  ADD_PROJECT_ITEM,
  UPDATE_SINGLE_SELECT_FIELD,
  UPDATE_TEXT_FIELD,
  UPDATE_NUMBER_FIELD,
} from '../src/graphql/mutations.js';

// Mock @actions/core
vi.mock('@actions/core', () => ({
  info: vi.fn(),
  warning: vi.fn(),
  error: vi.fn(),
  debug: vi.fn(),
}));

// Mock @octokit/graphql
vi.mock('@octokit/graphql', () => ({
  graphql: {
    defaults: vi.fn(() => vi.fn()),
  },
}));

describe('graphql/queries', () => {
  it('should have GET_ORGANIZATION_PROJECT query', () => {
    expect(GET_ORGANIZATION_PROJECT).toContain('organization');
    expect(GET_ORGANIZATION_PROJECT).toContain('projectV2');
    expect(GET_ORGANIZATION_PROJECT).toContain('fields');
  });

  it('should have GET_USER_PROJECT query', () => {
    expect(GET_USER_PROJECT).toContain('user');
    expect(GET_USER_PROJECT).toContain('projectV2');
    expect(GET_USER_PROJECT).toContain('fields');
  });

  it('should have GET_PROJECT_ITEMS query', () => {
    expect(GET_PROJECT_ITEMS).toContain('items');
    expect(GET_PROJECT_ITEMS).toContain('content');
    expect(GET_PROJECT_ITEMS).toContain('pageInfo');
  });
});

describe('graphql/mutations', () => {
  it('should have ADD_PROJECT_ITEM mutation', () => {
    expect(ADD_PROJECT_ITEM).toContain('addProjectV2ItemById');
    expect(ADD_PROJECT_ITEM).toContain('projectId');
    expect(ADD_PROJECT_ITEM).toContain('contentId');
  });

  it('should have UPDATE_SINGLE_SELECT_FIELD mutation', () => {
    expect(UPDATE_SINGLE_SELECT_FIELD).toContain('updateProjectV2ItemFieldValue');
    expect(UPDATE_SINGLE_SELECT_FIELD).toContain('singleSelectOptionId');
  });

  it('should have UPDATE_TEXT_FIELD mutation', () => {
    expect(UPDATE_TEXT_FIELD).toContain('updateProjectV2ItemFieldValue');
    expect(UPDATE_TEXT_FIELD).toContain('text');
  });

  it('should have UPDATE_NUMBER_FIELD mutation', () => {
    expect(UPDATE_NUMBER_FIELD).toContain('updateProjectV2ItemFieldValue');
    expect(UPDATE_NUMBER_FIELD).toContain('number');
  });
});

describe('graphql/client', () => {
  it('should create client with token', () => {
    const client = new GraphQLClient('test-token');
    expect(client).toBeDefined();
  });
});
