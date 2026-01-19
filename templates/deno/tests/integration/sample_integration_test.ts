/**
 * Sample integration tests demonstrating async operations with Deno.
 */

import { assertEquals } from '@std/assert';
import { afterEach, beforeEach, describe, it } from '@std/testing/bdd';

interface JsonData {
  name: string;
  value: number;
  items: number[];
}

/**
 * Read and parse a JSON file.
 */
async function readJsonFile<T>(filePath: string): Promise<T> {
  const content = await Deno.readTextFile(filePath);
  return JSON.parse(content) as T;
}

/**
 * Write data to a JSON file.
 */
async function writeJsonFile<T>(filePath: string, data: T): Promise<void> {
  await Deno.writeTextFile(filePath, JSON.stringify(data, null, 2));
}

describe('JSON file operations', () => {
  let tmpDir: string;

  beforeEach(async () => {
    tmpDir = await Deno.makeTempDir({ prefix: 'test-' });
  });

  afterEach(async () => {
    await Deno.remove(tmpDir, { recursive: true });
  });

  it('should write and read JSON data', async () => {
    const filePath = `${tmpDir}/test.json`;
    const testData: JsonData = { name: 'test', value: 42, items: [1, 2, 3] };

    await writeJsonFile(filePath, testData);
    const result = await readJsonFile<JsonData>(filePath);

    assertEquals(result, testData);
  });

  it('should handle nested JSON structures', async () => {
    const filePath = `${tmpDir}/nested.json`;
    const testData = {
      level1: {
        level2: {
          level3: { value: 'deep' },
        },
      },
    };

    await writeJsonFile(filePath, testData);
    const result = await readJsonFile<typeof testData>(filePath);

    assertEquals(result.level1.level2.level3.value, 'deep');
  });
});
