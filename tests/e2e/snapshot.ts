/**
 * Tiny JSON snapshot helper. Playwright's built-in `toMatchSnapshot`
 * targets binary blobs (images, PDFs); for readable DOM diffs we want
 * plain JSON files committed to the repo.
 *
 * Usage:
 *
 *     const dom = await dumpDomJson(page, '.jp-OutputArea');
 *     matchJsonSnapshot(dom, 'rich-display-html');
 *
 * On the first run (or when UPDATE_SNAPSHOTS=1), the file is written
 * to disk. On subsequent runs, the file is read and compared with
 * `expect(actual).toEqual(expected)`.
 */

import * as fs from 'fs';
import * as path from 'path';
import { expect } from '@playwright/test';

const SNAP_DIR = path.join(__dirname, '__snapshots__');

function ensureDir(): void {
  if (!fs.existsSync(SNAP_DIR)) fs.mkdirSync(SNAP_DIR, { recursive: true });
}

function snapshotPath(name: string): string {
  // Prevent accidental path traversal from a test name.
  const safe = name.replace(/[^a-z0-9._-]+/gi, '_');
  return path.join(SNAP_DIR, `${safe}.json`);
}

export function matchJsonSnapshot(actual: unknown, name: string): void {
  ensureDir();
  const file = snapshotPath(name);
  const serialized = JSON.stringify(actual, null, 2) + '\n';

  const update = Boolean(process.env.UPDATE_SNAPSHOTS);
  const exists = fs.existsSync(file);

  if (update || !exists) {
    fs.writeFileSync(file, serialized);
    // Under `-- --reporter=list` Playwright swallows console.log from
    // tests, so also mark the test as passing via a soft assertion.
    if (!exists) {
      // eslint-disable-next-line no-console
      console.log(`[snapshot] wrote new baseline: ${path.relative(process.cwd(), file)}`);
    } else {
      // eslint-disable-next-line no-console
      console.log(`[snapshot] updated: ${path.relative(process.cwd(), file)}`);
    }
    return;
  }

  const expected = JSON.parse(fs.readFileSync(file, 'utf-8'));
  expect(actual, `snapshot mismatch for ${name} (file: ${file})`).toEqual(expected);
}
