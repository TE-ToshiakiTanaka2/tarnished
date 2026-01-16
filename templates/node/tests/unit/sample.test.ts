/**
 * Sample unit tests demonstrating Vitest usage.
 */

import { describe, expect, it } from 'vitest';

/**
 * Add two numbers.
 */
function add(a: number, b: number): number {
  return a + b;
}

/**
 * Multiply two numbers.
 */
function multiply(a: number, b: number): number {
  return a * b;
}

describe('add', () => {
  it('should add positive numbers', () => {
    expect(add(2, 3)).toBe(5);
  });

  it('should add negative numbers', () => {
    expect(add(-1, -1)).toBe(-2);
  });

  it('should add zero', () => {
    expect(add(5, 0)).toBe(5);
  });
});

describe('multiply', () => {
  it('should multiply positive numbers', () => {
    expect(multiply(2, 3)).toBe(6);
  });

  it('should multiply by zero', () => {
    expect(multiply(5, 0)).toBe(0);
  });

  it('should multiply negative numbers', () => {
    expect(multiply(-2, -3)).toBe(6);
  });
});
