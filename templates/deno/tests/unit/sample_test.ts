/**
 * Sample unit tests demonstrating Deno.test with BDD style.
 */

import { assertEquals } from '@std/assert';
import { describe, it } from '@std/testing/bdd';

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
    assertEquals(add(2, 3), 5);
  });

  it('should add negative numbers', () => {
    assertEquals(add(-1, -1), -2);
  });

  it('should add zero', () => {
    assertEquals(add(5, 0), 5);
  });
});

describe('multiply', () => {
  it('should multiply positive numbers', () => {
    assertEquals(multiply(2, 3), 6);
  });

  it('should multiply by zero', () => {
    assertEquals(multiply(5, 0), 0);
  });

  it('should multiply negative numbers', () => {
    assertEquals(multiply(-2, -3), 6);
  });
});
