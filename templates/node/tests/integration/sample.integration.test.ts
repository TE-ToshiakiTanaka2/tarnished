/**
 * Sample integration tests demonstrating async operations.
 */

import * as fs from 'node:fs/promises';
import * as os from 'node:os';
import * as path from 'node:path';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';

interface JsonData {
  name: string;
  value: number;
  items: number[];
}

/**
 * Read and parse a JSON file.
 */
async function readJsonFile<T>(filePath: string): Promise<T> {
  const content = await fs.readFile(filePath, 'utf-8');
  return JSON.parse(content) as T;
}

/**
 * Write data to a JSON file.
 */
async function writeJsonFile<T>(filePath: string, data: T): Promise<void> {
  await fs.writeFile(filePath, JSON.stringify(data, null, 2), 'utf-8');
}

describe('JSON file operations', () => {
  let tmpDir: string;

  beforeEach(async () => {
    tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), 'test-'));
  });

  afterEach(async () => {
    await fs.rm(tmpDir, { recursive: true, force: true });
  });

  it('should write and read JSON data', async () => {
    const filePath = path.join(tmpDir, 'test.json');
    const testData: JsonData = { name: 'test', value: 42, items: [1, 2, 3] };

    await writeJsonFile(filePath, testData);
    const result = await readJsonFile<JsonData>(filePath);

    expect(result).toEqual(testData);
  });

  it('should handle nested JSON structures', async () => {
    const filePath = path.join(tmpDir, 'nested.json');
    const testData = {
      level1: {
        level2: {
          level3: { value: 'deep' },
        },
      },
    };

    await writeJsonFile(filePath, testData);
    const result = await readJsonFile<typeof testData>(filePath);

    expect(result.level1.level2.level3.value).toBe('deep');
  });
});
