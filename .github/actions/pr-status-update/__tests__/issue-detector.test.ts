import { describe, it, expect } from 'vitest';
import {
  detectIssuesFromKeywords,
  detectIssuesFromBranch,
  detectIssues,
} from '../src/issue-detector.js';

describe('detectIssuesFromKeywords', () => {
  it('detects "Closes #123"', () => {
    const result = detectIssuesFromKeywords('Fix something', 'Closes #123');
    expect(result).toEqual([123]);
  });

  it('detects "closes #456" (lowercase)', () => {
    const result = detectIssuesFromKeywords('closes #456', '');
    expect(result).toEqual([456]);
  });

  it('detects "Fixes #789"', () => {
    const result = detectIssuesFromKeywords('Fixes #789', '');
    expect(result).toEqual([789]);
  });

  it('detects "fix #101"', () => {
    const result = detectIssuesFromKeywords('fix #101', '');
    expect(result).toEqual([101]);
  });

  it('detects "fixed #202"', () => {
    const result = detectIssuesFromKeywords('', 'fixed #202');
    expect(result).toEqual([202]);
  });

  it('detects "Resolves #303"', () => {
    const result = detectIssuesFromKeywords('Resolves #303', '');
    expect(result).toEqual([303]);
  });

  it('detects "resolve #404"', () => {
    const result = detectIssuesFromKeywords('resolve #404', '');
    expect(result).toEqual([404]);
  });

  it('detects "resolved #505"', () => {
    const result = detectIssuesFromKeywords('', 'resolved #505');
    expect(result).toEqual([505]);
  });

  it('detects "closed #606"', () => {
    const result = detectIssuesFromKeywords('closed #606', '');
    expect(result).toEqual([606]);
  });

  it('detects multiple issues', () => {
    const result = detectIssuesFromKeywords(
      'Closes #1, Fixes #2',
      'Also resolves #3 and closes #4'
    );
    expect(result).toEqual([1, 2, 3, 4]);
  });

  it('deduplicates same issue mentioned multiple times', () => {
    const result = detectIssuesFromKeywords('Closes #123', 'Also closes #123');
    expect(result).toEqual([123]);
  });

  it('returns empty array when no issues detected', () => {
    const result = detectIssuesFromKeywords('Just a regular PR', 'No issue refs');
    expect(result).toEqual([]);
  });

  it('ignores mentions without keywords (just #123)', () => {
    const result = detectIssuesFromKeywords('Related to #123', 'See #456');
    expect(result).toEqual([]);
  });

  it('handles empty strings', () => {
    const result = detectIssuesFromKeywords('', '');
    expect(result).toEqual([]);
  });

  it('handles mixed case keywords', () => {
    const result = detectIssuesFromKeywords('CLOSES #111', 'FIXES #222');
    expect(result).toEqual([111, 222]);
  });
});

describe('detectIssuesFromBranch', () => {
  it('extracts from "feature/123-add-feature"', () => {
    const result = detectIssuesFromBranch('feature/123-add-feature');
    expect(result).toEqual([123]);
  });

  it('extracts from "fix/456-fix-bug"', () => {
    const result = detectIssuesFromBranch('fix/456-fix-bug');
    expect(result).toEqual([456]);
  });

  it('extracts from "bugfix/789-resolve-issue"', () => {
    const result = detectIssuesFromBranch('bugfix/789-resolve-issue');
    expect(result).toEqual([789]);
  });

  it('extracts from "hotfix/101-urgent-fix"', () => {
    const result = detectIssuesFromBranch('hotfix/101-urgent-fix');
    expect(result).toEqual([101]);
  });

  it('extracts from "feature-202-new-feature" (hyphen separator)', () => {
    const result = detectIssuesFromBranch('feature-202-new-feature');
    expect(result).toEqual([202]);
  });

  it('extracts from "fix303" (no separator)', () => {
    const result = detectIssuesFromBranch('fix303');
    expect(result).toEqual([303]);
  });

  it('returns empty array for non-matching branch', () => {
    const result = detectIssuesFromBranch('main');
    expect(result).toEqual([]);
  });

  it('returns empty array for develop branch', () => {
    const result = detectIssuesFromBranch('develop');
    expect(result).toEqual([]);
  });

  it('returns empty array for release branch', () => {
    const result = detectIssuesFromBranch('release/1.0.0');
    expect(result).toEqual([]);
  });

  it('uses custom pattern when provided', () => {
    const pattern = '^issue-(\\d+)';
    const result = detectIssuesFromBranch('issue-999-custom', pattern);
    expect(result).toEqual([999]);
  });

  it('handles custom pattern with different format', () => {
    const pattern = '(\\d+)-.*';
    const result = detectIssuesFromBranch('42-meaning-of-life', pattern);
    expect(result).toEqual([42]);
  });

  it('returns empty for invalid regex pattern', () => {
    const pattern = '[invalid';
    const result = detectIssuesFromBranch('feature/123', pattern);
    expect(result).toEqual([]);
  });

  it('is case insensitive', () => {
    const result = detectIssuesFromBranch('FEATURE/123-test');
    expect(result).toEqual([123]);
  });
});

describe('detectIssues', () => {
  it('combines issues from keywords and branch', () => {
    const pr = {
      title: 'Closes #1',
      body: 'Fixes #2',
      head: { ref: 'feature/3-test' },
    };
    const result = detectIssues(pr);

    expect(result.fromKeywords).toEqual([1, 2]);
    expect(result.fromBranch).toEqual([3]);
    expect(result.all).toEqual([1, 2, 3]);
  });

  it('deduplicates issues found in both keyword and branch', () => {
    const pr = {
      title: 'Closes #123',
      body: '',
      head: { ref: 'feature/123-same-issue' },
    };
    const result = detectIssues(pr);

    expect(result.fromKeywords).toEqual([123]);
    expect(result.fromBranch).toEqual([123]);
    expect(result.all).toEqual([123]);
  });

  it('handles null body', () => {
    const pr = {
      title: 'Closes #456',
      body: null,
      head: { ref: 'main' },
    };
    const result = detectIssues(pr);

    expect(result.fromKeywords).toEqual([456]);
    expect(result.fromBranch).toEqual([]);
    expect(result.all).toEqual([456]);
  });

  it('returns empty arrays when no issues found', () => {
    const pr = {
      title: 'Just a PR',
      body: 'No issue refs',
      head: { ref: 'main' },
    };
    const result = detectIssues(pr);

    expect(result.fromKeywords).toEqual([]);
    expect(result.fromBranch).toEqual([]);
    expect(result.all).toEqual([]);
  });

  it('uses custom branch pattern when provided', () => {
    const pr = {
      title: 'Test PR',
      body: null,
      head: { ref: 'custom-999-branch' },
    };
    const result = detectIssues(pr, '^custom-(\\d+)');

    expect(result.fromBranch).toEqual([999]);
    expect(result.all).toEqual([999]);
  });

  it('sorts issues numerically', () => {
    const pr = {
      title: 'Fixes #10 and closes #2',
      body: 'Also resolves #5',
      head: { ref: 'feature/1-test' },
    };
    const result = detectIssues(pr);

    expect(result.all).toEqual([1, 2, 5, 10]);
  });
});
